import Foundation

@MainActor
@Observable
final class ManageLanguageViewModel {

    struct LanguageRow: Identifiable, Hashable {
        let language: LanguageCode
        let level: LangGrade
        let progressPercent: Int
        let subtitle: String
        let hasProgress: Bool
        var id: LanguageCode { language }
    }

    let user: UserEntity
    let repository: UserRepository

    /// Локальный выбор в UI. Записывается в user.settings только при commit().
    var selectedLanguage: LanguageCode
    /// Идёт ли сейчас `commit()` (PATCH + syncMe). View использует чтобы
    /// заблокировать кнопку/показать спиннер и не дать dismiss до финиша.
    private(set) var isCommitting: Bool = false

    init(user: UserEntity, repository: UserRepository) {
        self.user = user
        self.repository = repository
        self.selectedLanguage = user.settings.currentLearningLanguage
    }

    // MARK: - Derived

    var languages: [LanguageRow] {
        // Фиксированный порядок [es, en] — тот же что и в Profile Learning plan.
        [LanguageCode.es, .en].map { languageRow(for: $0) }
    }

    var currentLanguage: LanguageCode { user.settings.currentLearningLanguage }

    var translationLanguage: LanguageCode { user.settings.translationLanguage }

    var hasChange: Bool { selectedLanguage != currentLanguage }

    var bottomButtonTitle: String {
        let name = selectedLanguage.displayTitle
        if hasChange {
            return L10n.tr("lang.switch_to", "Switch to %@", name)
        }
        return L10n.tr("lang.keep_learning", "Keep learning %@", name)
    }

    // MARK: - Actions

    func select(_ language: LanguageCode) {
        selectedLanguage = language
    }

    /// Меняет активный язык. Оптимистично пишет локально, потом ждёт
    /// PATCH + syncMe и только после этого возвращает управление View,
    /// чтобы dismiss произошёл ПОСЛЕ завершения сетевого цикла.
    ///
    /// Гейт `MeMapper.suppressCurrentLearningLanguageMirror` на всё время
    /// операции блокирует зеркалирование серверного `currentLearningLanguage`
    /// в user.settings — это защита от параллельного `syncMe` (например
    /// `HomeVM.onAppear`), который может прилететь пока наш PATCH ещё в
    /// полёте и вернуть старое значение, затерев только что сделанный
    /// клиентом выбор. См. верификацию бага «после re-entry язык
    /// сбросился на английский».
    func commit() async {
        guard hasChange, !isCommitting else { return }
        isCommitting = true
        defer { isCommitting = false }

        let target = selectedLanguage
        user.settings.currentLearningLanguage = target
        user.updatedAt = .now
        repository.save()

        MeMapper.suppressCurrentLearningLanguageMirror = true
        defer { MeMapper.suppressCurrentLearningLanguageMirror = false }

        // 1) Если LearningProfile для target-языка ещё не существует —
        //    создаём через `POST /me/learning-profiles`. Без этого шага
        //    сервер после смены settings.currentLearningLanguage не
        //    автосоздаёт профиль, `user.learningProfiles` остаётся без
        //    Spanish, и Profile-карточка пуста → юзер видит «переключение
        //    не сработало».
        let needsCreate = !user.learningProfiles.contains(where: { $0.languageCode == target })
        if needsCreate {
            _ = try? await MeAPI.startLanguage(.init(
                languageCode: target.rawValue,
                level: LangGrade.aOne.rawValue,
                goal: LearningGoal.somethingElse.rawValue
            ))
        }

        // 2) Смена активного языка.
        _ = try? await MeAPI.updateSettings(.init(
            currentLearningLanguage: target.rawValue
        ))
        await AuthService.shared.syncMe()
    }

    // MARK: - Private

    private func languageRow(for lang: LanguageCode) -> LanguageRow {
        guard let profile = user.learningProfiles.first(where: { $0.languageCode == lang }) else {
            // Профиля ещё нет — язык не начинался.
            return LanguageRow(
                language: lang,
                level: .aOne,
                progressPercent: 0,
                subtitle: L10n.tr("lang.no_progress", "Nothing done yet — starts from unit 1"),
                hasProgress: false
            )
        }
        let done = profile.completedStepIds.count
        // Реальный total = все шаги уровня из серверного контента (тот же
        // расчёт, что в `ProfileViewModel.progressPercent`) — раньше здесь
        // стояло hardcoded `approxTotalSteps = 8`, из-за чего один и тот же
        // English показывал разные проценты в Profile и в Manage.
        let bundle = ContentService.shared.cachedBundle(for: lang)
        let totalSteps = bundle.map {
            ContentMapper.map($0)
                .filter { $0.grade == profile.level }
                .flatMap(\.steps)
                .count
        } ?? 0
        let percent = totalSteps > 0
            ? Int((Double(min(done, totalSteps)) / Double(totalSteps) * 100).rounded())
            : 0

        // Total units из того же серверного контента для сабтайтла
        // «Unit N of M · started in …». В fallback (кэш пуст) даём 8 как
        // безопасный дефолт — только на первый заход до `GET /content`.
        let totalUnits: Int = bundle.map {
            ContentMapper.map($0).filter { $0.grade == profile.level }.count
        } ?? 8

        let subtitle: String
        if done == 0 {
            subtitle = L10n.tr("lang.no_progress", "Nothing done yet — starts from unit 1")
        } else {
            let currentUnitOrdinal = min(profile.completedUnitIds.count + 1, max(1, totalUnits))
            let month = localizedMonthName(for: profile.startedAt)
            subtitle = L10n.tr("lang.progress_subtitle",
                               "Unit %1$lld of %2$lld · started in %3$@",
                               currentUnitOrdinal, totalUnits, month)
        }

        return LanguageRow(
            language: lang,
            level: profile.level,
            progressPercent: percent,
            subtitle: subtitle,
            hasProgress: done > 0
        )
    }

    private func localizedMonthName(for date: Date) -> String {
        let uiLang = UserDefaults.standard.string(forKey: "app.uiLanguage") ?? "en"
        let f = DateFormatter()
        f.locale = Locale(identifier: uiLang)
        f.dateFormat = "LLLL"
        return f.string(from: date).capitalized(with: Locale(identifier: uiLang))
    }
}

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SubscriptionService.self) private var premiumService
    @State private var auth = AuthService.shared
    @State private var currentUser: UserEntity?

    var body: some View {
        @Bindable var service = premiumService
        content
            .onAppear { hydrateUser() }
            .onChange(of: auth.currentUser?.id) { _, _ in hydrateUser() }
            .onChange(of: auth.currentMe?.id) { _, _ in
                hydrateUser()
                Task { await PushTokenService.shared.syncIfPossible() }
            }
            // Каждый успешный syncMe (в т.ч. после завершения урока) →
            // зеркалим MeDTO в SwiftData (`MeMapper.upsert`). onChange по
            // `.id` тут не работает — id тот же, но нам нужно перезаписать
            // вложенные completedStepIds/streak/hearts.
            .onChange(of: auth.meSyncNonce) { _, _ in hydrateUser() }
            .onChange(of: scenePhase) { _, new in
                // Возврат из бэкграунда — освежаем зеркало сервера (hearts,
                // streak, isPremium могли измениться в webhook'ах пока нас не было).
                if new == .active, auth.isLoggedIn {
                    Task { await auth.syncMe() }
                    Task { await PushTokenService.shared.syncIfPossible() }
                }
            }
            .fullScreenCover(isPresented: $service.isPaywallShown) {
                paywallDestination
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if auth.isRestoring {
            // Пока валидируем токены при холодном старте — показываем
            // сплэш, а не AuthGate. Иначе юзер видит AuthGate на секунду
            // и по инерции жмёт Sign-In, создавая новую сессию поверх
            // валидной. Restore выставит isRestoring=false, дальше пойдёт
            // либо AuthGate (нет токенов), либо Home.
            ZStack {
                Color.black.ignoresSafeArea()
                ProgressView().tint(.white)
            }
        } else if !auth.isLoggedIn {
            AuthGateView()
        } else if let user = currentUser {
            if user.isOnboardingDone {
                HomeView(user: user)
            } else {
                OnboardingRootView(
                    user: user,
                    repository: UserRepository(context: context),
                    // Никакого автоматического пейвола после онборда.
                    // Пейвол `.onboarding` показывается ТОЛЬКО когда юзер
                    // сам тапает Start с premium-teacher (кнопка в
                    // OnboardingRootView). Free teacher → сразу Home.
                    onFinished: { }
                )
            }
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - Paywalls

    @ViewBuilder
    private var paywallDestination: some View {
        // Приоритет: `pendingTeacher` (что-то выбранное но ещё не купленное) →
        // saved selectedTeacher → emma. Логика превью паейвола на видео/фон.
        let teacher = premiumService.pendingTeacher
            ?? currentUser?.settings.selectedTeacher
            ?? .emma
        switch premiumService.currentPaywallId {
        case .onboarding, .in_lessons:
            // Figma 762:2445 (B_Paywall). Триггеры: онбординг после выбора
            // premium teacher, свап teacher, все 3 подсказки исчерпаны.
            UnifiedPaywallView()
        case .free_chat:
            // Figma 762:2625 (continue_dialog_paywall). Лимит Talk-квоты.
            ContinueDialogPaywallView()
        case .dating:
            // Figma 762:2511 (daiting_paywall). Конец date-шага —
            // предложение продолжить в свободном чате.
            DatingContinuePaywallView()
        case .lesson_end:
            // Figma 762:2568 (lesson_end). Конец обычного шага —
            // «You stopped one step before the good part».
            LessonEndPaywallView()
        case .none:
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - Session hydration

    /// Приводит локальную SwiftData-модель в соответствие с сервером.
    /// - логаут → currentUser = nil, RootView покажет AuthGate;
    /// - логин: если серверный документ уже пришёл (`auth.currentMe`) —
    ///   зеркалим его; иначе временно рисуем скелет из `AuthUser` (id/email)
    ///   пока `syncMe` не завершится.
    private func hydrateUser() {
        guard let authUser = auth.currentUser else {
            currentUser = nil
            return
        }
        let repo = UserRepository(context: context)
        if let me = auth.currentMe {
            currentUser = repo.upsert(from: me, provider: authUser.provider)
        } else {
            currentUser = repo.upsert(from: authUser)
        }
    }
}

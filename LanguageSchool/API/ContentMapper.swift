import Foundation

/// Приводит серверный `ContentBundleDTO` к клиентским моделям `[Unit]/[Step]`.
///
/// Правила:
///  - Юниты сортируются по `order` и мапятся один-в-один.
///  - `Unit.grade` мы берём из `unit.level` (сервер отдаёт `aOne/aTwo/bOne`).
///  - `unlockRule` берётся из `unlockRule.kind = afterUnit|afterStep`.
///  - Неизвестные `kind` шага → `.grammar` как безопасный дефолт (шаг
///    выглядит как «упражнение», приложение не крашится).
///  - `Step.payload` пробрасывается как есть — LessonViewModel разбирает
///    по `step.kind`.
enum ContentMapper {

    static func map(_ dto: ContentBundleDTO) -> [Unit] {
        dto.units
            .sorted { $0.order < $1.order }
            .map(mapUnit)
    }

    private static func mapUnit(_ dto: ContentUnitDTO) -> Unit {
        let grade = LangGrade(rawValue: dto.level ?? "") ?? .aOne
        let steps = dto.steps
            .sorted { $0.order < $1.order }
            .map(mapStep)

        return Unit(
            id: dto.id,
            order: dto.order,
            title: dto.title,
            iconName: (dto.iconName?.isEmpty == false) ? dto.iconName! : "book.closed",
            isPremium: dto.isPremium ?? false,
            grade: grade,
            unlockRule: mapUnitUnlock(dto.unlockRule),
            steps: steps
        )
    }

    private static func mapUnitUnlock(_ rule: UnlockRuleDTO?) -> UnitUnlockRule? {
        guard let rule else { return nil }
        if case .afterUnit(let id) = rule { return .afterUnit(id) }
        return nil
    }

    private static func mapStepUnlock(_ rule: UnlockRuleDTO?) -> StepUnlockRule? {
        guard let rule else { return nil }
        if case .afterStep(let id) = rule { return .afterStep(id) }
        return nil
    }

    private static func mapStep(_ dto: ContentStepDTO) -> Step {
        let kind = StepKind(rawValue: dto.kind) ?? .grammar
        return Step(
            id: dto.id,
            order: dto.order,
            kind: kind,
            title: dto.title,
            subtitle: dto.subtitle,
            unlockRule: mapStepUnlock(dto.unlockRule),
            audioUrl: nil,
            payload: dto.payload
        )
    }
}

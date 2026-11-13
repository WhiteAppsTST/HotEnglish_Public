import SwiftUI

/// Универсальная карточка юнита с раскрытием списка шагов.
/// Используется и на HomeView, и на AllUnitsView — единая точка правды
/// по внешнему виду и логике expand/step/Continue.
///
/// Все состояния/цвета копируют HomeView-версию, чтобы визуально идентично.
struct UnitCardView: View {
    @Environment(SubscriptionService.self) private var premium
    let vm: HomeViewModel
    let unit: Unit
    let now: Date
    let animation: Namespace.ID

    var body: some View {
        let locked = vm.isUnitLocked(unit)
        let completed = vm.isUnitCompleted(unit)
        let expanded = vm.isExpanded(unit) && !locked

        VStack(spacing: 0) {
            Button {
                if !locked { vm.toggleExpand(unit) }
            } label: {
                header(locked: locked, completed: completed, expanded: expanded)
            }
            .buttonStyle(.plain)
            .disabled(locked)

            if expanded {
                stepList
                    .padding(.top, 10)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .padding(.top, expanded ? 14 : 15)
        .padding(.bottom, expanded ? 18 : 15)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#19191D")))
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }
}

// MARK: - Header
private extension UnitCardView {

    @ViewBuilder
    func header(locked: Bool, completed: Bool, expanded: Bool) -> some View {
        HStack(spacing: 12) {
            iconCircle(locked: locked)

            VStack(alignment: .leading, spacing: 2) {
                Text("UNIT \(unit.order)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(labelColor(locked: locked, completed: completed))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(unit.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(locked ? Color(hex: "#9A9AA4") : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            trailing(locked: locked, completed: completed, expanded: expanded)
        }
    }

    @ViewBuilder
    func iconCircle(locked: Bool) -> some View {
        Group {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#9A9AA4"))
            } else if unit.isIconEmoji {
                Text(unit.iconName)
                    .font(.system(size: 20))
            } else {
                Image(systemName: unit.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 40, height: 40)
        .background(Circle().fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    func trailing(locked: Bool, completed: Bool, expanded: Bool) -> some View {
        if locked {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#9A9AA4"))

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        } else if completed {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(unit.steps.count)/\(unit.steps.count)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(hex: "#32D74B"))

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        } else {
            HStack(spacing: 8) {
                Text("\(vm.completedStepCount(in: unit))/\(unit.steps.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FF2E7E"))

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    func labelColor(locked: Bool, completed: Bool) -> Color {
        if locked { return Color(hex: "#9A9AA4") }
        if completed { return Color(hex: "#32D74B") }
        return Color(hex: "#FF2E7E")
    }
}

// MARK: - Step list
private extension UnitCardView {

    var stepList: some View {
        VStack(spacing: 0) {
            ForEach(Array(unit.steps.enumerated()), id: \.element.id) { pair in
                stepRow(pair.element, index: pair.offset, total: unit.steps.count)
            }
        }
    }

    @ViewBuilder
    func stepRow(_ step: Step, index: Int, total: Int) -> some View {
        let completed = vm.isStepCompleted(step)
        let locked = vm.isStepLocked(step)
        let current = vm.isCurrentStep(step, in: unit)
        let quotaLocked = current && vm.isQuotaExhausted

        HStack(alignment: .center, spacing: 12) {
            markerColumn(
                order: step.order,
                completed: completed,
                current: current,
                locked: locked,
                showTopLine: index > 0,
                showBottomLine: index < total - 1
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(locked ? Color(hex: "#9A9AA4") : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(step.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#9A9AA4"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            stepTrailing(step, current: current, completed: completed, locked: locked, quotaLocked: quotaLocked)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(stepRowBackground(current: current, quotaLocked: quotaLocked))
        )
    }

    func stepRowBackground(current: Bool, quotaLocked: Bool) -> Color {
        // Figma 373:3151 и 425:7113: строка активного шага в обоих
        // состояниях остаётся pink@14%. Меняется только trailing:
        // Continue → timer pill.
        if current { return Color(hex: "#FF2E7E").opacity(0.14) }
        return .clear
    }

    @ViewBuilder
    func markerColumn(
        order: Int, completed: Bool, current: Bool, locked: Bool,
        showTopLine: Bool, showBottomLine: Bool
    ) -> some View {
        VStack(spacing: 0) {
            if showTopLine {
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 2).frame(maxHeight: .infinity)
            } else {
                Color.clear.frame(width: 2).frame(maxHeight: .infinity)
            }

            Circle()
                .fill(markerFill(completed: completed, current: current, locked: locked))
                .frame(width: 26, height: 26)
                .overlay { markerContent(order: order, completed: completed, locked: locked) }

            if showBottomLine {
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 2).frame(maxHeight: .infinity)
            } else {
                Color.clear.frame(width: 2).frame(maxHeight: .infinity)
            }
        }
        .frame(width: 26)
    }

    @ViewBuilder
    func markerContent(order: Int, completed: Bool, locked: Bool) -> some View {
        if completed {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        } else if locked {
            Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: "#9A9AA4"))
        } else {
            Text("\(order)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        }
    }

    func markerFill(completed: Bool, current: Bool, locked: Bool) -> Color {
        if completed { return Color(hex: "#32D74B") }
        if current { return .lsPink }
        if locked { return Color.white.opacity(0.05) }
        return Color.white.opacity(0.1)
    }

    @ViewBuilder
    func stepTrailing(_ step: Step, current: Bool, completed: Bool, locked: Bool, quotaLocked: Bool) -> some View {
        if completed {
            Text("Done")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#32D74B"))
        } else if quotaLocked {
            quotaTimerPill
        } else if current {
            // Continue доступен ТОЛЬКО у активного (текущего) шага.
            // Locked/future шаги — без кнопки, только маркер.
            NavigationLink {
                LessonView(unitId: unit.id, step: step, teacher: vm.teacher, language: vm.language, user: vm.user)
                    .navigationTransition(.zoom(sourceID: "step_\(step.id)", in: animation))
            } label: {
                HStack(spacing: 4) {
                    Text("Continue").font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(HomeContinuePillStyle())
            .matchedTransitionSource(id: "step_\(step.id)", in: animation)
        }
    }

    /// Figma 425:7113 «Button — Continue» quota-locked: 90×44 pill cr=22,
    /// fill white@8%, серый текст "14h 20m" 13pt + серый chevron.
    /// По ТЗ — тап открывает пейвол (`.in_lessons`): free-юзеру каждый раз,
    /// пока таймер не спал, показываем предложение оформить подписку.
    var quotaTimerPill: some View {
        Button {
            premium.showPaywall(.in_lessons)
        } label: {
            HStack(spacing: 4) {
                Text(vm.quotaTimeRemaining(at: now) ?? "24h 0m")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Экран со списком всех юнитов курса. Figma 374:6045.
///
/// Открывается из HomeView по кнопке "All units". Использует общий
/// компонент `UnitCardView` — тот же, что и на главном экране, только
/// показывает весь список, а не один активный юнит. Юниты раскрываются
/// и показывают шаги с Continue-кнопкой.
///
/// Перед первым premium-юнитом вставлен разделитель "Dates & more with Premium".
struct AllUnitsView: View {
    @Environment(\.dismiss) private var dismiss
    let vm: HomeViewModel
    @Namespace private var animation

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 8)
                .padding(.bottom, 12)

            ScrollView {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    LazyVStack(spacing: 10) {
                        rowsView(now: context.date)

                        Text("Finish a unit to open the next  ·  dates need 5 ♥")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color(hex: "#5A5A63"))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .background(Color(hex: "#0B0B0D").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Юниты + premium-divider перед первым `isPremium` юнитом.
    @ViewBuilder
    private func rowsView(now: Date) -> some View {
        let firstPremiumId = vm.units.first(where: \.isPremium)?.id
        ForEach(vm.units) { unit in
            if unit.id == firstPremiumId {
                premiumDivider
            }
            UnitCardView(vm: vm, unit: unit, now: now, animation: animation)
        }
    }

    private var premiumDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            Text("Dates & more with Premium")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .fixedSize()
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
        .frame(height: 30)
        .padding(.vertical, 4)
    }

    private var header: some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)

            Text("All units")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 44)
    }
}

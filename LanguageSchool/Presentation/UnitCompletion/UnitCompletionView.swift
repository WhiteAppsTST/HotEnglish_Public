import SwiftUI

/// Данные для экрана завершения юнита (Figma 373:1316).
/// TODO: тянуть с бэка после completion юнита.
struct UnitCompletionData: Hashable {
    let unitNumber: Int
    let quote: String
    /// 0…5 — сколько сердец у Emma сейчас (после этого юнита).
    let hearts: Int
    /// Сколько сердец добавилось за этот юнит (для «+N» pill).
    let heartsBonus: Int
    let level: Int
    let progressSubtitle: String
    let newWordsCount: Int
    let pronunciationScore: Int
    let minutesSpent: Int
    let nextUnitNumber: Int
    let nextUnitTitle: String
    let teacher: TeacherProfile
}

extension UnitCompletionData {
    /// Мок под Figma 373:1316. TODO: заменить на реальные данные.
    static let mock = UnitCompletionData(
        unitNumber: 3,
        quote: "\"You just held a whole conversation in a bar. In Spanish. With me.\"",
        hearts: 4,
        heartsBonus: 1,
        level: 4,
        progressSubtitle: "She stopped correcting your accent and started teasing you about it.",
        newWordsCount: 8,
        pronunciationScore: 86,
        minutesSpent: 12,
        nextUnitNumber: 4,
        nextUnitTitle: "Making plans",
        teacher: .emma
    )
}

/// Экран завершения юнита. Fullscreen photo учительницы, поверх снизу —
/// достижения, level up card, стата и CTA.
struct UnitCompletionView: View {
    let data: UnitCompletionData
    let onDateTap: () -> Void
    let onNextUnitTap: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var premium

    var body: some View {
        ZStack {
            Image(data.teacher.chatHeroImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Оба скрима по Figma 373:1316: top 150pt (black@0.5→0),
            // bottom 600pt (тёмный градиент). Без них текст поверх светлой
            // фотографии проваливается.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.5), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 150)

                Spacer(minLength: 0)

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 10/255, green: 10/255, blue: 13/255).opacity(0), location: 0),
                        .init(color: Color(red: 10/255, green: 10/255, blue: 13/255).opacity(0.75), location: 0.5),
                        .init(color: Color(red: 10/255, green: 10/255, blue: 13/255).opacity(0.98), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 600)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) { closeButton.padding(16) }
        .overlay(alignment: .bottom) { bottomStack }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !premium.isActiveSubscription else { return }
            premium.showPaywall(.dating)
        }
    }
}

// MARK: - Sub-views
private extension UnitCompletionView {

    var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.40)))
        }
        .buttonStyle(.plain)
    }

    var bottomStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            unitDonePill
            quoteText
            heartsCard
            statsRow
            dateButton
            openNextUnitSubtitle
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    /// Зелёная pill «✓ UNIT N DONE» — Figma: 27pt height, cr=13, text 11/590.
    var unitDonePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
            Text("UNIT \(data.unitNumber) DONE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(height: 27)
        .background(Capsule().fill(Color(hex: "#31D64A")))
    }

    var quoteText: some View {
        Text(data.quote)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Affinity gain card — Figma: bg #FF2D7D@14%, cr=16.
    var heartsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < data.hearts ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.lsPink)
                    }
                }
                if data.heartsBonus > 0 {
                    Text("+\(data.heartsBonus)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.lsPink))
                }
                Spacer()
                Text("LV \(data.level)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.lsPink)
            }
            Text(data.progressSubtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "#D8D8E0"))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.lsPink.opacity(0.14)))
    }

    var statsRow: some View {
        HStack(spacing: 12) {
            statPart(number: data.newWordsCount, label: "new words")
            dot
            statPart(number: data.pronunciationScore, label: "pronunciation")
            dot
            statPart(number: data.minutesSpent, label: "minutes")
        }
    }

    func statPart(number: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(number)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
        }
    }

    var dot: some View {
        Circle().fill(Color(hex: "#9A9AA3")).frame(width: 3, height: 3)
    }

    var dateButton: some View {
        Button {
            onDateTap()
        } label: {
            HStack(spacing: 8) {
                Text("Date with \(data.teacher.name)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Image(systemName: "heart")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(Color.lsPink))
        }
        .buttonStyle(.plain)
    }

    var openNextUnitSubtitle: some View {
        Button {
            onNextUnitTap()
        } label: {
            Text("Open Unit \(data.nextUnitNumber) · \(data.nextUnitTitle)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }
}

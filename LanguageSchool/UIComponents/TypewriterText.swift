import SwiftUI

/// Печатает текст посимвольно. Скорость в символах в секунду.
/// Если `text` меняется — перезапускает анимацию с начала.
struct TypewriterText: View {
    let text: String
    var charactersPerSecond: Double = 45
    var font: Font = .system(size: 15)
    var color: Color = .white

    @State private var visibleCount = 0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Text(String(text.prefix(visibleCount)))
            .font(font)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { animate() }
            .onChange(of: text) { _, _ in animate() }
            .onDisappear { animationTask?.cancel() }
    }

    private func animate() {
        animationTask?.cancel()
        visibleCount = 0
        guard !text.isEmpty else { return }
        let total = text.count
        let intervalNs = UInt64(max(0.005, 1.0 / charactersPerSecond) * 1_000_000_000)
        animationTask = Task { @MainActor in
            while visibleCount < total {
                try? await Task.sleep(nanoseconds: intervalNs)
                if Task.isCancelled { return }
                visibleCount += 1
            }
        }
    }
}

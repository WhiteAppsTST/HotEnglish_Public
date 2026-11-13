import SwiftUI
import SwiftData
import Combine

struct TalkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var premium
    @State private var vm: TalkViewModel
    @State private var avatar = AvatarPlayer()
    @State private var isExpanded: Bool = false
    @FocusState private var isInputFocused: Bool
    @Namespace private var animation

    fileprivate static let typingIndicatorId = "typing-indicator"

    /// Высота hero-видео в обычном режиме (Figma 373:4216 "Video — Emma" 420pt).
    private let normalHeroHeight: CGFloat = 420

    init(user: UserEntity, repository: UserRepository, context: ModelContext) {
        _vm = State(
            wrappedValue: TalkViewModel(user: user, repository: repository, context: context)
        )
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else {
                normalBody
            }
        }
        .background(Color(hex: "#0A0A0D").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.onAppear() }
        .onAppear { configureAvatar() }
        .onDisappear {
            vm.onDisappear()
            avatar.stop()
        }
        .onChange(of: vm.reactionTick) { _, _ in playReaction() }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { vm.error != nil },
                set: { if !$0 { vm.error = nil } }
            )
        ) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .onChange(of: vm.showPaywall) { _, isOn in
            guard isOn else { return }
            vm.showPaywall = false
            premium.showPaywall(.free_chat)
        }
    }

    /// Настраивает базовый idle-loop учителя (silent) при появлении экрана.
    private func configureAvatar() {
        if let idle = vm.teacher.lessonVideo(.idle) {
            avatar.setBase(video: idle)
        }
    }

    /// Играет reaction-видео с последнего GPT-ответа + опциональный SFX
    /// (flirting/smile/thinking) — см. `TalkReaction.soundEffect`.
    /// Полноценный TTS-голос Emma — это отдельная premium-фича.
    private func playReaction() {
        guard let reaction = vm.lastReaction else { return }
        guard let video = vm.teacher.lessonVideo(reaction.lessonState) else { return }
        let audio = reaction.soundEffect.flatMap { vm.teacher.sound($0) }
        avatar.playOnce(video: video, audio: audio)
    }
}

// MARK: - Normal layout (Figma 373:4216)
private extension TalkView {

    var normalBody: some View {
        VStack(spacing: 0) {
            heroBlock
                .frame(height: normalHeroHeight)
                .clipped()

            sheetBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: "#0A0A0D"))
        }
        .ignoresSafeArea(.container, edges: .top)
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
    }

    /// Видео + top-scrim + плавающие nav-pills.
    var heroBlock: some View {
        ZStack(alignment: .top) {
            AvatarPlayerView(player: avatar.videoPlayer)

            LinearGradient(
                colors: [Color.black.opacity(0.5), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)

            navPillsRow
                .padding(.horizontal, 16)
                .padding(.top, 60)
        }
    }

    /// Всё под hero: grabber, quota+hearts row, messages, input bar.
    var sheetBlock: some View {
        VStack(spacing: 0) {
            grabber

            quotaRow
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)

            messagesList

            interactionPanel
        }
    }

    var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.22))
            .frame(width: 36, height: 4)
            .padding(.top, 8)
    }
}

// MARK: - Expanded layout (Figma 373:3603, no hints button)
private extension TalkView {

    var expandedBody: some View {
        ZStack {
            // Полноэкранное видео + оба скрима + чат посередине. Всё в одном
            // ZStack чтобы scrim'ы доходили до физических краёв экрана.
            AvatarPlayerView(player: avatar.videoPlayer)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.5), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 160)

                Spacer(minLength: 0)

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 10/255, green: 10/255, blue: 13/255).opacity(0), location: 0),
                        .init(color: Color(red: 10/255, green: 10/255, blue: 13/255).opacity(0.85), location: 0.6),
                        .init(color: Color(red: 10/255, green: 10/255, blue: 13/255).opacity(0.98), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 300)
            }
            .allowsHitTesting(false)

        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            navPillsRow
                .padding(.horizontal, 16)
                .padding(.top, 20)   // раньше 60 — подняли на 40pt по требованию
        }
        // Chat приклеен к низу — сразу над interaction panel с зазором 25pt.
        // Ограничен по высоте, чтобы не перекрывать лицо учителя.
        .overlay(alignment: .bottom) {
            messagesList
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: 380)
                .padding(.bottom, 135) // высота interaction panel + 25pt gap
        }
        .overlay(alignment: .bottom) {
            interactionPanel
                .padding(.bottom, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
    }
}

// MARK: - Nav pills (used in both layouts)
private extension TalkView {

    var navPillsRow: some View {
        HStack(spacing: 10) {
            navPillButton(systemImage: "xmark") { dismiss() }

            HStack {
                Text("Free talk")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(Color.black.opacity(0.42)))

            Spacer(minLength: 0)

            if vm.speech.isRecording {
                listeningPill
            }

            navPillButton(
                systemImage: isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right"
            ) {
                withAnimation(.easeInOut(duration: 0.33)) { isExpanded.toggle() }
            }
        }
    }

    func navPillButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.42)))
        }
        .buttonStyle(.plain)
    }

    var listeningPill: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach([7, 13, 9, 15, 6], id: \.self) { h in
                    Capsule()
                        .fill(Color(hex: "#31D64A"))
                        .frame(width: 2.5, height: CGFloat(h))
                }
            }
            Text("Listening to you")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.42)))
    }
}

// MARK: - Quota + hearts row (Figma "Free quota")
private extension TalkView {

    var quotaRow: some View {
        HStack {
            quotaPill
            Spacer(minLength: 0)
            heartsRow
        }
    }

    /// Розовая пилюля: 3 точки + "{N} of 3 free texts today".
    var quotaPill: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<TalkViewModel.freeTextsPerDay, id: \.self) { i in
                    Circle()
                        .fill(i < vm.freeTextsRemaining
                              ? Color.lsPink
                              : Color(hex: "#37373C"))
                        .frame(width: 7, height: 7)
                }
            }
            Text("\(vm.freeTextsRemaining) of \(TalkViewModel.freeTextsPerDay) free texts today")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.lsPink)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(Color.lsPink.opacity(0.18)))
    }

    var heartsRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < vm.hearts ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(i < vm.hearts ? .lsPink : Color.white.opacity(0.35))
            }
        }
    }
}

// MARK: - Messages
private extension TalkView {

    var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if vm.isSending {
                        TypingIndicatorBubble(label: vm.typingLabel)
                            .id(Self.typingIndicatorId)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .onChange(of: vm.isSending) { _, isSending in
                if isSending {
                    withAnimation { proxy.scrollTo(Self.typingIndicatorId, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    func messageBubble(_ message: AIMessage) -> some View {
        switch message.role {
        case .assistant: assistantBubble(message)
        case .user:      userBubble(message)
        }
    }

    func assistantBubble(_ message: AIMessage) -> some View {
        let translation = vm.translations[message.id]
        let isTranslating = vm.translatingIds.contains(message.id)

        return VStack(alignment: .leading, spacing: 10) {
            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(.white)

            if let translation {
                Divider().background(Color.white.opacity(0.1))
                Text(translation)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 18) {
                // Speaker: играем озвучку голосом текущего учителя.
                // Тап работает и для реплик из disk-истории — если url'а
                // нет в кэше, VM сделает ленивый TTS-запрос.
                Button {
                    Task { await vm.playAudio(for: message) }
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(vm.playingMessageId == message.id
                                         ? Color.lsPink
                                         : Color(hex: "#9A9AA3"))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await vm.toggleTranslation(for: message) }
                } label: {
                    HStack(spacing: 4) {
                        if isTranslating {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(Color(hex: "#9A9AA3"))
                        } else {
                            Image(systemName: "character.book.closed")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(translation == nil ? "Translate" : "Hide translation")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(translation == nil ? Color(hex: "#9A9AA3") : .lsPink)
                }
                .buttonStyle(.plain)
                .disabled(isTranslating)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#18181D")))
    }

    func userBubble(_ message: AIMessage) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#5B1B36")))
        }
    }
}

// MARK: - Typing indicator
private struct TypingIndicatorBubble: View {
    let label: String

    @State private var dotCount: Int = 1
    private let tick = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(label)
            Text(String(repeating: ".", count: dotCount))
                .frame(width: 20, alignment: .leading)
        }
        .font(.system(size: 15))
        .foregroundStyle(Color(hex: "#9A9AA3"))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#18181D")))
        .onReceive(tick) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}

// MARK: - Interaction panel (Figma "Interaction panel", 393×109)
private extension TalkView {

    @ViewBuilder
    var interactionPanel: some View {
        if vm.quotaExhausted {
            unlockCTA
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    textFieldPill
                    micLockedButton
                }
                .padding(.horizontal, 16)

                if !vm.isPremium {
                    Text("Unlimited texts and voice with Premium")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#9A9AA3"))
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    /// Тёмная пилюля с полем ввода и inline pink send'ом справа.
    /// Figma: 303×54, cr=23, fill #18181D. Send: 38×38 pink, cr=19.
    var textFieldPill: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $vm.inputText,
                prompt: Text("Type your reply…").foregroundStyle(Color(hex: "#9A9AA3"))
            )
            .textInputAutocapitalization(.sentences)
            .submitLabel(.send)
            .focused($isInputFocused)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .padding(.leading, 18)
            .onSubmit { Task { await vm.send(); isInputFocused = false } }

            Button {
                Task { await vm.send(); isInputFocused = false }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(vm.canSend ? Color.lsPink : Color(hex: "#37373C")))
            }
            .buttonStyle(.plain)
            .disabled(!vm.canSend)
            .padding(.trailing, 8)
        }
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 23).fill(Color(hex: "#18181D")))
    }

    /// Отдельная кнопка микрофона. В базовом сценарии — залочена (premium-only).
    /// Figma: 48×48 cr=24 fill #37373C + pink lock 20×20 в углу.
    var micLockedButton: some View {
        Button {
            if vm.voiceLocked {
                vm.openPaywall()
            } else {
                Task { await vm.toggleMic() }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(vm.speech.isRecording ? Color.lsPink : Color(hex: "#37373C"))
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
            .frame(width: 48, height: 48)
            .overlay(alignment: .bottomTrailing) {
                if vm.voiceLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.lsPink))
                        .offset(x: 4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    var unlockCTA: some View {
        VStack(spacing: 8) {
            Button {
                vm.openPaywall()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Unlock more messages")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Capsule().fill(Color.lsPink))
            }
            .buttonStyle(.plain)

            Text("Free texts come back tomorrow")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#9A9AA3"))
        }
    }
}

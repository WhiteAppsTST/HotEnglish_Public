import SwiftUI
import Combine

struct LessonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var premium
    @State private var vm: LessonViewModel
    @State private var avatar = AvatarPlayer()
    @FocusState private var isInputFocused: Bool
    @Namespace private var animation

    /// Скорость аудио учителя (Figma 811:1113 — контекстное меню под "1×").
    /// Хранится в UserDefaults, чтобы сохранялась между запусками.
    /// Влияет ТОЛЬКО на аудио через `PlaybackService.playbackRate`; видео
    /// аватара идёт своей дорожкой и не меняется.
    @AppStorage("app.lessonAudioSpeed") private var audioSpeed: Double = 1.0
    /// Открыт ли выпадающий список скоростей под pill'ом.
    @State private var isSpeedMenuOpen: Bool = false
    /// Доступные пресеты скорости в порядке отображения.
    private static let audioSpeedOptions: [Double] = [0.5, 1.0, 1.5, 2.0]

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Id typing-индикаторного бабла (см. `messagesList`). Используется
    /// для автоскролла при появлении/скрытии.
    fileprivate static let typingIndicatorId = "lesson-typing-indicator"

    init(unitId: String, step: Step, teacher: TeacherProfile, language: LanguageCode, user: UserEntity) {
        _vm = State(wrappedValue: LessonViewModel(
            unitId: unitId, step: step, teacher: teacher, language: language, user: user
        ))
    }

    /// Настраивает idle-loop учителя. Вызывается на onAppear.
    private func setupAvatar() {
        if let idle = vm.teacher.lessonVideo(.idle) {
            avatar.setBase(video: idle)
        }
    }

    /// Играет reaction-видео по последнему `vm.lastReaction`. Триггерится
    /// подпиской на `vm.reactionTick`.
    private func playReaction() {
        guard let reaction = vm.lastReaction else { return }
        guard let video = vm.teacher.lessonVideo(reaction.lessonState) else { return }
        let audio = reaction.soundEffect.flatMap { vm.teacher.sound($0) }
        avatar.playOnce(video: video, audio: audio)
    }

    var body: some View {
        Group {
            if vm.isFullscreen {
                fullscreenBody
            } else {
                normalBody
            }
        }
        .background(Color(hex: "#0A0A0D").ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Открытое меню скорости — тап по пустому месту сначала закрывает
        // его, затем как обычно снимает фокус с TextField.
        .onTapGesture {
            if isSpeedMenuOpen {
                withAnimation(.easeOut(duration: 0.15)) { isSpeedMenuOpen = false }
            }
            isInputFocused = false
        }
        .onReceive(tick) { _ in vm.tick() }
        .onAppear {
            setupAvatar()
            // Синхронизируем сохранённую скорость аудио с плеером ДО
            // autoplay-старта, чтобы первая реплика уже играла в правильном
            // темпе. Каст в Float — AVAudioPlayer.rate: Float.
            vm.remoteAudio.playbackRate = Float(audioSpeed)
            // Autoplay первой реплики учительницы — только после того как
            // экран урока реально появился. В init'e VM autoplay не стартуем,
            // иначе NavigationLink проиграет аудио ещё на Home.
            vm.startAutoplayIfNeeded()
        }
        .onChange(of: audioSpeed) { _, new in
            // Юзер выбрал другую скорость — применяем к текущему и будущим
            // проигрываниям. `didSet` в PlaybackService пробросит на живой
            // AVAudioPlayer, если он есть.
            vm.remoteAudio.playbackRate = Float(new)
        }
        .onDisappear {
            avatar.stop()
            vm.remoteAudio.stop()
            Task { await vm.abandonIfActive() }
        }
        .onChange(of: vm.reactionTick) { _, _ in playReaction() }
        .task { await vm.startSession() }
        .onChange(of: vm.sessionAbort) { _, abort in
            guard let abort else { return }
            // Если Apphud уже подтвердил подписку локально — сервер просто
            // ещё не успел валидировать чек (в песочнице /purchases/refresh
            // отваливается с «Notification chain does not root in Apple's
            // CA», сервер видит юзера как free и режет квоту 3 попытками).
            // В этом случае НЕ выкидываем в пейвол — юзер уже заплатил.
            // Дёргаем повторный ping /purchases/refresh в фоне и молча
            // остаёмся в уроке (следующий тап startSession попробует
            // снова, когда серверный премиум подтянется).
            if premium.isActiveSubscription {
                // Apphud уже видит подписку локально, сервер просто ещё не
                // валидировал чек и режет квоту. Не выкидываем в пейвол —
                // юзер платящий. Следующий тап startSession попробует
                // снова, когда бэк подтянет статус (webhook / повторный
                // POST /purchases/refresh из completePurchase/restore).
                vm.sessionAbort = nil
                return
            }
            switch abort {
            case .paywallRequired:
                premium.showPaywall(.in_lessons)
                dismiss()
            case .stepConflict:
                Task { await AuthService.shared.syncMe() }
                dismiss()
            case .quotaExhausted:
                premium.showPaywall(.in_lessons)
                dismiss()
            }
        }
        // Date-шаг завершён на free → сначала dismiss, потом пейвол
        // «продолжить свидание в свободном чате» (Figma 762:2511).
        .onChange(of: vm.shouldShowDateContinuePaywall) { _, shouldShow in
            guard shouldShow else { return }
            vm.shouldShowDateContinuePaywall = false
            dismiss()
            premium.showPaywall(.dating)
        }
        // Обычный шаг завершён на free → «You stopped one step before the good
        // part» (Figma 762:2568).
        .onChange(of: vm.shouldShowLessonEndPaywall) { _, shouldShow in
            guard shouldShow else { return }
            vm.shouldShowLessonEndPaywall = false
            dismiss()
            premium.showPaywall(.lesson_end)
        }
        // Free-юзер жмёт мик в date-шаге → пейвол `.free_chat`.
        .onChange(of: vm.shouldShowFreeChatPaywall) { _, shouldShow in
            guard shouldShow else { return }
            vm.shouldShowFreeChatPaywall = false
            premium.showPaywall(.free_chat)
        }
        // Free-юзер жмёт мик в любом уроке → in-lesson пейвол
        // (Figma 762:2445 / .in_lessons) вместо системного alert.
        .onChange(of: vm.shouldShowInLessonsPaywall) { _, shouldShow in
            guard shouldShow else { return }
            vm.shouldShowInLessonsPaywall = false
            premium.showPaywall(.in_lessons)
        }
        .sheet(isPresented: $vm.showHintSheet) {
            hintSheet
        }
        .sheet(isPresented: $vm.showConversationInfoSheet) {
            conversationInfoSheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: "#0B0B0F"))
        }
        .sheet(isPresented: $vm.showHintRevealSheet) {
            hintRevealSheet
        }
        .sheet(isPresented: $vm.showScoreSheet) {
            scoreSheet
        }
        .alert(
            "Permission needed",
            isPresented: Binding(
                get: { vm.error != nil },
                set: { if !$0 { vm.error = nil } }
            )
        ) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }
}

// MARK: - Normal layout
private extension LessonView {

    var normalBody: some View {
        VStack(spacing: 0) {
            heroSection
            contentSection
            bottomBar
        }
    }

    var heroSection: some View {
        Color.clear
            .frame(height: 383)
            .background {
                // Silent idle-loop учителя + reaction-видео по последнему
                // ответу (см. onChange(reactionTick) -> playReaction()).
                AvatarPlayerView(player: avatar.videoPlayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottomLeading) {
                emmaSaysPill
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .bottomTrailing) {
                fullscreenToggleButton
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
    }

    var contentSection: some View {
        VStack(spacing: 0) {
            phaseHeaderRow
                .padding(.horizontal, 16)
                .frame(height: 43)

            progressBar
                .padding(.horizontal, 16)
                .frame(height: 16)

            // Offline-banner (373:4639) — между progress-баром и месседжами.
            if vm.isOffline {
                offlineBanner
            }

            switch vm.phase {
            case .lecture:  messagesList
            case .practice: practiceContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Amber banner для offline-стейта (Figma 373:4639). Bg .amber@16% полупрозрачный.
    /// WiFi-иконка + title 14/590 white + subtitle 12/400 grey + Retry 14/590 amber.
    var offlineBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "#FFAF1F"))

            VStack(alignment: .leading, spacing: 2) {
                Text("No connection")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("The lesson is paused — nothing is lost")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                vm.retryConnection()
            } label: {
                Text("Retry")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FFAF1F"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(hex: "#FFAF1F").opacity(0.16))
    }
}

// MARK: - Fullscreen layout
private extension LessonView {

    /// Fullscreen layout (Figma 373:3603): фото на весь экран, снизу стек из
    /// bottom bar → скроллируемый компактный чат-лог → row (Emma says · stats
    /// · collapse). Логика: юзер общается с AI голосом/текстом (bottom bar), а
    /// весь диалог виден в чате поверх фото.
    var fullscreenBody: some View {
        Color.clear
            .background {
                AvatarPlayerView(player: avatar.videoPlayer)
                    .ignoresSafeArea()
            }
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    fullscreenControlsRow
                    fullscreenChat
                    bottomBar
                }
            }
    }

    /// Горизонтальный ряд над баблом (Figma 373:3603, y=544 от верха frame'а):
    /// Emma says слева (padding-L=16), справа группа Affinity-pill + collapse
    /// с фиксированным gap=8, right padding=16. Между left- и right-группой —
    /// flex spacer.
    var fullscreenControlsRow: some View {
        HStack(spacing: 0) {
            emmaSaysPill
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                statsPill
                fullscreenToggleButton
            }
        }
        .padding(.horizontal, 16)
    }

    /// Компактный скроллируемый чат в fullscreen. Показывает `fullscreenChatItems`
    /// из VM — messages в Lecture, feedback-реплики в Practice.
    /// maxHeight 200 чтобы меньше закрывать фото учителя. Автоскролл к последнему.
    var fullscreenChat: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(vm.fullscreenChatItems) { item in
                        fullscreenChatItemView(item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 200)
            .onChange(of: vm.fullscreenChatItems.count) { _, _ in
                if let last = vm.fullscreenChatItems.last?.id {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func fullscreenChatItemView(_ item: LessonViewModel.FullscreenChatItem) -> some View {
        switch item {
        case .message(let m):
            switch m.role {
            case .assistant: fullscreenAssistantBubble(m)
            case .user:      fullscreenUserBubble(m)
            }
        case .keyPhrases:
            // Reuse существующей keyPhrases card (573:2487).
            keyPhrasesCard
        case .pattern(let p):
            patternCard(p)
        case .practiceFeedback(_, let text, _):
            HStack {
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
                Spacer(minLength: 40)
            }
        case .practiceQuestion(let q):
            // Fullscreen — та же практика по типу вопроса. Юзер видит
            // вопрос и может ответить прямо тут.
            switch q.kind {
            case .fillBlank:
                VStack(spacing: 10) {
                    grammarQuestionCard(q)
                    grammarOptions(q)
                }
            case .listenChoose:
                VStack(spacing: 10) {
                    listenChooseCard(q)
                    listenChooseOptions(q)
                }
            case .wordOrder:
                wordOrderCard(q)
            case .describeImage:
                describeImageCard(q)
            }
        }
    }

    /// Компактный assistant-бабл в fullscreen. Figma 373:3603 subtitle-бабл:
    /// `.white@10%` cr=12, native text 14/medium white. Бабл hug'ается по
    /// контенту с trailing-spacer'ом ≥40pt — так поле не растягивается на
    /// весь экран и меньше перекрывает лицо учителя.
    func fullscreenAssistantBubble(_ m: LessonMessage) -> some View {
        HStack {
            Text(m.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
            Spacer(minLength: 40)
        }
    }

    /// Компактный user-бабл в fullscreen: right-aligned pink/wine (для queued).
    /// Симметричен assistant-баблу — 14/semibold, padding 12×8, leading-spacer
    /// ≥40pt чтобы бабл hug'ался и не растягивался на весь экран.
    func fullscreenUserBubble(_ m: LessonMessage) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(m.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(m.isQueued ? Color.white.opacity(0.6) : .white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(
                    m.isQueued ? Color(hex: "#5B1B36") : Color.lsPink
                ))
        }
    }
}

// MARK: - Top bar (X · timer · 1×)
private extension LessonView {

    var topBar: some View {
        HStack {
            closeButton
            timerPill
            Spacer(minLength: 0)
            speedPill
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
    }

    var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.42)))
        }
        .buttonStyle(.plain)
    }

    var timerPill: some View {
        HStack(spacing: 4) {
            Text(String(format: "%d:%02d", vm.elapsedSeconds / 60, vm.elapsedSeconds % 60))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("/ \(Self.formatSecs(LessonViewModel.sessionMaxSeconds))")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "#BFBFC9"))
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(Color.black.opacity(0.42)))
    }

    /// Pill со скоростью аудио. Тап — раскрывает контекстное меню
    /// пресетов (Figma 811:1113). Меню висит поверх контента через
    /// `overlay(alignment: .top)` со смещением ниже pill'а. Клик по
    /// пресету сохраняет значение в `@AppStorage`, `PlaybackService`
    /// подхватит через `.onChange(of: audioSpeed)` в body.
    var speedPill: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isSpeedMenuOpen.toggle() }
        } label: {
            Text(Self.speedLabel(audioSpeed))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Capsule().fill(Color.black.opacity(0.42)))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if isSpeedMenuOpen {
                speedMenu
                    .offset(y: 44) // 36 pill height + 8 gap (Figma 811:1123→1208)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .zIndex(10) // чтобы меню перекрывало соседний timerPill / heart
    }

    /// Список пресетов (Figma 811:1208): 41pt ширина, corner 18, bg
    /// black@0.42. Активный пресет подсвечен `white@0.20`. Разделители
    /// между кнопками — hairline white@8%.
    var speedMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.audioSpeedOptions.enumerated()), id: \.offset) { pair in
                if pair.offset > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                }
                speedMenuButton(value: pair.element)
            }
        }
        .frame(width: 41)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.42))
        )
    }

    func speedMenuButton(value: Double) -> some View {
        let isSelected = abs(audioSpeed - value) < 0.01
        return Button {
            audioSpeed = value
            withAnimation(.easeOut(duration: 0.15)) { isSpeedMenuOpen = false }
        } label: {
            Text(Self.speedLabel(value))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 37)
                .background(isSelected ? Color.white.opacity(0.20) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    /// Формат "1×" / "1.5×" / "2×" — без .0.
    static func speedLabel(_ v: Double) -> String {
        let trunc = Double(Int(v))
        if abs(v - trunc) < 0.01 {
            return "\(Int(v))×"
        }
        // 0.5 → "0.5×", 1.5 → "1.5×"
        return String(format: "%.1f×", v)
    }

    static func formatSecs(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Hero overlays
private extension LessonView {

    /// Пилюля «эквалайзер + подпись». В Lecture — розовая, «{Emma} says».
    /// В Practice (Figma 373:3665) — зелёная, «Listening to you».
    var emmaSaysPill: some View {
        let isPractice = vm.phase == .practice
        let color: Color = isPractice ? Color(hex: "#31D64A") : .lsPink
        let text: String = isPractice ? "Listening to you" : "\(vm.teacher.name) says"

        return HStack(spacing: 8) {
            AnimatedEqualizer(color: color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.42)))
    }

    var fullscreenToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { vm.toggleFullscreen() }
        } label: {
            Image(systemName: vm.isFullscreen
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.42)))
        }
        .buttonStyle(.plain)
    }

    /// Пилюля со здоровьями + уровнем в fullscreen поверх фото (Figma
    /// 373:3654 «Affinity»): h=32, cornerRadius=16 (capsule), bg black@0.42,
    /// horizontal padding 10, itemSpacing 8. Слева heart 11×10.5 pink,
    /// затем 5 сегментов 11×4 (gap 3, cornerRadius 2) — заполненные pink,
    /// пустые white@0.28. Справа "LV N" SF Pro Semibold 11pt, pink,
    /// однострочный fixedSize чтобы не переносился при сжатии.
    var statsPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lsPink)
                .frame(width: 11, height: 11)
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(i < vm.heartsFilled ? Color.lsPink : Color.white.opacity(0.28))
                        .frame(width: 11, height: 4)
                }
            }
            Text("LV \(vm.affinityLevel)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lsPink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.42)))
    }
}

// MARK: - Phase header (Lecture / Practice) + hearts
private extension LessonView {

    var phaseHeaderRow: some View {
        HStack(spacing: 8) {
            phaseTab(.lecture)
            // Divider между табами: розовый когда Practice активна (373:3665),
            // серый в обычном Lecture-стейте.
            Rectangle()
                .fill(vm.phase == .practice ? Color.lsPink : Color(hex: "#37373C"))
                .frame(width: 26, height: 2)
            phaseTab(.practice)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("Lvl \(vm.affinityLevel)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: "#878680"))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < vm.heartsFilled ? "heart.fill" : "heart")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.lsPink)
                    }
                }
            }
        }
    }

    /// Тап-таб сегмента. Активный tab: розовый dot + белый semibold текст.
    /// Неактивный: серый dot + серый regular текст. По тапу → `vm.selectPhase`.
    /// Divider между табами в Practice становится розовой линией (см. phaseHeaderRow).
    func phaseTab(_ p: LessonPhase) -> some View {
        let active = vm.phase == p
        return Button {
            vm.selectPhase(p)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(active ? Color.lsPink : Color(hex: "#37373C"))
                    .frame(width: 9, height: 9)
                Text(p.title)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? .white : Color(hex: "#9A9AA3"))
            }
        }
        .buttonStyle(.plain)
    }

    var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<vm.progressTotal, id: \.self) { i in
                Capsule()
                    .fill(i < vm.progressCurrent ? Color.lsPink : Color(hex: "#37373C"))
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Messages list + bubbles
private extension LessonView {

    var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.messages) { message in
                        bubble(message).id(message.id)
                    }
                    // Typing-индикатор: пока ждём ответ учителя (chat-turn /
                    // клиентский GPT), показываем "Yuki is typing…" на месте
                    // будущего бабла. Юзер сразу видит, что запрос не повис.
                    if vm.isTeacherReplying {
                        LessonTypingIndicatorBubble(label: vm.typingLabel)
                            .id(Self.typingIndicatorId)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    // Voice error (Figma 373:4511) — часть чат-стрима.
                    if vm.voiceError != nil {
                        voiceErrorSection
                    } else if vm.messages.last?.role == .assistant {
                        if !vm.keyPhrases.isEmpty {
                            keyPhrasesCard
                        }
                        ForEach(vm.patterns) { pattern in
                            patternCard(pattern)
                        }
                    }
                    if vm.canFinishLesson {
                        finishLessonButton
                    }
                    if shouldShowWhatToReplyChip {
                        whatToReplyChip
                    }
                    // Якорь низа — на него скроллим при новом сообщении.
                    Color.clear.frame(height: 1).id("chat_bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .allowsHitTesting(!vm.isRecordingActive || vm.voiceError != nil)
            // Автоскролл: следим за количеством сообщений и id последнего;
            // при любом изменении пинаем `.bottom` через `scrollTo`.
            .onChange(of: vm.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: vm.messages.last?.id) { _, _ in
                scrollToBottom(proxy)
            }
            // Typing-индикатор появился/скрылся — скроллим низ, чтобы
            // "…is typing" сразу оказался в поле зрения.
            .onChange(of: vm.isTeacherReplying) { _, isTyping in
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollToBottom(proxy)
                }
                if isTyping {
                    withAnimation { proxy.scrollTo(Self.typingIndicatorId, anchor: .bottom) }
                }
            }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let action = { proxy.scrollTo("chat_bottom", anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.28)) { action() }
        } else {
            action()
        }
    }

    /// Секция для 373:4511: сверху винный waveform-бабл прошлой записи, снизу
    /// error-карточка с двумя кнопками.
    var voiceErrorSection: some View {
        VStack(spacing: 12) {
            recordedAudioBubble
            voiceErrorCard
        }
    }

    /// Wine-розовый бабл (right-aligned) с play + waveform + duration.
    /// Показывает воспроизведение предыдущей неудачной записи.
    /// Ширина по контенту (не тянется на весь ряд).
    var recordedAudioBubble: some View {
        HStack {
            Spacer(minLength: 40)
            HStack(spacing: 10) {
                Button {
                    // TODO: воспроизведение записи через AVAudioPlayer.
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)

                staticWaveform

                Text(String(format: "0:%02d", Int(vm.lastRecordingDuration)))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(hex: "#5B1B36")))
        }
    }

    /// Voice error card (Figma 373:4511): bg `.white@5%` cr 16 — очень тонкая
    /// полупрозрачная плашка поверх основного фона, не тёмная как assistant-бабл.
    var voiceErrorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("That came through too quiet to score")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Try again a bit closer to the mic — or type your answer instead.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    vm.dismissVoiceErrorAndType()
                } label: {
                    Text("Type instead")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(Color(hex: "#2E2E34")))
                }
                .buttonStyle(.plain)

                Button {
                    vm.retryRecording()
                } label: {
                    Text("Record again")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(Color.lsPink))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    /// Кнопка «Finish lesson» — появляется когда `vm.canFinishLesson == true`
    /// (все turns прошли для .lecture / .speaking, сервер прислал shouldEnd
    /// для .date, все practice отвечены для .grammar).
    var finishLessonButton: some View {
        Button {
            vm.finishLesson { dismiss() }
        } label: {
            Text(L10n.tr("lesson.finish", "Finish lesson"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Capsule().fill(Color.lsPink))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    /// Card «Key phrases» — Figma 373:2557. Header (title + pink count) +
    /// список всех фраз (native + translation + play). Между фразами
    /// horizontal separator (Figma 373:2577, 1pt, white@6%), как в
    /// pattern-card. Каунтер в шапке = общее число фраз.
    var keyPhrasesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key phrases")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(vm.keyPhrases.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.lsPink)
            }

            ForEach(Array(vm.keyPhrases.enumerated()), id: \.element.id) { pair in
                if pair.offset > 0 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
                keyPhraseRow(pair.element)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
    }

    func keyPhraseRow(_ phrase: KeyPhrase) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(phrase.native)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(phrase.translation)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            playIconButton {
                guard let url = phrase.audioUrl else { return }
                Task { await vm.playRemote(url: url, id: phrase.id) }
            }
            .opacity(phrase.audioUrl == nil ? 0.4 : 1)
            .disabled(phrase.audioUrl == nil)
        }
    }

    /// Card «Pattern» — Figma 373:2487. Header (title + formula справа) +
    /// **несколько примеров** (2+) через `Divider` между ними.
    /// Каждый example: pink-highlighted prefix + translation + play.
    func patternCard(_ p: PatternExample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pattern")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(p.formula)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }

            ForEach(Array(p.examples.enumerated()), id: \.element.id) { pair in
                if pair.offset > 0 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
                patternExampleRow(pair.element)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
    }

    func patternExampleRow(_ ex: PatternExample.Example) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                patternExampleText(ex)
                Text(ex.translation)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            playIconButton {
                guard let url = ex.audioUrl else { return }
                Task { await vm.playRemote(url: url, id: ex.id) }
            }
            .opacity(ex.audioUrl == nil ? 0.4 : 1)
            .disabled(ex.audioUrl == nil)
        }
    }

    /// Рендерит example с pink-подсветкой префикса. Text-конкатенация не
    /// требует HStack — переносит правильно.
    func patternExampleText(_ ex: PatternExample.Example) -> Text {
        if let range = ex.text.range(of: ex.highlightPrefix) {
            let prefix = String(ex.text[ex.text.startIndex..<range.upperBound])
            let rest = String(ex.text[range.upperBound...])
            return Text(prefix)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.lsPink)
            + Text(rest)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
        }
        return Text(ex.text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
    }

    func playIconButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(hex: "#2E2E34")))
        }
        .buttonStyle(.plain)
    }

    /// «What to reply?» — розовая chip справа. Показываем ТОЛЬКО в
    /// интерактивных Lecture-степах (.date / .speaking), где юзер общается
    /// с GPT-учителем — chip открывает conversation-info sheet с описанием
    /// режима на языке юзера. В trigger-driven лекциях диалога нет,
    /// поэтому chip там не нужен.
    var shouldShowWhatToReplyChip: Bool {
        guard vm.canUseTextOrVoice else { return false }
        return vm.messages.last?.role == .assistant && vm.inputText.isEmpty
    }

    var whatToReplyChip: some View {
        HStack {
            Spacer(minLength: 40)
            Button {
                vm.openConversationInfoSheet()
            } label: {
                Text(L10n.tr("What to reply?", "What to reply?"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.lsPink)
                    .padding(.horizontal, 16)
                    .frame(height: 41)
                    .background(Capsule().fill(Color.lsPink.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    func bubble(_ message: LessonMessage) -> some View {
        switch message.role {
        case .assistant: assistantBubble(message)
        case .user:      userBubble(message)
        }
    }

    func assistantBubble(_ message: LessonMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let translation = vm.translations[message.id] {
                Text(translation)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }

            HStack(spacing: 18) {
                Button {
                    Task { await vm.playAudio(for: message) }
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            vm.playingMessageId == message.id
                                ? Color.lsPink
                                : Color(hex: "#9A9AA3")
                        )
                }
                .buttonStyle(.plain)
                .disabled(vm.audioUrlByMessageId[message.id] == nil)
                .opacity(vm.audioUrlByMessageId[message.id] == nil ? 0.4 : 1)

                Button {
                    Task { await vm.toggleTranslation(for: message) }
                } label: {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            vm.translations[message.id] != nil
                                ? Color.lsPink
                                : Color(hex: "#9A9AA3")
                        )
                }
                .buttonStyle(.plain)
                .disabled(vm.translatingIds.contains(message.id))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#18181D")))
    }

    /// Контент Practice-фазы. По типу текущего вопроса выбирает вью:
    /// - `.fillBlank` → grammar quiz (Figma 373:3665)
    /// - `.listenChoose` → listen-and-choose (Figma 373:4010, следующий тикет)
    /// Если `currentPracticeQuestion == nil` — показываем пустое состояние
    /// (например, вопросы ещё не загружены с бэка).
    @ViewBuilder
    var practiceContent: some View {
        if vm.currentPracticeQuestion != nil {
            // Всё то же chat-like ScrollView + header — работает для всех
            // Practice-типов через practiceItemView switch.
            grammarQuizContent(vm.currentPracticeQuestion!)
        } else {
            EmptyView()
        }
    }

    /// Grammar quiz (Figma 373:3665): статический header + chat-like ScrollView
    /// стрима вопросов и feedback-сообщений от Emma. При ответе на вопрос —
    /// внизу появляется feedback + следующий вопрос, скрол едет вниз.
    func grammarQuizContent(_ q: PracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            practiceHeaderRow
                .padding(.horizontal, 16)
                .padding(.top, 20)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.practiceStream) { item in
                            practiceItemView(item)
                                .id(item.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }
                        // Все вопросы отвечены — показываем CTA завершения
                        // урока прямо в стриме (после последнего feedback'а).
                        if vm.canFinishLesson {
                            finishLessonButton
                                .padding(.top, 8)
                                .id("finish_lesson_cta")
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .onChange(of: vm.practiceStream.count) { _, _ in
                    if let lastId = vm.practiceStream.last?.id {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: vm.canFinishLesson) { _, ready in
                    if ready {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("finish_lesson_cta", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    /// «Question 1 of 6» слева (13/510 medium) + «about 1 min left» справа
    /// (13/400 regular), оба цвет `#9A9AA3` (Figma 373:3665).
    var practiceHeaderRow: some View {
        HStack {
            Text("Question \(vm.currentQuestionNumber) of \(vm.currentQuestionTotal)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "#9A9AA3"))
            Spacer()
            Text("about 1 min left")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
        }
    }

    /// Роутер по типу элемента стрима.
    @ViewBuilder
    func practiceItemView(_ item: PracticeStreamItem) -> some View {
        switch item {
        case .question(let q):
            VStack(alignment: .leading, spacing: 12) {
                switch q.kind {
                case .fillBlank:
                    grammarQuestionCard(q)
                    grammarOptions(q)
                case .listenChoose:
                    listenChooseCard(q)
                    listenChooseOptions(q)
                case .wordOrder:
                    wordOrderCard(q)
                case .describeImage:
                    describeImageCard(q)
                }
            }
        case .feedback(_, let text, let isCorrect):
            practiceFeedbackBubble(text: text, isCorrect: isCorrect)
        }
    }

    /// Word-ordering card (Figma 373:3761): subtitle + prompt + dashed drop-zone
    /// c pink-pill выбранными словами + word bank ниже (LazyVGrid для wrap).
    /// Все размеры и цвета — из Figma REST tree.
    func wordOrderCard(_ q: PracticeQuestion) -> some View {
        let selected = vm.wordOrderSelection(for: q)
        let available = vm.availableWords(for: q)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let sub = q.wordOrderSubtitle {
                    Text(sub)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "#9A9AA3"))
                }
                Text(q.promptNative ?? "")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Dashed drop-zone с выбранными словами (тап → удалить).
                // WordWrapLayout — контент-size пиллы, честный wrap строк,
                // без летер-рэпа как в LazyVGrid.
                WordWrapLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(selected.enumerated()), id: \.offset) { pair in
                        Button {
                            vm.removeWordFromOrder(at: pair.offset, for: q)
                        } label: {
                            Text(pair.element)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 11).fill(Color.lsPink))
                        }
                        .buttonStyle(.plain)
                    }
                    // Курсор (мигающая линия) в конце
                    if vm.practiceAnswers[q.id] == nil {
                        Rectangle()
                            .fill(Color.lsPink)
                            .frame(width: 2, height: 22)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(
                            Color(hex: "#37373C"),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))

            Text("Tap the words in the right order")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(maxWidth: .infinity, alignment: .center)

            // Word bank — flow layout: каждая пилла sized-to-content,
            // строка wrap'ится когда следующее слово не влезает.
            WordWrapLayout(spacing: 8, lineSpacing: 8) {
                ForEach(available, id: \.self) { word in
                    Button {
                        vm.addWordToOrder(word, for: q)
                    } label: {
                        Text(word)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 13).fill(Color(hex: "#18181D")))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Describe-image card (Figma 373:3933): prompt + large image placeholder.
    /// Все размеры/цвета — из Figma REST tree.
    func describeImageCard(_ q: PracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(q.describePrompt ?? "")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Placeholder-бокс для картинки/видео. TODO: заменить на AsyncImage
            // когда бэк отдаст URL.
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#37373C"))
                .frame(minHeight: 256)
                .overlay {
                    if let imageName = q.describeImageName {
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text("image / video")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "#9A9AA3"))
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
    }

    /// Audio-player card для listen-choose (Figma 373:4010). Instruction 13/510
    /// grey, play button 52×52 pink, waveform static, duration 11/400 grey.
    /// Card bg `#18181D` cr 16.
    func listenChooseCard(_ q: PracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(q.instruction ?? "Listen, then choose what I said")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    // Играем аудио через RemoteAudioCache + PlaybackService.
                    // Тот же путь что и озвучка лекторских реплик.
                    if let raw = q.audioName, let url = URL(string: raw) {
                        Task { await vm.playRemote(url: url, id: "practice_\(q.id)") }
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.lsPink))
                }
                .buttonStyle(.plain)
                .disabled(q.audioName == nil)
                .opacity(q.audioName == nil ? 0.4 : 1)

                staticWaveform

                Spacer(minLength: 0)

                Text(String(format: "0:%02d", Int(q.audioDurationSeconds ?? 2)))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
    }

    /// 20 серых баров, высоты по фикс. паттерну. Пиксель-плейсхолдер waveform-а.
    var staticWaveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<20, id: \.self) { i in
                let heights: [CGFloat] = [8, 12, 20, 6, 14, 22, 18, 10, 24, 14, 8, 16, 20, 12, 6, 22, 14, 18, 8, 10]
                Capsule()
                    .fill(Color(hex: "#5A5A63"))
                    .frame(width: 2.5, height: heights[i % heights.count])
            }
        }
    }

    /// Правые опции с инлайн-номером «1.», «2.», «3.» (Figma 373:4010).
    /// Selected: pink 2pt stroke + pink@10% fill. Bg unselected: `#19191D`.
    func listenChooseOptions(_ q: PracticeQuestion) -> some View {
        let selectedId = vm.selectedOption(for: q)
        let isAnswered = selectedId != nil
        return VStack(spacing: 10) {
            ForEach(q.options) { option in
                listenChooseOptionRow(option,
                                      question: q,
                                      isSelected: selectedId == option.id,
                                      isAnswered: isAnswered)
            }
        }
    }

    /// Figma 373:4010: right-aligned option 242×58, cr неявный (~14), text 15/400
    /// regular. Selected: fill `#FF2D7D@18%` + stroke lsPink 1pt, text pink.
    /// Unselected: fill `#19191D` + stroke white@25%/1pt, text white.
    func listenChooseOptionRow(
        _ option: PracticeOption,
        question: PracticeQuestion,
        isSelected: Bool,
        isAnswered: Bool
    ) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                vm.answerPractice(question: question, option: option)
            } label: {
                Text("\(option.label).\(option.text)")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isSelected ? Color.lsPink : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? Color.lsPink.opacity(0.18) : Color(hex: "#19191D"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected ? Color.lsPink : Color.white.opacity(0.25),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(isAnswered)
            .frame(width: 242)
        }
    }

    /// Feedback-бабл в стиле assistant-бабла: тёмный `#18181D` cornerRadius 18,
    /// текст 15/regular белый. TODO: показывать зелёную/красную точку по isCorrect
    /// когда будет продовое решение по визуалу.
    func practiceFeedbackBubble(text: String, isCorrect: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isCorrect ? Color(hex: "#31D64A") : Color(hex: "#FF9A3C"))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#18181D")))
    }

    /// Тёмный card с предложением с пропуском + перевод. Bg `#18181D`,
    /// cornerRadius 16. Пропуск `____` — pink Rectangle underline.
    /// Native: 20/510 medium white. Translation: 13/400 regular grey.
    func grammarQuestionCard(_ q: PracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let instruction = q.instruction {
                Text(instruction)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
            }
            grammarPromptText(q.promptNative ?? "", isNative: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            grammarPromptText(q.promptTranslation ?? "", isNative: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
    }

    /// Рендерит текст с пропусками `____` через HStack. Каждый blank — Text с
    /// прозрачным цветом (сохраняет ширину подчёркиваний) + Rectangle 3pt
    /// розовый снизу через overlay. Native — 22/semibold белый, translation —
    /// 15/regular серый.
    func grammarPromptText(_ text: String, isNative: Bool) -> some View {
        let parts = splitBlanks(text)
        let font = Font.system(
            size: isNative ? 20 : 13,
            weight: isNative ? .medium : .regular
        )
        let color = isNative ? Color.white : Color(hex: "#9A9AA3")

        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                grammarPromptPart(part, font: font, color: color, isNative: isNative)
            }
        }
    }

    @ViewBuilder
    func grammarPromptPart(_ part: PromptPart, font: Font, color: Color, isNative: Bool) -> some View {
        switch part {
        case .plain(let s):
            Text(s).font(font).foregroundStyle(color)
        case .blank(let s):
            if isNative {
                Text(s)
                    .font(font)
                    .foregroundStyle(.clear)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.lsPink)
                            .frame(height: 2)
                            .padding(.bottom, 2)
                    }
            } else {
                Text(s).font(font).foregroundStyle(color)
            }
        }
    }

    /// Разбивает строку на чередующиеся куски plain-текста и blank-подчёркиваний.
    /// Blank = 4+ подчёркиваний подряд, чтобы отличить от одного `_`.
    private func splitBlanks(_ text: String) -> [PromptPart] {
        var out: [PromptPart] = []
        var current = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "_" {
                // Собираем последовательность подчёркиваний.
                var j = i
                while j < text.endIndex && text[j] == "_" { j = text.index(after: j) }
                let run = String(text[i..<j])
                if run.count >= 4 {
                    if !current.isEmpty {
                        out.append(.plain(current))
                        current = ""
                    }
                    out.append(.blank(run))
                } else {
                    current += run
                }
                i = j
            } else {
                current.append(text[i])
                i = text.index(after: i)
            }
        }
        if !current.isEmpty { out.append(.plain(current)) }
        return out
    }

    enum PromptPart {
        case plain(String)
        case blank(String)
    }

    /// Список опций (A/B/C/D). Bg `#18181D`, selected — border 2pt `#FF2D7D` + badge
    /// fill `#FF2D7D@22%`. Row 54pt, cr 16, badge 24×24 cr 7.
    func grammarOptions(_ q: PracticeQuestion) -> some View {
        let selectedId = vm.selectedOption(for: q)
        let isAnswered = selectedId != nil
        return VStack(spacing: 10) {
            ForEach(q.options) { option in
                grammarOptionRow(option,
                                 question: q,
                                 isSelected: selectedId == option.id,
                                 isAnswered: isAnswered)
            }
            // «No idea, honestly» — footer в Figma 373:3665.
            // Открывает hint flow: подсказка на текущий вопрос (если есть
            // квота) или пейвол `.in_lessons` (если free-квота исчерпана).
            Button {
                vm.openHintSheet()
            } label: {
                Text(L10n.tr("practice.no_idea", "No idea, honestly"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .buttonStyle(.plain)
        }
    }

    func grammarOptionRow(
        _ option: PracticeOption,
        question: PracticeQuestion,
        isSelected: Bool,
        isAnswered: Bool
    ) -> some View {
        Button {
            vm.answerPractice(question: question, option: option)
        } label: {
            HStack(spacing: 12) {
                // Letter badge 24×24 cr 7 — pink@22% при selected, #37373C иначе.
                Text(option.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isSelected ? Color.lsPink.opacity(0.22) : Color(hex: "#37373C"))
                    )

                Text(option.text)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.lsPink : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAnswered)
    }

    func userBubble(_ message: LessonMessage) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Spacer(minLength: 40)
                HStack(spacing: 8) {
                    Text(message.text)
                        .font(.system(size: 15, weight: message.isQueued ? .regular : .semibold))
                        .foregroundStyle(.white)
                    if message.hintUsed {
                        Image(systemName: "questionmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.25)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(
                    // Queued (Figma 373:4639): полупрозрачный pink@24%.
                    // Обычный: solid pink.
                    message.isQueued ? Color.lsPink.opacity(0.24) : Color.lsPink
                ))
            }
            if message.isQueued {
                Text("Will send when you're back online")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
        }
    }
}

// MARK: - Bottom bar (Text · Speak · Hint) / text input
private extension LessonView {

    @ViewBuilder
    var bottomBar: some View {
        switch vm.inputMode {
        case .buttons:          actionButtonsRow
        case .text:             textInputRow
        case .recording:        recordingRow(isStopped: false)
        case .recordingStopped: recordingRow(isStopped: true)
        }
    }

    var actionButtonsRow: some View {
        // HStack alignment .center: в Figma 373:2077 центры всех трёх кнопок
        // лежат на одной вертикали (y=773 от верха фрейма). Speak (74pt) шире
        // сайд-кнопок (54pt), поэтому центр-выравнивание даёт нужный эффект:
        // Speak-круг выступает на 10pt выше и ниже сайд-кнопок.
        //
        // Логика режима — правила разведены на два флага в VM:
        // - `canUseTextOrVoice` управляет Text/Speak (opacity 1 / .2 + enable).
        //   true только для интерактивных Lecture-степов (.date / .speaking).
        // - `canTapNext` управляет Next.
        //   Lecture-фаза → true для trigger-driven (.lecture / .topicWords /
        //   .pattern / .grammar), false для .date / .speaking.
        //   Practice-фаза → true ТОЛЬКО для .wordOrder (юзер собирает
        //   предложение и жмёт Next для валидации); .fillBlank /
        //   .listenChoose валидируются тапом по опции.
        // Тап Next → `vm.onNextTap()` (сам решает: advanceLecture или
        // validateWordOrder). Opacity 0.2 — из Figma 373:2077 (829:1050).
        let canTalk = vm.canUseTextOrVoice
        let canNext = vm.canTapNext
        return HStack(alignment: .center, spacing: 34) {
            actionButton(
                icon: "text.alignleft",
                label: "Text",
                background: Color(hex: "#18181D"),
                size: 54,
                iconSize: 18
            ) {
                vm.switchToTextInput()
                DispatchQueue.main.async { isInputFocused = true }
            }
            .opacity(canTalk ? 1 : 0.2)
            .disabled(!canTalk)

            actionButton(
                icon: "mic.fill",
                label: "Speak",
                background: Color.lsPink,
                size: 74,
                iconSize: 24
            ) {
                Task { await vm.startRecording() }
            }
            .opacity(canTalk ? 1 : 0.2)
            .disabled(!canTalk)

            actionButton(
                icon: "chevron.right",
                label: "Next",
                background: Color.lsPink,
                size: 54,
                iconSize: 18
            ) {
                vm.onNextTap()
            }
            .opacity(canNext ? 1 : 0.2)
            .disabled(!canNext)
        }
        .padding(.bottom, 8)
    }

    func actionButton(
        icon: String,
        label: String,
        background: Color,
        size: CGFloat,
        iconSize: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 5) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(background))
            }
            .buttonStyle(.plain)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    /// Bottom-bar в состояниях активной записи (`isStopped == false`,
    /// центральная кнопка — анимированный эквалайзер) и остановленной перед
    /// отправкой (`isStopped == true`, центральная кнопка — стрелка «отправить»).
    /// Размеры и цвета взяты напрямую из Figma 373:4741 / 373:4831.
    func recordingRow(isStopped: Bool) -> some View {
        VStack(spacing: 6) {
            micWithLockHint(isStopped: isStopped)

            Text("Listening…")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomLeading) {
            Button {
                vm.cancelRecording()
            } label: {
                Text("Cancel")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            // Figma 373:4741: Cancel at x=69.5, y=59 (bottom bar top). Cancel
            // center-y ≈ mic center-y. Padding-leading 70, padding-bottom
            // подобран так, чтобы Cancel был на уровне центра mic-круга.
            .padding(.leading, 70)
            .padding(.bottom, 30)
        }
        .padding(.bottom, 8)
    }

    /// Вертикальный эллипс pink@35% с розовой lock-иконкой. 28×44 (высота > ширины
    /// в 1.57 раза) — реальный вертикальный овал. Ставится через `.background()`
    /// с offset -22, так что нижние 22pt эллипса уходят за круглый мик, а верхняя
    /// половина торчит. Смысл в UI: чат-скролл и тапы по сообщениям заблокированы
    /// на время записи.
    /// TODO: реализовать реальный swipe-to-lock жест.
    var lockHintPill: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.lsPink)
            .frame(width: 28, height: 44)
            .padding(.bottom,20)
            .background(
                RoundedRectangle(cornerRadius: 44)
                    .fill(Color.lsPink.opacity(0.35)))
            .frame(width: 22)
    }

    func recordingMicButton(isStopped: Bool) -> some View {
        Button {
            if isStopped {
                vm.sendRecordedReply()
            } else {
                vm.stopRecording()
            }
        } label: {
            Group {
                if isStopped {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    AnimatedEqualizer(
                        color: .white,
                        barWidth: 4,
                        barSpacing: 4,
                        heights: [12, 24, 34, 20, 28]
                    )
                }
            }
            .frame(width: 74, height: 74)
            .background(Circle().fill(Color.lsPink))
            // Pink glow-ring вокруг мика в recording-state (Figma 373:4511):
            // stroke lsPink@30%, толщина 6pt наружу.
            .overlay(
                Circle().stroke(Color.lsPink.opacity(0.30), lineWidth: 6)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recording lock hint helper
private extension LessonView {

    /// Обёртка над mic-кнопкой которая рисует lock-hint (вертикальный эллипс
    /// pink@35%) ПОД миком в z-order через `.background`. Верхняя половина
    /// эллипса видна над миком, нижняя за круглой кнопкой мика.
    func micWithLockHint(isStopped: Bool) -> some View {
        recordingMicButton(isStopped: isStopped)
            .background(alignment: .top) {
                lockHintPill
                    .offset(y: -32)
            }
    }

    var textInputRow: some View {
        let finished = vm.canFinishLesson
        return HStack(spacing: 10) {
            TextField(
                "",
                text: $vm.inputText,
                prompt: Text("Type your reply…").foregroundStyle(Color(hex: "#9A9AA3"))
            )
            .textInputAutocapitalization(.sentences)
            .focused($isInputFocused)
            .submitLabel(.send)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Capsule().fill(Color(hex: "#18181D")))
            .onSubmit {
                vm.sendUserReply(vm.inputText)
            }
            .disabled(finished)

            trailingInputButton
                .disabled(finished)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .opacity(finished ? 0.4 : 1)
    }

    /// Когда в поле есть непустой текст — показываем кнопку «Отправить»
    /// (стрелка вверх), тап отправляет реплику и чистит поле, фокус
    /// сохраняется чтобы юзер мог сразу писать следующее. Пусто — та же
    /// круглая кнопка возвращает микрофон/запись (уходим из text-режима
    /// в buttons, оттуда стандартный флоу с крупным Speak).
    @ViewBuilder
    private var trailingInputButton: some View {
        let hasText = !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Button {
            if hasText {
                vm.sendUserReply(vm.inputText)
            } else {
                isInputFocused = false
                vm.switchToButtons()
            }
        } label: {
            Image(systemName: hasText ? "arrow.up" : "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.lsPink))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: hasText)
    }
}

// MARK: - Conversation info sheet
/// Sheet-подсказка «Conversation mode» — открывается тапом chip
/// «What to reply?» в интерактивных степах (.date / .speaking). Простой
/// info-щит на языке юзера: объясняет, что идёт живой диалог с учителем
/// на тему `vm.conversationTopic`. Локализованные строки —
/// `lesson.conversation.info.*` (см. Localizable.xcstrings).
private extension LessonView {

    var conversationInfoSheet: some View {
        VStack(spacing: 16) {
            // Все три строки — на РОДНОМ языке юзера (`nativeUILang` в VM),
            // не на языке изучения. Чтобы подсказка про режим диалога
            // была понятна юзеру сразу.
            Text(vm.conversationInfoTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            Text(vm.conversationInfoBody)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)

            Button {
                vm.closeConversationInfoSheet()
            } label: {
                Text(vm.conversationInfoCloseLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(Color.lsPink))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Hint sheet
private extension LessonView {

    @ViewBuilder
    var hintSheet: some View {
        if vm.isHintsExhausted {
            hintSheetExhausted
        } else {
            hintSheetPrompt
        }
    }

    /// Первый sheet — тизер. Сам текст подсказки НЕ показываем — только
    /// счётчик доступных подсказок и кнопка «Show me the hint». Открытие
    /// самой подсказки — во втором sheet после тапа.
    var hintSheetPrompt: some View {
        VStack(spacing: 20) {
            Capsule().fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 4).padding(.top, 10)

            Text(L10n.tr("lesson.hint.title", "Need a hint?"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text(L10n.tr("lesson.hint.subtitle",
                        "I’ll suggest one natural reply for this moment. You can say it as is or make it yours."))
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { i in
                    hintBulb(filled: i < vm.hintsRemaining)
                }
            }
            .padding(.vertical, 10)

            Spacer(minLength: 0)

            Button {
                vm.showHint()
            } label: {
                Text(L10n.tr("lesson.hint.show", "Show me the hint"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(Color.lsPink))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .disabled(vm.currentSuggestedReply == nil)
            .opacity(vm.currentSuggestedReply == nil ? 0.4 : 1)

            Button {
                vm.closeHintSheet()
            } label: {
                Text(L10n.tr("lesson.hint.not_now", "Not now"))
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium])
        .presentationBackground(Color(hex: "#0B0B0D"))
    }

    /// Второй sheet — сам ответ подсказки. Стилистика Figma 373:2263
    /// (score sheet): grabber, title left, единственная dark-card с
    /// green-текстом внутри которой есть встроенный subtitle, две
    /// разноширинные кнопки внизу.
    var hintRevealSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 14)

            Text(L10n.tr("lesson.hint.reveal_title", "Try saying"))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

            hintRevealCard
                .padding(.horizontal, 20)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button {
                    vm.closeHintRevealSheet()
                } label: {
                    Text(L10n.tr("lesson.hint.close", "Close"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 140, height: 54)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button {
                    vm.applyRevealedHint()
                } label: {
                    Text(L10n.tr("lesson.hint.use", "Use this reply"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(Color.lsPink))
                }
                .disabled(vm.revealedHintText == nil)
                .opacity(vm.revealedHintText == nil ? 0.5 : 1)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .presentationDetents([.medium])
        .presentationBackground(Color(hex: "#0B0B0D"))
    }

    /// Dark-card #19191D cr=18 с подсказкой:
    /// - большой green-текст (по мотивам «¡Hola a todos!, soy Evan.»)
    /// - под ним 13pt gray subtitle (по мотивам «Green means clean…»)
    /// Пока GPT-фолбэк генерит — спиннер + текст «Thinking…».
    @ViewBuilder
    var hintRevealCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.isGeneratingHint {
                HStack(spacing: 10) {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                    Text(L10n.tr("lesson.hint.generating", "Thinking of a good reply…"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "#9A9AA3"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let text = vm.revealedHintText, !text.isEmpty {
                Text(text)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: "#32D74B"))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.tr("lesson.hint.reveal_subtitle",
                            "Say it out loud when you're ready"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(L10n.tr("lesson.hint.unavailable",
                            "No hint for this moment — try answering freely."))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#19191D")))
    }

    var hintSheetExhausted: some View {
        VStack(spacing: 20) {
            Capsule().fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 4).padding(.top, 10)

            Text("You’re out of hints")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("You’ve used all 3 free hints.\nUnlock more whenever you get stuck.")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    hintBulb(filled: false)
                }
            }
            .padding(.vertical, 10)

            Spacer(minLength: 0)

            Button {
                vm.closeHintSheet()
                premium.showPaywall(.in_lessons)
            } label: {
                Text("Unlock more hints")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(Color.lsPink))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Button {
                vm.closeHintSheet()
            } label: {
                Text("Continue without hints")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium])
        .presentationBackground(Color(hex: "#0B0B0D"))
    }

    func hintBulb(filled: Bool) -> some View {
        Image(systemName: filled ? "lightbulb.fill" : "lightbulb")
            .font(.system(size: 42, weight: .medium))
            .foregroundStyle(.lsPink)
    }
}

// MARK: - Score sheet (Figma 373:2263)
private extension LessonView {

    /// Bottom sheet «How it sounded» — оценка произношения последнего голосового
    /// ответа юзера. Открывается тапом Hint если `vm.lastScore != nil`.
    @ViewBuilder
    var scoreSheet: some View {
        if let score = vm.lastScore {
            scoreSheetContent(score)
        } else {
            EmptyView()
        }
    }

    func scoreSheetContent(_ s: PronunciationScore) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: "#9A9AA3"))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Text("How it sounded")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

            scoreHeaderRow(s)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

            scoreCleanCard(s)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            scoreFeedbackCard(s)
                .padding(.horizontal, 20)

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                Button {
                    vm.scoreOnceMore()
                } label: {
                    Text("Once more")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 32)
                                .fill(Color(hex: "#37373C"))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    vm.scoreNext()
                } label: {
                    Text("Next")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 32)
                                .fill(Color.lsPink)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .presentationDetents([.large])
        .presentationBackground(Color(hex: "#18181D"))
    }

    /// «82 out of 100» слева + verdict/subVerdict справа. Figma 373:2263:
    /// 82 = 48/700 green, out of 100 = 14/400 grey, verdict = 16/590 white,
    /// sub-verdict = 13/400 grey.
    func scoreHeaderRow(_ s: PronunciationScore) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(s.score)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Color(hex: "#31D64A"))
                Text("out of \(s.totalPossible)")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(s.verdict)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(s.subVerdict)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Card с распознанным transcript-ом (зелёный текст) + подпись.
    /// Figma: bg #232329 cr=16, transcript 20/510 green, hint 12/400 grey.
    func scoreCleanCard(_ s: PronunciationScore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.cleanTranscript)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color(hex: "#31D64A"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(s.accentHint)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#232329")))
    }

    /// Amber-tinted tip-card с советом по акценту. Figma: fill #FFAF1F@13%, cr=14.
    /// Текст 14/400 белый.
    func scoreFeedbackCard(_ s: PronunciationScore) -> some View {
        Text(s.feedback)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#FFAF1F").opacity(0.13)))
    }
}

// MARK: - Animated equalizer (переиспользуется в Emma-says пилюле и в Speak-кнопке)
/// 5 вертикальных капсул. Циклим индексы `heights` чтобы получить анимацию
/// «пульсации». Размеры и цвет параметризуются под место использования:
/// - Emma says pill: `barWidth: 2.5, spacing: 2, heights: [7,13,9,15,6]` розовый
/// - Recording big mic (74×74 круг): `barWidth: 4, spacing: 4, heights: [12,24,34,20,28]` белый
private struct AnimatedEqualizer: View {
    let color: Color
    var barWidth: CGFloat = 2.5
    var barSpacing: CGFloat = 2
    var heights: [CGFloat] = [7, 13, 9, 15, 6]

    @State private var offset: Int = 0
    private let tick = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<heights.count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: barWidth, height: heights[(i + offset) % heights.count])
                    .animation(.easeInOut(duration: 0.28), value: offset)
            }
        }
        .frame(height: heights.max() ?? 15, alignment: .center)
        .onReceive(tick) { _ in
            offset = (offset + 1) % heights.count
        }
    }
}

// MARK: - Typing indicator (assistant bubble stand-in)

/// Серый бабл-индикатор «{teacher} is typing…» — как в Talk
/// (`TalkView.TypingIndicatorBubble`). Показываем в чате урока пока
/// ждём ответ учителя (сервер chat-turn или клиентский GPT).
private struct LessonTypingIndicatorBubble: View {
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

import SwiftUI
import SwiftData

struct OnboardingRootView: View {
    @Environment(SubscriptionService.self) private var premium
    @State private var vm: OnboardingViewModel
    @State private var playback = PlaybackService()
    @State private var avatar = AvatarPlayer()
    @Namespace private var animation

    init(user: UserEntity, repository: UserRepository, onFinished: @escaping () -> Void) {
        _vm = State(
            wrappedValue: OnboardingViewModel(
                user: user,
                repository: repository,
                onFinished: onFinished
            )
        )
    }

    var body: some View {
        contentView
            .animation(.linear(duration: 0.3), value: vm.currentStep)
            .animation(.linear(duration: 0.3), value: vm.selectedTeacher)
            .sensoryFeedback(.levelChange, trigger: vm.currentStep)
            .sensoryFeedback(.selection, trigger: vm.selectedGrade)
            .sheet(isPresented: $vm.isTimePickerShown) {
                timePickerSheet
            }
            .onAppear { playCurrentAvatar() }
            .onChange(of: vm.currentStep) { _, _ in playCurrentAvatar() }
            .onChange(of: vm.selectedLanguage) { _, _ in playCurrentAvatar() }
            .onChange(of: vm.selectedTeacher) { _, _ in
                if vm.currentStep == .seven { playCurrentAvatar() }
            }
            .alert(
                "Couldn’t finish onboarding",
                isPresented: Binding(
                    get: { vm.commitError != nil },
                    set: { if !$0 { vm.commitError = nil } }
                )
            ) {
                Button("OK") { vm.commitError = nil }
            } message: {
                Text(vm.commitError ?? "")
            }
    }
}

// MARK: - UI Components
private extension OnboardingRootView {
    var contentView: some View {
        VStack {
            bottomView
                .padding(.vertical)
                .background(
                    // Glass-карточка по Figma 373:1609: fill white@10% + backdrop
                    // blur ~25pt, cr=32. Используем UnevenRoundedRectangle с
                    // верхними углами, т.к. карточка тянется до низа экрана.
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: 32, topTrailing: 32),
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.10))
                    .background(
                        .ultraThinMaterial,
                        in: UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 32, topTrailing: 32),
                            style: .continuous
                        )
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(
            // Оба скрима в одном ZStack с общим ignoresSafeArea, иначе
            // bottom-align считается по safe area и под home indicator
            // остаётся кусок нескрымленного видео.
            ZStack {
                AvatarPlayerView(player: avatar.videoPlayer)

                VStack(spacing: 0) {
                    // Верхний скрим (Figma 373:1609): 150pt, black@0.45 → 0.
                    LinearGradient(
                        colors: [Color.black.opacity(0.45), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)

                    Spacer(minLength: 0)

                    // Нижний скрим (Figma): 560pt, #0A0A0C 0 → 0.72@50% → 0.96.
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0), location: 0),
                            .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.72), location: 0.5),
                            .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.96), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 560)
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        )
        .overlay(alignment: .top) {
            progressHeaderView
                .padding(.horizontal, 15)
        }
    }

    var progressHeaderView: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(vm.currentStep.rawValue) of \(OnboardingStep.allCases.count)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                ForEach(OnboardingStep.allCases) { step in
                    Capsule()
                        .fill(.white)
                        .frame(height: 3)
                        .opacity(step.rawValue <= vm.currentStep.rawValue ? 1 : 0.28)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: vm.currentStep)
        }
    }

    @ViewBuilder
    var bottomView: some View {
        switch vm.currentStep {
        case .one:   firstStepView
        case .two:   secondStepView
        case .three: thirdStepView
        case .four:  fourthStepView
        case .five:  fifthStepView
        case .six:   sixStepView
        case .seven: lastStepView
        }
    }

    var firstStepView: some View {
        VStack(alignment: .center, spacing: 16) {
            titleView("Hi. I’ve been waiting for you.\nWhat’s your name?")

            subtitleView("Let's make this experience feel truly personal and\nunique.")

            TextField("Your name", text: $vm.name)
                .textFieldStyle(OnboardingFieldStyle())
                .padding(.horizontal)

            continueButton
                .disabled(!vm.canAdvance)
        }
        .multilineTextAlignment(.center)
    }

    var secondStepView: some View {
        VStack(alignment: .center, spacing: 16) {
            titleView("Which language do you\nwant to learn?")

            subtitleView("I’ll carefully shape every conversation around your\nchoice to suit your needs.")

            HStack(alignment: .center, spacing: 16) {
                ForEach(LanguageCode.allCases) { lang in
                    LanguageSelectionBtnView(
                        language: lang,
                        isSelected: vm.selectedLanguage == lang) { selection in
                            vm.selectedLanguage = selection
                        }
                }
            }
            .padding(.horizontal)

            continueButton
        }
    }

    var thirdStepView: some View {
        VStack(alignment: .center, spacing: 16) {
            titleView("Why \(vm.selectedLanguage.displayTitle) \(vm.name) ?")

            subtitleView("I’ll carefully shape every conversation around your\nchoice to suit your needs.")

            VStack(alignment: .center, spacing: 10) {
                HStack(alignment: .center, spacing: 9) {
                    goalButton(.work)
                    goalButton(.movingAbroad)
                    goalButton(.exam)
                }

                HStack(alignment: .center, spacing: 9) {
                    goalButton(.travel)
                    goalButton(.toTalkToTeacher)
                    somethingElseBtnView
                }

                continueButton
                    .disabled(!vm.canAdvance)
            }
        }
    }

    var fourthStepView: some View {
        VStack(alignment: .center, spacing: 16) {
            titleView("I want to hear you.\nLet me listen.")
            subtitleView("Recording only while you hold the mic. Clips are\ndeleted after scoring. You can type instead any time.")

            Button {
                vm.requestMicPermissionAndProceed()
            } label: {
                Text("Allow microphone")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(MainPinkBtnStyle())
            .padding(.horizontal)

            Button {
                vm.nexStep()
            } label: {
                Text("Skip for now")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top)
        }
    }

    var fifthStepView: some View {
        VStack(alignment: .center, spacing: 16) {
            titleView("When should I remind you\nabout our lessons?")

            VStack(alignment: .center, spacing: 10) {
                Button {
                    vm.showTimePicker()
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        timeSquare(vm.reminderHourString)

                        Text(":")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Color(hex: "CCCCD6"))

                        timeSquare(vm.reminderMinuteString)
                    }
                }

                subtitleView("One notification a day. Nothing else.")
            }

            continueButton
        }
        // Пермишн на уведомления запрашиваем ровно когда 5-й шаг реально
        // появился на экране — иначе системный алерт всплывает над предыдущим
        // или следующим шагом (async нативного диалога).
        .onAppear { vm.requestNotificationAccessIfNeeded() }
    }

    var sixStepView: some View {
        VStack(alignment: .center, spacing: 16) {
            titleView("How much \(vm.selectedLanguage.displayTitle) do you\nalready have?")

            VStack(spacing: 10) {
                ForEach(LangGrade.allCases) { grade in
                    GradeSelectionBtnView(
                        grade: grade, isSelected: vm.selectedGrade == grade) { langGrade in
                            vm.selectedGrade = langGrade
                        }
                }
            }
            .padding(.horizontal)

            subtitleView("No test. I’ll feel it out as we go.")

            continueButton
        }
    }

    var lastStepView: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Who do you want to learn with?")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            HStack(alignment: .center, spacing: 9) {
                Text("\(vm.selectedTeacher.name), \(vm.selectedTeacher.age)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Text(vm.selectedTeacher.isFreeTier ? "FREE" : "PREMIUM")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(vm.selectedTeacher.isFreeTier ? Color(hex: "#32D74B") : Color(hex: "#FF0062"))
                    )
            }

            Text(vm.selectedTeacher.description)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(hex: "#DBDBE3"))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(alignment: .center, spacing: 10) {
                Button {
                    playCurrentAvatar()
                } label: {
                    Label("Hear her voice", systemImage: "speaker.wave.1")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 15)
                        .glassedEffect(
                            in: Capsule(),
                            isClear: false,
                            tint: .white.opacity(0.16),
                            interactive: false
                        )
                }

                Text(vm.selectedTeacher.country.capitalized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 15)
                    .glassedEffect(
                        in: Capsule(),
                        isClear: false,
                        tint: .white.opacity(0.16),
                        interactive: false
                    )
            }

            HStack(alignment: .center, spacing: 9) {
                RespectRateView(rate: 0)

                Text("you two are warming up")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(hex: "#C7C7D1"))
            }
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 13) {
                    ForEach(TeacherProfile.allCases) { teacher in
                        Button {
                            vm.selectTeacher(teacher)
                        } label: {
                            VStack(alignment: .center, spacing: 7) {
                                Image(teacher.avatarImageName)
                                    .resizable()
                                    .frame(width: 62, height: 62)
                                    .clipShape(.circle)
                                    .overlay {
                                        // Premium-девушки задиммлены, чтобы
                                        // визуально отличались от Emma (free).
                                        if !teacher.isFreeTier {
                                            Circle().fill(Color.black.opacity(0.45))
                                        }
                                        if vm.selectedTeacher == teacher {
                                            Circle()
                                                .stroke(.lsPink, lineWidth: 1.5)
                                        }
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        // Замочек в правом-нижнем углу для всех
                                        // non-free девушек.
                                        if !teacher.isFreeTier {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .frame(width: 20, height: 20)
                                                .background(Circle().fill(Color.black.opacity(0.75)))
                                                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                                        }
                                    }

                                Text(teacher.name)
                                    .font(
                                        .system(
                                            size: 12,
                                            weight: vm.selectedTeacher == teacher ? .semibold : .regular
                                        )
                                    )
                                    .foregroundStyle(
                                        vm.selectedTeacher == teacher ? .white : Color(hex: "#CCCCD6")
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 86)
            .padding(.bottom, 8)

            Button {
                // Free-учительница ИЛИ уже премиум → нормальный commit.
                // Иначе → показываем `.onboarding` пейвол; после успешной
                // покупки премиум-статус обновится и следующий тап уйдёт в
                // commit. Отмена пейвола оставляет юзера здесь — тап снова
                // покажет пейвол, пока он либо не купит, либо не сменит
                // учительницу на бесплатную.
                if vm.selectedTeacher.isFreeTier || premium.isActiveSubscription {
                    Task { await vm.commit() }
                } else {
                    // Premium-teacher выбрана но подписки нет → пейвол с
                    // видео этой teacher. После покупки — автокоммит того же
                    // выбора и выход из онбординга. Отмена — юзер остаётся
                    // на экране выбора и может сменить teacher.
                    premium.showPaywall(.onboarding, teacher: vm.selectedTeacher) {
                        Task { await vm.commit() }
                    }
                }
            } label: {
                Group {
                    if vm.isCommitting {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text("Start with \(vm.selectedTeacher.name)")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .buttonStyle(MainPinkBtnStyle())
            .padding(.horizontal)
            .padding(.bottom, 8)
            .disabled(vm.isCommitting)

            Text(vm.selectedTeacher.isFreeTier
                 ? "The other four unlock with Premium"
                 : "\(vm.selectedTeacher.name) unlocks with Premium")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: "#B2B2BF"))
        }
    }

    var continueButton: some View {
        Button {
            vm.nexStep()
        } label: {
            Text("Continue")
                .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(MainPinkBtnStyle())
        .padding(.horizontal)
    }

    var timePickerSheet: some View {
        VStack(spacing: 16) {
            Text("Pick a time")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 20)

            DatePicker(
                "",
                selection: $vm.reminderTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)

            Button {
                vm.isTimePickerShown = false
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(MainPinkBtnStyle())
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
    }

    @ViewBuilder
    var somethingElseBtnView: some View {
        Button {
            vm.selectGoal(.somethingElse)
        } label: {
            Text("Something else")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
        }
        .background {
            if vm.selectedGoal == .somethingElse {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.lsPink)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
        }
    }

    func playSample(for teacher: TeacherProfile) {
        let file = teacher.voiceSampleFileName as NSString
        let name = file.deletingPathExtension
        let ext = file.pathExtension
        playback.play(bundleResource: name, ext: ext.isEmpty ? "mp3" : ext)
    }

    /// Играет фон-видео + приветственное аудио текущего шага один раз.
    /// Между шагами видео начинается и заканчивается на одном rest-кадре,
    /// так что переключение бесшовное.
    func playCurrentAvatar() {
        switch vm.currentStep {
        case .one, .two, .three, .four, .five, .six:
            guard let screen = OnboardingScreen(rawValue: vm.currentStep.rawValue),
                  let video = screen.videoURL(for: vm.selectedLanguage)
            else { return }
            let audio = screen.voiceURL(for: vm.selectedLanguage)
            avatar.playOnce(video: video, audio: audio)
        case .seven:
            guard let video = vm.selectedTeacher.chooseVideo else { return }
            let audio = vm.selectedTeacher.chooseVoice(for: vm.selectedLanguage)
            avatar.playOnce(video: video, audio: audio)
        }
    }

    func goalButton(_ goal: LearningGoal) -> some View {
        LanguageReasonBtnView(
            title: LocalizedStringResource(stringLiteral: goal.displayTitle),
            isSelected: vm.selectedGoal == goal
        ) {
            vm.selectGoal(goal)
        }
    }

    func titleView(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .multilineTextAlignment(.center)
    }

    func subtitleView(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color(hex: "#9A9AA4"))
            .padding(.horizontal, 26)
            .multilineTextAlignment(.center)
    }

    func timeSquare(_ time: String) -> some View {
        Text(time)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(.white)
            .padding(24)
            .glassedEffect(
                in: RoundedRectangle(cornerRadius: 16),
                isClear: false,
                tint: .white.opacity(0.16),
                interactive: false
            )
    }
}

fileprivate struct RespectRateView: View {
    let rate: Int
    var maxHearts: Int = 5
    var heartSize: CGFloat = 12
    var color: Color = .lsPink

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<maxHearts, id: \.self) { index in
                Image(systemName: index < rate ? "heart.fill" : "heart")
                    .font(.system(size: heartSize, weight: .light))
                    .foregroundStyle(color)
                    .symbolEffect(.bounce, value: rate)
            }
        }
    }
}

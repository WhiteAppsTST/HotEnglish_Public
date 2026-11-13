import SwiftUI

struct AssistenceSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var premium
    @State private var vm: AssistenceSelectionViewModel
    @State private var avatar = AvatarPlayer()

    init(user: UserEntity, repository: UserRepository) {
        _vm = State(
            wrappedValue: AssistenceSelectionViewModel(user: user, repository: repository)
        )
    }

    var body: some View {
        contentView
            .animation(.linear(duration: 0.3), value: vm.selectedTeacher)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { playCurrentAvatar() }
            .onChange(of: vm.selectedTeacher) { _, _ in playCurrentAvatar() }
            .onDisappear {
                // База не задана — stop() просто заглушит текущее видео +
                // аудио, чтобы фраза не договаривалась поверх Home.
                avatar.stop()
            }
    }

    /// Играет choose-видео + приветственный войс выбранной учительницы на
    /// активном языке. Тот же принцип что в OnboardingRootView (шаг 7).
    private func playCurrentAvatar() {
        guard let video = vm.selectedTeacher.chooseVideo else { return }
        let audio = vm.selectedTeacher.chooseVoice(for: vm.currentLanguage)
        avatar.playOnce(video: video, audio: audio)
    }
}

// MARK: - Layout
private extension AssistenceSelectionView {

    var contentView: some View {
        VStack {
            bottomView
                .padding(.vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(
            // Silent video выбранной учительницы + оба скрима по Figma
            // 373:1999. Обёрнуто в один ZStack с общим ignoresSafeArea —
            // иначе overlay-скрим bottom-align'ится по safe area, а не по
            // физическому низу экрана, и под home indicator виден кусок
            // необработанного видео.
            ZStack {
                AvatarPlayerView(player: avatar.videoPlayer)

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)

                    Spacer(minLength: 0)

                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0), location: 0),
                            .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.80), location: 0.45),
                            .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.98), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 540)
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        )
        .overlay(alignment: .top) {
            headerView
                .padding(.horizontal, 15)
        }
    }

    var headerView: some View {
        HStack {
            backButton
            Spacer()
        }
        .overlay {
            Text("Your teacher")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom content
private extension AssistenceSelectionView {

    var bottomView: some View {
        VStack(alignment: .center, spacing: 8) {
            titleRow

            Text(vm.selectedTeacher.description)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(hex: "#DBDBE3"))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            infoChipsRow

            respectRow
                .padding(.bottom, 8)

            teachersScroll
                .padding(.bottom, 8)

            studyButton

            Text("Switching later is possible — progress always carries over.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: "#B2B2BF"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    var titleRow: some View {
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
    }

    var infoChipsRow: some View {
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
            .buttonStyle(.plain)

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
    }

    var respectRow: some View {
        HStack(alignment: .center, spacing: 9) {
            RespectRateView(rate: vm.heartsForSelected)

            Text("you two are warming up")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(hex: "#C7C7D1"))
        }
    }

    var teachersScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 13) {
                ForEach(vm.teachers) { teacher in
                    Button {
                        // Просмотр учительниц бесплатный: тап только
                        // переключает preview (видео/голос), пейвол не
                        // показываем. Гейт премиума — на кнопке Study with.
                        vm.selectTeacher(teacher)
                    } label: {
                        teacherAvatar(teacher)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 86)
    }

    @ViewBuilder
    func teacherAvatar(_ teacher: TeacherProfile) -> some View {
        VStack(alignment: .center, spacing: 7) {
            Image(teacher.avatarImageName)
                .resizable()
                .frame(width: 62, height: 62)
                .clipShape(.circle)
                .overlay {
                    // Затемнение только для premium-teacher'ов И только пока
                    // у юзера нет активной подписки. После покупки все
                    // учительницы разлочены визуально.
                    if !teacher.isFreeTier, !vm.isPremium {
                        Circle().fill(Color.black.opacity(0.45))
                    }
                    if vm.selectedTeacher == teacher {
                        Circle().stroke(.lsPink, lineWidth: 1.5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !teacher.isFreeTier, !vm.isPremium {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                }

            Text(teacher.name)
                .font(.system(
                    size: 12,
                    weight: vm.selectedTeacher == teacher ? .semibold : .regular
                ))
                .foregroundStyle(
                    vm.selectedTeacher == teacher ? .white : Color(hex: "#CCCCD6")
                )
        }
    }

    var studyButton: some View {
        Button {
            // Гейт премиума — только тут. Free teacher или уже premium —
            // сразу commit + dismiss. Premium teacher без подписки —
            // unified пейвол; после покупки колбэк применяет выбор и
            // возвращает на Home.
            if vm.selectedTeacher.isFreeTier || vm.isPremium {
                vm.commit()
                dismiss()
            } else {
                let chosen = vm.selectedTeacher
                premium.showPaywall(.onboarding, teacher: chosen) {
                    vm.selectTeacher(chosen)
                    vm.commit()
                    dismiss()
                }
            }
        } label: {
            Text("Study with \(vm.selectedTeacher.name)")
                .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(MainPinkBtnStyle())
        .padding(.horizontal)
        .padding(.bottom, 8)
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

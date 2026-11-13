import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionService.self) private var premium
    @State private var vm: HomeViewModel
    @State private var homeAvatar = HomeAvatarController()
    @Namespace private var animation

    init(user: UserEntity) {
        _vm = State(wrappedValue: HomeViewModel(user: user))
    }

    @State private var showDailyLimitSheet: Bool = false

    /// AI-disclosure alert. Показываем ОДИН раз при первом попадании
    /// на Home (после онбординга и первого пейвола). Юзер тапает OK →
    /// флаг сохраняется в UserDefaults, больше не показываем никогда.
    /// Требование App Review: явное уведомление о том, что клиентские
    /// сообщения уходят в третьесторонний AI (OpenAI).
    @AppStorage("app.ai_disclosure_acknowledged") private var aiDisclosureAcknowledged: Bool = false
    /// Локальная @State-копия: alert показывается только после кадра —
    /// иначе он появится ПОВЕРХ paywall / онбординга, вылезающих сразу
    /// на первом рендере. Ставим true в .task после короткой задержки.
    @State private var showAIDisclosureAlert: Bool = false

    var body: some View {
        NavigationStack {
            contentStack
                .background(backgroundLayer)
                .toolbar(.hidden, for: .navigationBar)
                .onAppear {
                    vm.onAppear()
                    homeAvatar.configure(for: vm.teacher)
                }
                .onChange(of: vm.teacher) { _, new in
                    homeAvatar.configure(for: new)
                }
                .sheet(isPresented: $showDailyLimitSheet) {
                    dailyLimitSheet
                }
                .sheet(item: Binding(
                    get: { vm.awayMessage },
                    set: { if $0 == nil { vm.dismissAwayMessage() } }
                )) { data in
                    AwayMessageSheet(
                        data: data,
                        onWinBack: {
                            // TODO: подцепить lesson-route на currentUnit.currentStep
                            vm.dismissAwayMessage()
                        },
                        onDismiss: { vm.dismissAwayMessage() }
                    )
                }
                // Мост из AppDelegate: тап по Apphud-пушу с `type: "away"`
                // публикует декодированный AwayMessageData в NotificationCenter,
                // Home подхватывает и открывает наш sheet поверх текущего экрана.
                .onReceive(NotificationCenter.default.publisher(for: .awayMessageReceived)) { note in
                    guard let data = note.object as? AwayMessageData else { return }
                    vm.presentAwayMessage(data)
                }
                // Один раз на юзера: явное уведомление про использование
                // сторонних AI-сервисов (App Review). Задержка 0.6c даёт
                // онбординговому/первому paywall'у отработать первым —
                // alert не должен появиться поверх них.
                .task {
                    guard !aiDisclosureAcknowledged else { return }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if !aiDisclosureAcknowledged { showAIDisclosureAlert = true }
                }
                .alert(
                    L10n.tr("home.ai_disclosure.title", "About AI in this app"),
                    isPresented: $showAIDisclosureAlert
                ) {
                    Button(L10n.tr("home.ai_disclosure.ok", "OK")) {
                        aiDisclosureAcknowledged = true
                    }
                } message: {
                    Text(L10n.tr(
                        "home.ai_disclosure.body",
                        "This app uses third-party AI services (OpenAI) to generate teacher replies, evaluate your practice, and produce the teacher's voice. Messages you send during lessons and free chat are sent to these providers for processing according to their terms. We do not control or take responsibility for how third-party AI providers process this data.\n\nBy continuing to use the app, you confirm your agreement."
                    ))
                }
        }
    }
}

// MARK: - Daily lesson limit sheet (Figma 425:7070)
private extension HomeView {

    var dailyLimitSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.22))
                .frame(width: 36, height: 4)
                .padding(.top, 14)
                .padding(.bottom, 18)

            Text("That’s today’s lesson done.")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)

            Text("You get one step a day on the free plan.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 20)

            // Mixed-color progress bar — 4 сегмента, height 6, cr=3.
            HStack(spacing: 6) {
                Capsule().fill(Color(hex: "#31D64A")).frame(height: 6)
                Capsule().fill(Color(hex: "#31D64A")).frame(height: 6)
                Capsule().fill(Color.lsPink).frame(height: 6)
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Text("Ordering Coffee · 2 of 4 steps")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .padding(.bottom, 18)

            unlockCard
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            Text("Your streak is safe — today already counts.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: "#6A6A72"))
                .padding(.bottom, 18)

            VStack(spacing: 12) {
                Button {
                    showDailyLimitSheet = false
                    premium.showPaywall(.in_lessons)
                } label: {
                    Text("Continue now with Premium")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(Color.lsPink))
                }
                .buttonStyle(.plain)

                Button {
                    showDailyLimitSheet = false
                    // TODO: открыть TalkView
                } label: {
                    Text("Talk to Emma · 3 free texts left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(hex: "#141417"))
    }

    /// Card «Next step unlocks in Xh Ym» с streak-огнём. Figma: bg #FFFFFF@6%,
    /// таймер 20/590 white, streak 15/590 amber #FFB020.
    var unlockCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next step unlocks in")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                Text("14h 20m")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("🔥 \(vm.streakDays)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "#FFB020"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Background
private extension HomeView {
    var backgroundLayer: some View {
        VStack(spacing: 0) {
            // Idle-loop выбранной учительницы + периодические реакции
            // (см. HomeAvatarController). Аспект держим fill — как раньше был
            // static Image.
            AvatarPlayerView(player: homeAvatar.player.videoPlayer)
                .frame(height: 393)
                .clipped()
            Color(hex: "#0B0B0D")
        }
        .ignoresSafeArea()
    }
}

// MARK: - Root layout (static top + scrolling course)
private extension HomeView {
    var contentStack: some View {
        VStack(spacing: 0) {
            heroBlock
            statsRow
                .padding(.horizontal, 16)
                .padding(.top, 20)

            ScrollView(showsIndicators: false) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 14) {
                        if vm.isQuotaExhausted {
                            limitBanner(now: context.date)
                        }
                        courseSection(now: context.date)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    var heroBlock: some View {
        Color.clear
            .frame(height: 393)
            .overlay(alignment: .top) {
                HStack {
                    teacherSwapChip
                    Spacer()
                    profileChip
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)
            }
            .overlay(alignment: .bottomLeading) {
                heroContent
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
    }

    var heroContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.teacher.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 12) {
                Text(vm.teacherQuote)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#D1D1DB"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                talkButton
            }
        }
    }
}

// MARK: - Top chips
private extension HomeView {

    var teacherSwapChip: some View {
        NavigationLink {
            AssistenceSelectionView(
                user: vm.user,
                repository: UserRepository(context: context)
            )
            .navigationTransition(.zoom(sourceID: "swap", in: animation))
        } label: {
            HStack(spacing: 6) {
                Image(vm.teacher.avatarImageName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(.circle)

                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 81, height: 44)
            .background(
                Capsule().fill(Color.black.opacity(0.4))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "swap", in: animation)
        // DEBUG: длинный тап на swap-чип открывает `.lesson_end` пейвол
        // (Lesson End) — быстрая A/B-сверка с Figma без прохождения
        // урока. TODO: удалить перед релизом.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in premium.showPaywall(.lesson_end) }
        )
    }

    var profileChip: some View {
        NavigationLink {
            ProfileView(
                user: vm.user,
                repository: UserRepository(context: context)
            )
            .navigationTransition(.zoom(sourceID: "profile", in: animation))
        } label: {
            Image(systemName: "person.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 21)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        // DEBUG: длинный тап по profile-чипу открывает Unified пейвол —
        // быстрый A/B pixel-perfect матч с Figma без прохождения онбординга.
        // TODO: удалить перед релизом.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in premium.showPaywall(.onboarding) }
        )
        .matchedTransitionSource(id: "profile", in: animation)
    }

    /// Talk button. Normal-состояние = прежний glass-look (373:3151).
    /// Limit-состояние = solid pink capsule по 425:7113.
    var talkButton: some View {
        NavigationLink {
            TalkView(
                user: vm.user,
                repository: UserRepository(context: context),
                context: context
            )
            .navigationTransition(.zoom(sourceID: "talk", in: animation))
        } label: {
            Group {
                // Pink CTA появляется когда исчерпан ЛЮБОЙ дневной лимит:
                // lesson-quota (нельзя проходить шаги) или talk-quota
                // (нельзя писать в свободный чат). В обоих случаях Talk —
                // единственный оставшийся способ дальше взаимодействовать.
                if vm.isQuotaExhausted || vm.isTalkQuotaExhausted {
                    talkContentLimit
                } else {
                    talkContentNormal
                }
            }
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "talk", in: animation)
    }

    /// Прежний вид (glass + circle-badge) — не трогаем.
    var talkContentNormal: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("Talk")
                .font(.system(size: 15, weight: .semibold))
            Group {
                if vm.talkBadgeIsUnlimited {
                    Image(systemName: "infinity")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text(vm.talkBadgeText)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
                .foregroundStyle(.white)
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, 4)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 110, minHeight: 44, maxHeight: 44, alignment: .center)
        .glassedEffect(in: Capsule(), isClear: true)
        .contentShape(Capsule())
    }

    /// Figma 425:7113: solid pink capsule + pill badge 20×19 cr=14.
    var talkContentLimit: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("Talk")
                .font(.system(size: 15, weight: .semibold))
            Group {
                if vm.talkBadgeIsUnlimited {
                    Image(systemName: "infinity")
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    Text(vm.talkBadgeText)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
                .foregroundStyle(.white)
                .frame(minWidth: 20, minHeight: 19)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.25)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 110, minHeight: 44, maxHeight: 44, alignment: .center)
        .background(Capsule().fill(Color.lsPink))
        .contentShape(Capsule())
    }
}

// MARK: - Stats row
private extension HomeView {

    var statsRow: some View {
        HStack(spacing: 10) {
            streakCard
            levelCard
            affinityCard
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    var streakCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#FF731F"), Color(hex: "#FF2600")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("\(vm.streakDays)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("days")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#9A9AA4"))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#19191D")))
    }

    var levelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(vm.currentLevelDisplay)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(vm.progressPercent)%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.lsPink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            gradeProgressBar
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#19191D")))
    }

    var gradeProgressBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.lsPink)
                        .frame(width: max(0, geo.size.width * vm.progressInCurrentGrade))
                }
        }
        .frame(height: 4)
    }

    /// ТЗ sec_327: «Отношения: 67%, симпатия» — полоса + стадия.
    /// Заменяет прежний hearts-UI.
    var affinityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(vm.affinityPercent)%")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text(vm.affinityStageLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.lsPink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            affinityBar
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#19191D")))
    }

    var affinityBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.lsPink)
                        .frame(width: max(0, geo.size.width * vm.affinityFraction))
                }
        }
        .frame(height: 4)
    }
}

// MARK: - Limit banner (daily lesson quota exhausted)
private extension HomeView {

    /// Figma 425:7113 «Daily limit banner»: 52pt, fill white@6%, cr=14.
    /// Title 13/semibold + subtitle 11/regular grey. Unlock chip 30pt cr=14
    /// pink. Показывается только при `isQuotaExhausted`.
    func limitBanner(now: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's step is done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text(bannerSubtitle(now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showDailyLimitSheet = true
            } label: {
                Text("Unlock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.lsPink))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    func bannerSubtitle(now: Date) -> String {
        let remaining = vm.quotaTimeRemaining(at: now) ?? "24h 0m"
        return L10n.tr("home.limit_banner.subtitle",
                       "Next opens in %@ · free plan",
                       remaining)
    }
}

// MARK: - Course section
private extension HomeView {

    func courseSection(now: Date) -> some View {
        VStack(spacing: 12) {
            courseHeader
            unitList(now: now)
        }
    }

    var courseHeader: some View {
        HStack {
            Text("Your course")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            NavigationLink {
                AllUnitsView(vm: vm)
                    .navigationTransition(.zoom(sourceID: "allunits", in: animation))
            } label: {
                HStack(spacing: 3) {
                    Text("All units")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color(hex: "#9A9AA4"))
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "allunits", in: animation)
        }
    }

    @ViewBuilder
    func unitList(now: Date) -> some View {
        if vm.isLoading {
            unitListSkeleton
        } else {
            VStack(spacing: 10) {
                ForEach(vm.unitsForCurrentLevel) { unit in
                    UnitCardView(vm: vm, unit: unit, now: now, animation: animation)
                }
            }
        }
    }
}

// MARK: - Skeleton (loading)
private extension HomeView {

    /// Показываем 5 плейсхолдер-карточек юнитов пока идёт fetch с бэка.
    /// TODO: цифра 5 подобрана визуально; при появлении backend'а можно
    /// брать last-known-count из локального SwiftData-кэша.
    var unitListSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { _ in
                unitCardSkeleton
            }
        }
    }

    var unitCardSkeleton: some View {
        HStack(spacing: 12) {
            SkeletonBar(shape: .circle)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(shape: .capsule)
                    .frame(width: 60, height: 10)
                SkeletonBar(shape: .capsule)
                    .frame(width: 160, height: 14)
            }

            Spacer(minLength: 0)

            SkeletonBar(shape: .capsule)
                .frame(width: 40, height: 14)
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#19191D")))
    }
}

// MARK: - SkeletonBar (нативный плейсхолдер с пульсацией)
private struct SkeletonBar: View {
    enum ShapeKind { case circle, capsule }
    let shape: ShapeKind

    @State private var pulsing = false

    var body: some View {
        Group {
            switch shape {
            case .circle:  Circle().fill(Color(hex: "#232329"))
            case .capsule: Capsule().fill(Color(hex: "#232329"))
            }
        }
        .opacity(pulsing ? 0.55 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}


// MARK: - Empty destination
private extension HomeView {

    var emptyDestination: some View {
        Color(hex: "#0B0B0D")
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
    }
}

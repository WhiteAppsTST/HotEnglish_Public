import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionService.self) private var premium
    @State private var vm: ProfileViewModel
    @Namespace private var animation

    init(user: UserEntity, repository: UserRepository) {
        _vm = State(wrappedValue: ProfileViewModel(user: user, repository: repository))
    }

    var body: some View {
        rootStack
            .background(Color(hex: "#0B0B0D").ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            // ManageLanguageView мог поменять `user.settings` вне VM —
            // при возврате Profile перечитываем актуальный язык, иначе
            // segmented показывает старое значение до перезапуска.
            .onAppear { vm.refreshFromUser() }
    }
}

// MARK: - Root layout
private extension ProfileView {

    var rootStack: some View {
        VStack(spacing: 0) {
            identityRow
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    premiumBanner
                    learningPlanCard
                    streakCard
                    teacherCard
                    finishedLessonsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    var identityRow: some View {
        HStack(spacing: 13) {
            avatarView

            Text(vm.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            settingsButton
        }
        .frame(height: 44)
    }
}

// MARK: - Identity subviews
private extension ProfileView {

    var avatarView: some View {
        Text(vm.initial)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.lsPink)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color(hex: "#FF2D7D").opacity(0.20)))
    }

    var settingsButton: some View {
        NavigationLink {
            SettingsView(
                user: vm.user,
                repository: UserRepository(context: context),
                context: context
            )
            .navigationTransition(.zoom(sourceID: "profile_settings", in: animation))
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(hex: "#18181D")))
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "profile_settings", in: animation)
    }
}

// MARK: - Premium banner
private extension ProfileView {

    var premiumBanner: some View {
        Button {
            premium.showPaywall(.onboarding)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Go Premium")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Four more teachers, unlimited talk")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: "#EAE0EF"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Upgrade")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(
                        Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1)
                    )
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 23)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#FF2D7C"), Color(hex: "#B7289E")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Learning plan (segmented control)
private extension ProfileView {

    var learningPlanCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Text("Learning plan")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                NavigationLink {
                    ManageLanguageView(
                        user: vm.user,
                        repository: UserRepository(context: context),
                        backTitle: "Profile"
                    )
                    .navigationTransition(.zoom(sourceID: "profile_manage", in: animation))
                } label: {
                    HStack(spacing: 5) {
                        Text("Manage")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .padding(.leading, 6)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: "profile_manage", in: animation)
            }

            languageSegmented
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 23).fill(Color(hex: "#18181D")))
    }

    var languageSegmented: some View {
        HStack(spacing: 4) {
            ForEach(vm.languages) { row in
                Button {
                    vm.selectLanguage(row.language)
                } label: {
                    languageOption(row)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#232329")))
        .animation(.easeInOut(duration: 0.18), value: vm.currentLanguage)
    }

    @ViewBuilder
    func languageOption(_ row: ProfileViewModel.LanguageRow) -> some View {
        let isActive = row.language == vm.currentLanguage
        HStack(spacing: 9) {
            flagCircle(for: row.language)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.language.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? .white : Color(hex: "#9A9AA3"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(row.level.grade) · \(row.progressPercent)%")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(isActive ? .lsPink : Color(hex: "#9A9AA3"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive ? Color(hex: "#FF2D7D").opacity(0.20) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    func flagCircle(for language: LanguageCode) -> some View {
        switch language {
        case .es:
            Circle()
                .fill(Color(hex: "#E53838"))
                .frame(width: 28, height: 28)
                .overlay(
                    Rectangle()
                        .fill(Color(hex: "#FFCC33"))
                        .frame(height: 11)
                )
                .clipShape(Circle())
        case .en:
            Circle()
                .fill(Color(hex: "#162870"))
                .frame(width: 28, height: 28)
                .overlay(
                    Group {
                        Rectangle().fill(Color.white).frame(width: 28, height: 6)
                        Rectangle().fill(Color.white).frame(width: 6, height: 28)
                        Rectangle().fill(Color(hex: "#CC1E2D")).frame(width: 28, height: 3)
                        Rectangle().fill(Color(hex: "#CC1E2D")).frame(width: 3, height: 28)
                    }
                )
                .clipShape(Circle())
        }
    }
}

// MARK: - Streak
private extension ProfileView {

    var streakCard: some View {
        VStack(spacing: 13) {
            // Плоский header без NavigationLink — секция не переходная,
            // статистика полностью инлайн ниже.
            HStack(spacing: 7) {
                Text("Streak")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            weekRow

            Rectangle()
                .fill(Color(hex: "#2E2E34"))
                .frame(height: 1)

            countsRow
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.top, 15)
        .padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: 23).fill(Color(hex: "#18181D")))
    }

    var weekRow: some View {
        HStack(spacing: 6) {
            ForEach(vm.streakWeek) { day in
                dayCell(day)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    func dayCell(_ day: ProfileViewModel.StreakDay) -> some View {
        VStack(spacing: 6) {
            dayDot(day)

            Text(weekdayLetter(day.date))
                .font(.system(size: 11, weight: day.isToday ? .semibold : .regular))
                .foregroundStyle(day.isToday ? .lsPink : Color(hex: "#9A9AA3"))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    func dayDot(_ day: ProfileViewModel.StreakDay) -> some View {
        let filled = day.isCompleted
        Circle()
            .fill(filled ? Color(hex: "#FF2D7D").opacity(0.22) : Color(hex: "#232329"))
            .frame(width: 38, height: 38)
            .overlay {
                if day.isToday {
                    Circle().stroke(Color.lsPink, lineWidth: 1.5)
                }
            }
            .overlay {
                if let order = day.orderInStreak {
                    Text("\(order)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.lsPink)
                }
            }
    }

    var countsRow: some View {
        HStack(spacing: 14) {
            countColumn(
                title: "Current",
                value: "\(vm.currentStreak) days",
                flameGradient: true
            )

            countColumn(
                title: "Best",
                value: "\(vm.bestStreak) days",
                flameGradient: false
            )
        }
    }

    @ViewBuilder
    func countColumn(title: LocalizedStringKey, value: LocalizedStringKey, flameGradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 7) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        flameGradient
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color(hex: "#FF731F"), Color(hex: "#FF2600")],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        : AnyShapeStyle(Color.white)
                    )

                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func weekdayLetter(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EE"
        var s = f.string(from: date)
        if s.count > 2 { s = String(s.prefix(2)) }
        return s
    }
}

// MARK: - My teacher
private extension ProfileView {

    var teacherCard: some View {
        NavigationLink {
            AssistenceSelectionView(
                user: vm.user,
                repository: UserRepository(context: context)
            )
            .navigationTransition(.zoom(sourceID: "profile_teacher", in: animation))
        } label: {
            HStack(spacing: 0) {
                teacherLeftText
                teacherPhoto
            }
            .frame(height: 132)
            .background(RoundedRectangle(cornerRadius: 23).fill(Color(hex: "#18181D")))
            .clipShape(RoundedRectangle(cornerRadius: 23))
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "profile_teacher", in: animation)
    }

    var teacherLeftText: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text("My teacher")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 0)

            Text(vm.teacher.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text(vm.teacherSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#9A9AA3"))

            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: index < vm.teacherHearts ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.lsPink)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var teacherPhoto: some View {
        Image(vm.teacher.backgroundImageName)
            .resizable()
            .scaledToFill()
            .frame(width: 158, height: 132)
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [Color(hex: "#18181D"), Color(hex: "#18181D").opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 94)
            }
            .clipped()
    }
}

// MARK: - Finished lessons
private extension ProfileView {

    var finishedLessonsCard: some View {
        // Плоская карточка без перехода — статистика видна инлайн.
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Text("Finished lessons")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Text("\(vm.unitsCompletedCount) units")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#31D64A"))
            }

            HStack(spacing: 10) {
                statBox(value: "\(vm.lessonsCount)", label: "profile.stat.lessons")
                statBox(value: "\(vm.averageScore)", label: "profile.stat.avg_score")
                statBox(value: vm.spokenTimeFormatted, label: "profile.stat.spoken")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 23).fill(Color(hex: "#18181D")))
    }

    @ViewBuilder
    func statBox(value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#232329")))
    }
}

// MARK: - Empty destination
private extension ProfileView {

    var emptyDestination: some View {
        Color(hex: "#0B0B0D")
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
    }
}

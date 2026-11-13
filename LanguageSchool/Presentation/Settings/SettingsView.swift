import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionService.self) private var premium
    @State private var vm: SettingsViewModel
    @Namespace private var animation
    @State private var showDeleteConfirm = false

    init(user: UserEntity, repository: UserRepository, context: ModelContext) {
        _vm = State(
            wrappedValue: SettingsViewModel(user: user, repository: repository, context: context)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
                .padding(.horizontal, 16)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    learningSection
                    voiceSection
                    accountSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
        }
        .background(Color(hex: "#0B0B0D").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await vm.deleteAccount()
                    dismiss()
                }
            }
        } message: {
            Text("This will remove your account and all local data. This action cannot be undone.")
        }
        .alert(
            "Couldn’t save change",
            isPresented: Binding(get: { vm.syncError != nil }, set: { if !$0 { vm.syncError = nil } })
        ) {
            Button("OK") { vm.syncError = nil }
        } message: {
            Text(vm.syncError ?? "")
        }
    }
}

// MARK: - Nav bar
private extension SettingsView {

    var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                    Text("Profile")
                        .font(.system(size: 17))
                }
                .foregroundStyle(.lsPink)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .overlay {
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 44)
    }
}

// MARK: - LEARNING
private extension SettingsView {

    var learningSection: some View {
        section(header: "LEARNING") {
            listCard {
                languageRow
                divider
                levelRow
                divider
                dailyGoalRow
                divider
                goalRow
            }
        }
    }

    var languageRow: some View {
        NavigationLink {
            ManageLanguageView(
                user: vm.user,
                repository: UserRepository(context: context),
                backTitle: "Settings"
            )
            .navigationTransition(.zoom(sourceID: "settings_language", in: animation))
        } label: {
            settingsRow(
                leading: LanguageFlagView(language: vm.currentLanguage).eraseToAnyView(),
                title: "Language",
                value: vm.currentLanguage.displayTitle,
                showChevron: true
            )
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "settings_language", in: animation)
    }

    var levelRow: some View {
        Menu {
            Picker("Level", selection: Binding(get: { vm.currentLevel }, set: { vm.currentLevel = $0 })) {
                ForEach(LangGrade.allCases) { grade in
                    Text(grade.grade).tag(grade)
                }
            }
        } label: {
            settingsRow(
                leading: nil,
                title: "Level",
                value: vm.currentLevel.grade,
                showChevron: true
            )
        }
    }

    var dailyGoalRow: some View {
        Menu {
            Picker("Daily goal", selection: Binding(get: { vm.dailyGoalMinutes }, set: { vm.dailyGoalMinutes = $0 })) {
                ForEach(vm.dailyGoalOptions, id: \.self) { minutes in
                    Text(vm.dailyGoalDisplay(for: minutes)).tag(minutes)
                }
            }
        } label: {
            settingsRow(
                leading: nil,
                title: "Daily goal",
                value: vm.dailyGoalDisplay,
                showChevron: true
            )
        }
    }

    var goalRow: some View {
        Menu {
            Picker("Your goal", selection: Binding(get: { vm.currentGoal }, set: { vm.currentGoal = $0 })) {
                ForEach(LearningGoal.allCases) { goal in
                    Text(goal.displayTitle).tag(goal)
                }
            }
        } label: {
            settingsRow(
                leading: nil,
                title: "Your goal",
                value: vm.currentGoal.displayTitle,
                showChevron: true
            )
        }
    }
}

// MARK: - VOICE AND PLAYBACK
private extension SettingsView {

    var voiceSection: some View {
        section(header: "VOICE AND PLAYBACK") {
            listCard {
                HStack(spacing: 11) {
                    Text("Autoplay her audio")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle("", isOn: Binding(
                        get: { vm.autoplayTeacherAudio },
                        set: { vm.autoplayTeacherAudio = $0 }
                    ))
                    .labelsHidden()
                    .tint(Color(hex: "#31D64A"))
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
            }
        }
    }
}

// MARK: - ACCOUNT
private extension SettingsView {

    var accountSection: some View {
        section(header: "ACCOUNT") {
            listCard {
                notificationsRow
                divider
                subscriptionRow
                divider
                restoreRow
                divider
                signOutRow
                divider
                deleteAccountRow
            }
        }
    }

    var notificationsRow: some View {
        NavigationLink {
            NotificationsView()
                .navigationTransition(.zoom(sourceID: "settings_notifications", in: animation))
        } label: {
            settingsRow(leading: nil, title: "Notifications", value: nil, showChevron: true)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "settings_notifications", in: animation)
    }

    var subscriptionRow: some View {
        Button {
            guard !vm.isPremium else { return }
            premium.showPaywall(.free_chat)
        } label: {
            settingsRow(leading: nil, title: "Subscription", value: vm.subscriptionLabel, showChevron: !vm.isPremium)
        }
        .buttonStyle(.plain)
    }

    var restoreRow: some View {
        Button {
            Task { await premium.restore() }
        } label: {
            settingsRow(leading: nil, title: "Restore purchases", value: nil, showChevron: true)
        }
        .buttonStyle(.plain)
    }

    var signOutRow: some View {
        Button {
            vm.signOut()
        } label: {
            HStack {
                Text("Sign out")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: "#FF4539"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var deleteAccountRow: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack {
                Text("Delete account")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: "#FF4539"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Building blocks
private extension SettingsView {

    @ViewBuilder
    func section<Content: View>(header: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .padding(.leading, 6)

            content()
        }
    }

    @ViewBuilder
    func listCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#18181D")))
    }

    var divider: some View {
        Rectangle()
            .fill(Color(hex: "#2E2E34"))
            .frame(height: 1)
            .padding(.leading, 14)
    }

    @ViewBuilder
    func settingsRow(leading: AnyView?, title: LocalizedStringKey, value: String?, showChevron: Bool) -> some View {
        HStack(spacing: 11) {
            if let leading {
                leading
            }
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let value {
                Text(value)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .lineLimit(1)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .contentShape(Rectangle())
    }

    var emptyDestination: some View {
        Color(hex: "#0B0B0D")
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Helper

private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}

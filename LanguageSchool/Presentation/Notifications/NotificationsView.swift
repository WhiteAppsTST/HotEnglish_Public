import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm = NotificationsViewModel()
    @State private var showTimePicker = false
    @State private var draftTime: Date = .now

    var body: some View {
        VStack(spacing: 0) {
            navBar
                .padding(.horizontal, 16)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    dailyReminderSection
                    fromEmmaSection
                    otherSection
                    footerText
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .background(Color(hex: "#0B0B0D").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showTimePicker) {
            timePickerSheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        }
    }
}

// MARK: - Nav bar
private extension NotificationsView {

    var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                    Text("Settings")
                        .font(.system(size: 17))
                }
                .foregroundStyle(.lsPink)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .overlay {
            Text("Notifications")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 44)
    }
}

// MARK: - DAILY REMINDER
private extension NotificationsView {

    var dailyReminderSection: some View {
        section(header: "DAILY REMINDER") {
            listCard {
                toggleRow(
                    title: "Remind me to practise",
                    subtitle: nil,
                    isOn: Binding(get: { vm.remindMeToPractise }, set: { vm.remindMeToPractise = $0 })
                )
                divider
                Button {
                    draftTime = vm.reminderTimeDate
                    showTimePicker = true
                } label: {
                    valueRow(title: "Time", value: vm.reminderTimeText)
                }
                .buttonStyle(.plain)
                .disabled(!vm.remindMeToPractise)
                .opacity(vm.remindMeToPractise ? 1 : 0.45)

                divider

                Menu {
                    Picker("Days", selection: Binding(get: { vm.reminderDays }, set: { vm.reminderDays = $0 })) {
                        ForEach(ReminderDays.allCases) { day in
                            Text(day.displayTitle).tag(day)
                        }
                    }
                } label: {
                    valueRow(title: "Days", value: vm.reminderDays.displayTitle)
                }
                .disabled(!vm.remindMeToPractise)
                .opacity(vm.remindMeToPractise ? 1 : 0.45)
            }
        }
    }
}

// MARK: - FROM EMMA
private extension NotificationsView {

    var fromEmmaSection: some View {
        section(header: "FROM EMMA") {
            listCard {
                toggleRow(
                    title: "Streak about to break",
                    subtitle: "Only if you haven't practised by 21:00",
                    isOn: Binding(get: { vm.streakAboutToBreak }, set: { vm.streakAboutToBreak = $0 })
                )
                divider
                toggleRow(
                    title: "New unit unlocked",
                    subtitle: nil,
                    isOn: Binding(get: { vm.newUnitUnlocked }, set: { vm.newUnitUnlocked = $0 })
                )
                divider
                toggleRow(
                    title: "Emma writes first",
                    subtitle: "A short message in your target language",
                    isOn: Binding(get: { vm.emmaWritesFirst }, set: { vm.emmaWritesFirst = $0 })
                )
            }
        }
    }
}

// MARK: - OTHER
private extension NotificationsView {

    var otherSection: some View {
        section(header: "OTHER") {
            listCard {
                toggleRow(
                    title: "Product news and offers",
                    subtitle: nil,
                    isOn: Binding(get: { vm.productNews }, set: { vm.productNews = $0 })
                )
            }
        }
    }
}

// MARK: - Footer
private extension NotificationsView {

    var footerText: some View {
        Text("You can turn everything off and the app still works — reminders are the only thing we send.")
            .font(.system(size: 12))
            .foregroundStyle(Color(hex: "#9A9AA3"))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}

// MARK: - Time picker sheet
private extension NotificationsView {

    var timePickerSheet: some View {
        VStack(spacing: 16) {
            Text("Reminder time")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 20)

            DatePicker("", selection: $draftTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)

            Button {
                vm.applyReminderDate(draftTime)
                showTimePicker = false
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(MainPinkBtnStyle())
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Building blocks
private extension NotificationsView {

    @ViewBuilder
    func section<Content: View>(header: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .padding(.leading, 4)

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
            .padding(.leading, 16)
    }

    @ViewBuilder
    func toggleRow(title: LocalizedStringKey, subtitle: LocalizedStringKey?, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#9A9AA3"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color(hex: "#31D64A"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    func valueRow(title: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "#9A9AA3"))
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#9A9AA3"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

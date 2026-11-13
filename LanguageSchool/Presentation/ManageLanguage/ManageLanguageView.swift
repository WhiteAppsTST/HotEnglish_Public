import SwiftUI
import SwiftData

struct ManageLanguageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ManageLanguageViewModel
    @AppStorage("app.uiLanguage") private var uiLanguage: String = "en"
    @Namespace private var animation

    /// Название родительского экрана в back-кнопке («Settings» / «Profile»).
    let backTitle: LocalizedStringKey

    init(user: UserEntity, repository: UserRepository, backTitle: LocalizedStringKey) {
        self.backTitle = backTitle
        _vm = State(wrappedValue: ManageLanguageViewModel(user: user, repository: repository))
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
                .padding(.horizontal, 16)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    languagesSection
                    translationsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }

            bottomBar
        }
        .background(Color(hex: "#0B0B0D").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Nav bar
private extension ManageLanguageView {

    var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                    Text(backTitle)
                        .font(.system(size: 17))
                }
                .foregroundStyle(.lsPink)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .overlay {
            Text("Language")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 44)
    }
}

// MARK: - Languages section
private extension ManageLanguageView {

    var languagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT YOU’RE LEARNING")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .padding(.leading, 6)

            VStack(spacing: 10) {
                ForEach(vm.languages) { row in
                    Button {
                        vm.select(row.language)
                    } label: {
                        languageCard(row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    func languageCard(_ row: ManageLanguageViewModel.LanguageRow) -> some View {
        let selected = vm.selectedLanguage == row.language

        VStack(spacing: 11) {
            HStack(alignment: .center, spacing: 12) {
                LanguageFlagView(language: row.language, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.language.displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(row.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#9A9AA3"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }

                selectionBadge(selected: selected)
            }

            progressRow(row)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.top, 14)
        .padding(.bottom, 15)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(selected ? Color(hex: "#FF2D7D").opacity(0.12) : Color(hex: "#18181D"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(selected ? Color.lsPink : .clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.18), value: selected)
    }

    @ViewBuilder
    func selectionBadge(selected: Bool) -> some View {
        if selected {
            Circle()
                .fill(Color.lsPink)
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
        } else {
            Circle()
                .stroke(Color(hex: "#37373C"), lineWidth: 1.5)
                .frame(width: 26, height: 26)
        }
    }

    @ViewBuilder
    func progressRow(_ row: ManageLanguageViewModel.LanguageRow) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                Capsule()
                    .fill(Color(hex: "#37373C"))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.lsPink)
                            .frame(width: max(0, geo.size.width * Double(row.progressPercent) / 100))
                    }
            }
            .frame(height: 6)

            Text("\(row.level.grade) · \(row.progressPercent)%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(row.hasProgress ? .lsPink : Color(hex: "#9A9AA3"))
        }
    }
}

// MARK: - Translations section
private extension ManageLanguageView {

    var translationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRANSLATIONS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .padding(.leading, 6)

            NavigationLink {
                TranslationPickerView()
                    .navigationTransition(.zoom(sourceID: "manage_translate", in: animation))
            } label: {
                HStack(spacing: 11) {
                    Text("Translate into")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text((LanguageCode(rawValue: uiLanguage) ?? .en).displayTitle)
                        .font(.system(size: 17))
                        .foregroundStyle(Color(hex: "#9A9AA3"))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#9A9AA3"))
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#18181D")))
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "manage_translate", in: animation)
        }
    }
}

// MARK: - Bottom bar
private extension ManageLanguageView {

    var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                guard vm.hasChange, !vm.isCommitting else { return }
                Task {
                    await vm.commit()
                    dismiss()
                }
            } label: {
                ZStack {
                    // Прячем текст пока крутится — так size pill не прыгает.
                    Text(vm.bottomButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(vm.hasChange ? .white : Color(hex: "#9A9AA3"))
                        .opacity(vm.isCommitting ? 0 : 1)
                    if vm.isCommitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule()
                        .fill(vm.hasChange ? Color.lsPink : Color(hex: "#37373C"))
                )
            }
            .buttonStyle(.plain)
            .disabled(!vm.hasChange || vm.isCommitting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.18), value: vm.hasChange)
        .animation(.easeInOut(duration: 0.18), value: vm.isCommitting)
    }
}

// MARK: - Empty destination
private extension ManageLanguageView {

    var emptyDestination: some View {
        Color(hex: "#0B0B0D")
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
    }
}

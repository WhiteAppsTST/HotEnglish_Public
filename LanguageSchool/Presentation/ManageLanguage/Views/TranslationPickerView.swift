import SwiftUI

/// Пикер языка интерфейса приложения. Хранится в `@AppStorage("app.uiLanguage")`
/// и прокидывается в `.environment(\.locale)` в `LanguageSchoolApp` —
/// смена на этом экране моментально перекатывает весь UI.
struct TranslationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app.uiLanguage") private var uiLanguage: String = "en"

    var body: some View {
        VStack(spacing: 0) {
            navBar
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    let langs: [LanguageCode] = [.en, .es]
                    ForEach(langs, id: \.self) { lang in
                        row(for: lang)
                        if lang != langs.last {
                            separator
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#18181D")))
                .padding(.horizontal, 16)
            }
        }
        .background(Color(hex: "#0B0B0D").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Nav bar
private extension TranslationPickerView {

    var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                    Text("Language")
                        .font(.system(size: 17))
                }
                .foregroundStyle(.lsPink)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .overlay {
            Text("Translate into")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 44)
    }
}

// MARK: - Rows
private extension TranslationPickerView {

    func row(for lang: LanguageCode) -> some View {
        Button {
            select(lang)
        } label: {
            HStack(spacing: 11) {
                LanguageFlagView(language: lang)

                Text(lang.displayTitle)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if uiLanguage == lang.rawValue {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.lsPink)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var separator: some View {
        Rectangle()
            .fill(Color(hex: "#2E2E34"))
            .frame(height: 1)
            .padding(.leading, 14)
    }

    func select(_ lang: LanguageCode) {
        guard uiLanguage != lang.rawValue else {
            dismiss()
            return
        }
        uiLanguage = lang.rawValue
        dismiss()
    }
}

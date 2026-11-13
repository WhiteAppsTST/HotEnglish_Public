import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

struct AuthGateView: View {
    @State private var auth = AuthService.shared
    @State private var showError: Bool = false
    @State private var devEmail: String = "ios@test.app"
    @State private var showDevSheet: Bool = false

    private var termsText: AttributedString {
        let raw = "By continuing you agree to our [Terms](\(AppConstants.K.termsURL)) and [Privacy Policy](\(AppConstants.K.privacyURL))."
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    var body: some View {
        VStack {
            VStack(alignment: .center, spacing: 16) {
                Text("Log in so I don't lose you.")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .multilineTextAlignment(.center)

                Text("Sign in to save your progress, streak\nand every chat with me.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA4"))
                    .padding(.horizontal, 26)
                    .multilineTextAlignment(.center)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await auth.handleApple(result: result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(Capsule())
                .padding(.horizontal)

                googleButton
                    .padding(.horizontal)

                #if DEBUG
                // Dev sign-in только под DEBUG-схемой. В Release кнопка
                // и её sheet не компилируются в бинарь.
                devButton
                    .padding(.horizontal)
                #endif

                Text(termsText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                    .tint(.white.opacity(0.75))
            }
            .padding(.vertical)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 32, topTrailing: 32),
                    style: .continuous
                )
                .fill(.ultraThinMaterial.opacity(0.7))
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(
            Image(.onboardingBG)
                .resizable()
                .ignoresSafeArea()
        )
        .overlay {
            if auth.isBusy {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(1.4)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isBusy)
        .onChange(of: auth.errorMessage) { _, new in
            showError = (new?.isEmpty == false)
        }
        .alert("Sign-in failed", isPresented: $showError) {
            Button("OK") { auth.errorMessage = nil }
        } message: {
            Text(auth.errorMessage ?? "")
        }
        .disabled(auth.isBusy)
        .sheet(isPresented: $showDevSheet) {
            devSignInSheet
                .presentationDetents([.height(220)])
        }
    }

    private var devButton: some View {
        Button {
            showDevSheet = true
        } label: {
            Text("Dev sign in (email)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    private var devSignInSheet: some View {
        VStack(spacing: 16) {
            Text("Dev sign-in")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 20)
            TextField("email", text: $devEmail)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.emailAddress)
                .padding(.horizontal)
            Button {
                showDevSheet = false
                Task { await auth.signInDev(email: devEmail) }
            } label: {
                Text("Sign in")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.lsPink))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#18181D"))
    }

    private var googleButton: some View {
        Button {
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 12) {
                Image(.googleGLogo)
                    .resizable()
                    .frame(width: 22, height: 22)

                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

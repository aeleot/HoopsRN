import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var mode: Mode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Mode {
        case signIn
        case signUp

        var title: String {
            switch self {
            case .signIn: "Welcome back"
            case .signUp: "Create your account"
            }
        }

        var actionLabel: String {
            switch self {
            case .signIn: "Sign In"
            case .signUp: "Sign Up"
            }
        }

        var switchPrompt: String {
            switch self {
            case .signIn: "Don't have an account?"
            case .signUp: "Already have an account?"
            }
        }

        var switchAction: String {
            switch self {
            case .signIn: "Sign up"
            case .signUp: "Sign in"
            }
        }

        var toggled: Mode {
            switch self {
            case .signIn: .signUp
            case .signUp: .signIn
            }
        }
    }

    private enum Field {
        case name
        case email
        case password
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespaces)
    }

    private var canSubmit: Bool {
        guard !authManager.isBusy else { return false }
        guard mode == .signIn || !trimmedDisplayName.isEmpty else { return false }

        return !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "basketball.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.hooprOrange)

                Text("HoopRN")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.black)

                Text(mode.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .padding(.bottom, 32)

            VStack(spacing: 12) {
                if mode == .signUp {
                    field(placeholder: "Name", text: $displayName, field: .name)
                        .transition(.opacity)
                }

                field(placeholder: "Email", text: $email, field: .email)

                field(placeholder: "Password", text: $password, field: .password)
            }

            if let errorMessage = authManager.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.hooprRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }

            Button {
                submit()
            } label: {
                ZStack {
                    if authManager.isBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(mode.actionLabel)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSubmit ? Color.hooprOrange : Color.hooprOrange.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSubmit)
            .padding(.top, 24)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    mode = mode.toggled
                }
                authManager.clearError()
            } label: {
                HStack(spacing: 4) {
                    Text(mode.switchPrompt)
                        .foregroundStyle(Color.hooprSecondaryText)
                    Text(mode.switchAction)
                        .foregroundStyle(Color.hooprOrange)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 14))
            }
            .padding(.top, 20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .onTapGesture {
            focusedField = nil
        }
    }

    @ViewBuilder
    private func field(
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        Group {
            switch field {
            case .name:
                TextField(placeholder, text: text)
                    .submitLabel(.next)
                    #if os(iOS) || os(visionOS)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    #endif

            case .email:
                TextField(placeholder, text: text)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    #if os(iOS) || os(visionOS)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif

            case .password:
                SecureField(placeholder, text: text)
                    .submitLabel(.go)
                    #if os(iOS) || os(visionOS)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    #endif
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(.black)
        .focused($focusedField, equals: field)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.hooprLightGray)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    focusedField == field ? Color.hooprOrange : Color.hooprBorderGray,
                    lineWidth: 1
                )
        )
        .onSubmit {
            switch field {
            case .name:
                focusedField = .email
            case .email:
                focusedField = .password
            case .password:
                submit()
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let name = trimmedDisplayName
        let currentMode = mode

        Task {
            switch currentMode {
            case .signIn:
                await authManager.signIn(email: trimmedEmail, password: password)
            case .signUp:
                await authManager.signUp(
                    email: trimmedEmail,
                    password: password,
                    displayName: name
                )
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

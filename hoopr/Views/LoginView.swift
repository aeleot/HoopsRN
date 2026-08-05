import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    @FocusState private var focusedField: Field?

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(authService: authService))
    }

    private enum Field {
        case email
        case password
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

                Text(viewModel.mode.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .padding(.bottom, 32)

            VStack(spacing: 12) {
                field(placeholder: "Email", text: $viewModel.email, field: .email, isSecure: false)
                field(placeholder: "Password", text: $viewModel.password, field: .password, isSecure: true)
            }

            if let errorMessage = viewModel.errorMessage {
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
                    if viewModel.isBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(viewModel.mode.actionLabel)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(viewModel.canSubmit ? Color.hooprOrange : Color.hooprOrange.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!viewModel.canSubmit)
            .padding(.top, 24)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.toggleMode()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.mode.switchPrompt)
                        .foregroundStyle(Color.hooprSecondaryText)
                    Text(viewModel.mode.switchAction)
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
        field: Field,
        isSecure: Bool
    ) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
                    .submitLabel(.go)
                    #if os(iOS) || os(visionOS)
                    .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                    #endif
            } else {
                TextField(placeholder, text: text)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    #if os(iOS) || os(visionOS)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
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
            case .email:
                focusedField = .password
            case .password:
                submit()
            }
        }
    }

    private func submit() {
        guard viewModel.canSubmit else { return }
        focusedField = nil
        Task { await viewModel.submit() }
    }
}

#Preview {
    LoginView(authService: AuthService())
}

import SwiftUI

/// Sign in and sign up — the one screen in the app with no data on it.
///
/// **Redesigned in UI revamp Phase 2b.** The brand keeps its place as the
/// screen's hero, and gains
/// the one fact a first-time user lacks: what the app is for
/// (`LoginBrandBand`). It becomes the same band every other screen opens on,
/// filling the top of the screen; the form sits under it at the bottom, where
/// a one-handed thumb is. When the keyboard comes up the band gives way first,
/// and at the largest text sizes the whole screen scrolls rather than
/// clipping.
///
/// **The form is on the page ground, not `hooprElevatedSurface`**, though the
/// redesign first drew it there. In dark mode the band *is* the elevated
/// surface's value, so a form on it would read as the band continuing. On the
/// page ground it separates from the band in both appearances, as every other
/// screen's content does.
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
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LoginBrandBand()
                        .frame(maxHeight: .infinity)

                    form
                }
                // At least the screen's height, so the band fills whatever the
                // form doesn't use; taller only when the text is too large to
                // fit, and then it scrolls.
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.hooprBackground)
        .onTapGesture {
            focusedField = nil
        }
    }

    // MARK: - The form

    /// Two fields and one button — the task — under a title that says which
    /// of the two it is, with the way to the other one quiet at the end.
    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(viewModel.mode.title)
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)
                // Wraps rather than truncating: the band above is the flexible
                // part, and at `.accessibility3` a squeezed title read "Create
                // your accou…" (render, 2026-09-23).
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            field(placeholder: "Email", text: $viewModel.email, field: .email, isSecure: false)
            field(placeholder: "Password", text: $viewModel.password, field: .password, isSecure: true)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            submitButton
                .padding(.top, Spacing.sm)

            modeSwitch
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.xl)
    }

    /// Filled when it can go, and a quiet fill with readable text when it
    /// can't (`unavailable`). It used to fade the orange to 40% under the same
    /// black label, which in dark mode left the label barely distinguishable
    /// from the button it was on.
    ///
    /// A `form` button: rounded like the two fields above it, not a capsule,
    /// so the form reads as one object (the user's call, 2026-09-24).
    private var submitButton: some View {
        Button {
            submit()
        } label: {
            if viewModel.isBusy {
                ProgressView()
            } else {
                Text(viewModel.mode.actionLabel)
            }
        }
        .buttonStyle(.hooprFilled(
            .large,
            role: viewModel.canSubmit ? .primary : .unavailable,
            shape: .form
        ))
        .disabled(!viewModel.canSubmit)
    }

    private var modeSwitch: some View {
        Button {
            withAnimation(.hooprSwap) {
                viewModel.toggleMode()
            }
        } label: {
            // One line when it fits, the prompt over the action when it
            // doesn't — at `.accessibility3` the side-by-side version wrapped
            // the prompt into a ragged column beside "Sign up" (render,
            // 2026-09-23).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    switchPrompt
                    switchAction
                }
                VStack(spacing: 2) {
                    switchPrompt
                    switchAction
                }
            }
            .hooprType(.body)
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var switchPrompt: some View {
        Text(viewModel.mode.switchPrompt)
            .foregroundStyle(Color.hooprSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var switchAction: some View {
        Text(viewModel.mode.switchAction)
            .foregroundStyle(Color.hooprBrandAccent)
            .fontWeight(.semibold)
    }

    /// **The unfocused edge is `hooprSeparatorStrong`, at 3:1.** It was the
    /// faint `hooprBorder` hairline around a `hooprFill` ground — 1.09:1 fill
    /// on white and 1.2:1 edge — so in light mode the two fields a new user
    /// has to find were barely drawn. `UI_SHELL.md` held that switch back for
    /// "the composition that wants it"; this is that composition.
    @ViewBuilder
    private func field(
        placeholder: String,
        text: Binding<String>,
        field: Field,
        isSecure: Bool
    ) -> some View {
        let isFocused = focusedField == field

        Group {
            if isSecure {
                SecureField(placeholder, text: text, prompt: .hooprPrompt(placeholder))
                    .submitLabel(.go)
                    #if os(iOS) || os(visionOS)
                    .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                    #endif
            } else {
                TextField(placeholder, text: text, prompt: .hooprPrompt(placeholder))
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    #if os(iOS) || os(visionOS)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        }
        .hooprFont(16, maximumSize: 24)
        .foregroundStyle(Color.hooprPrimaryText)
        .focused($focusedField, equals: field)
        .hooprFieldChrome(isFocused: isFocused)
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

/// The login screen's hero: the glyph, the name at `display`, and one line
/// saying what the app is for — the only screen where the product itself is
/// what needs explaining (assumption A1). Centred, because this band is the
/// whole of a screen with one task, not the top of a list.
///
/// Its own view, taking nothing, so it can be rendered without an
/// `AuthService` — and so Phase 4's `MeshGradient` had one place to land.
struct LoginBrandBand: View {
    /// What a first-time user doesn't know yet. Both halves are true today:
    /// the court dataset covers the Triangle, and Seasons ships.
    static let pitch = "Pickup basketball across the Triangle. Find a run tonight, or play a season with your squad."

    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer(minLength: Spacing.xxxl)

            Image(systemName: "basketball.fill")
                .hooprFont(44, maximumSize: 64)
                .foregroundStyle(Color.hooprBrandAccent)
                .accessibilityHidden(true)

            Text("hoopsRN")
                .hooprType(.display)
                .foregroundStyle(Color.hooprPrimaryText)
                .accessibilityAddTraits(.isHeader)

            Text(Self.pitch)
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Spacing.xxl)
        }
        .padding(.horizontal, Spacing.pageMargin)
        .frame(maxWidth: .infinity)
        // The brand orange rising from behind the glyph, at the band's own
        // luminance (UI revamp Phase 4, `HeroWash`): the one screen whose
        // hero is the product, drawn in the product's colour, with every
        // ratio the plain band had.
        .background(HeroWash(placement: .centred(.hooprBrandWash)))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hooprSeparatorStrong)
                .frame(height: 1)
        }
    }
}

#Preview {
    LoginView(authService: AuthService())
}

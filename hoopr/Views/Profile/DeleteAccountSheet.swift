import SwiftUI

/// Deletes the account — the one irreversible thing in the app, so the one
/// screen that makes you prove it twice: the password (which Firebase needs
/// anyway, and which means an unlocked phone isn't enough) and a typed word.
///
/// Says plainly what goes and what stays before it asks for anything, because
/// "delete my account" means different things to different people and the
/// answer here has consequences for others: a squad you lead is disbanded for
/// everyone on it.
///
/// There is no "deleted" state to show. When it works, the account is gone,
/// `AuthService` publishes `nil`, and the app is already back at the login
/// screen with this sheet torn down underneath it.
struct DeleteAccountSheet: View {
    @StateObject private var viewModel: DeleteAccountViewModel
    @FocusState private var focusedField: Field?

    private let onCancel: () -> Void

    private enum Field {
        case password
        case confirmation
    }

    init(viewModel: @autoclosure @escaping () -> DeleteAccountViewModel, onCancel: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    explanation

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SecureField("Password", text: $viewModel.password, prompt: .hooprPrompt("Password"))
                            .submitLabel(.next)
                            #if os(iOS) || os(visionOS)
                            .textContentType(.password)
                            #endif
                            .hooprFont(16, maximumSize: 24)
                            .foregroundStyle(Color.hooprPrimaryText)
                            .focused($focusedField, equals: .password)
                            .hooprFieldChrome(isFocused: focusedField == .password)
                            .onSubmit { focusedField = .confirmation }

                        TextField(
                            "Type \(AccountDeletionPlan.confirmationWord)",
                            text: $viewModel.confirmation,
                            prompt: .hooprPrompt("Type \(AccountDeletionPlan.confirmationWord) to confirm")
                        )
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        #if os(iOS) || os(visionOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .hooprFont(16, maximumSize: 24)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .focused($focusedField, equals: .confirmation)
                        .hooprFieldChrome(isFocused: focusedField == .confirmation)
                        .onSubmit { focusedField = nil }
                    }
                    .disabled(viewModel.isDeleting)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .hooprType(.caption)
                            .foregroundStyle(Color.hooprRed)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    deleteButton
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hooprBackground)
            .navigationTitle("Delete Account")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .disabled(viewModel.isDeleting)
                }
            }
        }
        // Mid-deletion is not a state to swipe away from: the steps are
        // resumable, but only from this sheet.
        .interactiveDismissDisabled(viewModel.isDeleting)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .hooprFont(22, maximumSize: 28)
                .foregroundStyle(Color.hooprRed)
                .accessibilityHidden(true)

            Text("This permanently deletes")
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)

            Text(viewModel.email ?? "your account")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)

            Text(Self.consequences(ledSquadNames: viewModel.ledSquadNames))
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What goes, what stays, and — when it applies — whose squad goes with
    /// it. One paragraph, in the order a person would ask.
    nonisolated static func consequences(ledSquadNames: [String]) -> String {
        var sentences = [
            "Your profile, friends, and squad invites are removed. Runs you host are called off, and you're taken off the runs you joined.",
        ]

        switch ledSquadNames.count {
        case 0:
            break
        case 1:
            sentences.append("\(ledSquadNames[0]) is disbanded for everyone on it, and its scheduled match is called off.")
        default:
            sentences.append("The squads you lead are disbanded for everyone on them, and their scheduled matches are called off.")
        }

        sentences.append("Finished matches and runs stay in other players' history without your name. This can't be undone.")
        return sentences.joined(separator: " ")
    }

    private var deleteButton: some View {
        Button {
            focusedField = nil
            Task { await viewModel.delete() }
        } label: {
            if viewModel.isDeleting {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    if let progress = viewModel.progress {
                        Text(progress)
                    }
                }
            } else {
                Text("Delete Account")
            }
        }
        .buttonStyle(.hooprFilled(
            .large,
            role: viewModel.canDelete ? .destructive : .unavailable,
            shape: .form
        ))
        .disabled(!viewModel.canDelete)
    }
}

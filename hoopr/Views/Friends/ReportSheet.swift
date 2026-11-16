import SwiftUI

/// Flags a player or a squad for review (App Review Guideline 1.2).
///
/// A reason is required and a note is optional: the reason is what lets a
/// report be triaged at a glance in the console, and demanding an essay is how
/// people decide not to report at all.
///
/// Says what happens next, because nothing visible does — the report goes to
/// the people who run hoopsRN and the reported player is never told. Blocking
/// is offered from the profile, not from here: reporting is about the app,
/// blocking is about you, and bundling them makes a report feel like a bigger
/// step than it is.
struct ReportSheet: View {
    @StateObject private var viewModel: ReportViewModel
    @FocusState private var isDetailsFocused: Bool

    private let onDismiss: () -> Void

    init(viewModel: ReportViewModel, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if viewModel.didSubmit {
                        confirmation
                    } else {
                        form
                    }
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hooprBackground)
            .navigationTitle("Report")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !viewModel.didSubmit {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onDismiss)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .disabled(viewModel.isSubmitting)
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
    }

    // MARK: - Form

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Report \(viewModel.targetName)")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Reports go to the hoopsRN team. \(viewModel.targetName) won't be told who sent it.")
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }

        DividedRows {
            ForEach(viewModel.reasons) { reason in
                reasonRow(reason)
            }
        }
        .disabled(viewModel.isSubmitting)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            TextField(
                "Anything else we should know?",
                text: $viewModel.details,
                prompt: .hooprPrompt("Anything else we should know? (optional)"),
                axis: .vertical
            )
            .lineLimit(3...6)
            .hooprFont(16, maximumSize: 24)
            .foregroundStyle(Color.hooprPrimaryText)
            .focused($isDetailsFocused)
            .hooprFieldChrome(isFocused: isDetailsFocused)
            .disabled(viewModel.isSubmitting)

            if let hint = viewModel.detailsHint {
                message(hint)
            }
        }

        if let errorMessage = viewModel.errorMessage {
            message(errorMessage)
        }

        Button {
            isDetailsFocused = false
            Task { await viewModel.submit() }
        } label: {
            if viewModel.isSubmitting {
                ProgressView()
            } else {
                Text("Send Report")
            }
        }
        .buttonStyle(.hooprFilled(
            .large,
            role: viewModel.canSubmit ? .primary : .unavailable,
            shape: .form
        ))
        .disabled(!viewModel.canSubmit)
    }

    private func reasonRow(_ reason: Report.Reason) -> some View {
        let isSelected = viewModel.reason == reason

        return Button {
            viewModel.reason = reason
        } label: {
            HStack(spacing: Spacing.md) {
                Text(reason.title)
                    .hooprType(.subhead)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Spacing.sm)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .hooprFont(20, maximumSize: 26)
                    .foregroundStyle(isSelected ? Color.hooprBrandAccent : Color.hooprSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .hooprType(.caption)
            .foregroundStyle(Color.hooprRed)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sent

    @ViewBuilder
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .hooprFont(28, maximumSize: 34)
                .foregroundStyle(Color.hooprBrandAccent)
                .accessibilityHidden(true)

            Text("Report sent")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("Thanks. We review every report and act on the ones that break the rules. If you don't want to hear from this player again, you can also block them from their profile.")
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button("Done", action: onDismiss)
            .buttonStyle(.hooprFilled(.large, shape: .form))
    }
}

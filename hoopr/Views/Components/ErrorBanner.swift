import SwiftUI

/// The soft red panel an error surfaces in, wherever it surfaces.
///
/// The Local Runs tab and the profile screen each had their own copy of this —
/// same triangle, same 8% red wash, same corner radius — and the profile's
/// version carried a comment saying so. An error should look the same in both
/// places by construction, not by two views happening to agree.
///
/// Both controls are optional, and a `nil` closure omits the control entirely
/// rather than disabling it — the same convention `ProfileCard` uses for
/// `onEdit`. Outer padding is deliberately left to the caller: the two screens
/// inset their content differently, and that's a property of the screen rather
/// than of the banner.
struct ErrorBanner: View {
    let message: String

    /// Adds a "Reconnecting… / Try again" row. Pass `nil` when there's nothing
    /// to retry — an action that failed is retried by repeating the action, not
    /// from here.
    var onRetry: (() -> Void)?

    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .hooprFont(13)

            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let onRetry {
                    HStack(spacing: 8) {
                        Text("Reconnecting…")
                            .foregroundStyle(Color.hooprSecondaryText)

                        Button("Try again", action: onRetry)
                            .buttonStyle(.plain)
                            .fontWeight(.semibold)
                    }
                }
            }
            .hooprFont(13)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .hooprFont(12, weight: .semibold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .foregroundStyle(Color.hooprRed)
        .padding(12)
        .background(Color.hooprRed.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorBanner(message: FailureText.network)

        ErrorBanner(
            message: FailureText.rulesNotDeployed(loading: "runs"),
            onRetry: {},
            onDismiss: {}
        )
    }
    .padding(16)
    .background(Color.hooprBackground)
}

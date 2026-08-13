import SwiftUI

/// The "Start Run" form, opened from a court's detail card on the map tab.
///
/// Collects the four things a host decides. The court is fixed by where the
/// form was opened from, so it's shown as context rather than as a field —
/// changing it here would mean re-picking a court you just tapped.
struct CreateGameSheet: View {
    @StateObject private var viewModel: CreateGameViewModel
    let onCreated: () -> Void
    let onCancel: () -> Void

    init(
        court: Court,
        gameService: GameService,
        onCreated: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CreateGameViewModel(
            court: court,
            gameService: gameService
        ))
        self.onCreated = onCreated
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    courtSummary
                    whenCard
                    visibilityCard
                    playersCard

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .hooprFont(13)
                            .foregroundStyle(Color.hooprRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .background(Color.hooprBackground)
            // The whole cycle is gated on `isSaving`, matching the profile
            // sheets: nothing can move out from under an in-flight write.
            .disabled(viewModel.isSaving)
            .navigationTitle("Start a Run")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task {
                                if await viewModel.create() { onCreated() }
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            viewModel.canSave ? Color.hooprOrange : Color.hooprSecondaryText
                        )
                        .disabled(!viewModel.canSave)
                    }
                }
            }
        }
    }

    // MARK: - Cards

    private var courtSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "basketball.fill")
                .hooprFont(22)
                .foregroundStyle(Color.hooprOrange)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.court.name)
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .multilineTextAlignment(.leading)

                Text(viewModel.court.address.isEmpty
                     ? viewModel.court.city
                     : viewModel.court.address)
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hooprFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var whenCard: some View {
        card(title: "When") {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker(
                    "Tip-off",
                    selection: $viewModel.scheduledTime,
                    in: viewModel.scheduleRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Color.hooprOrange)
                .frame(maxWidth: .infinity, alignment: .leading)

                // A form left open long enough for its own tip-off to pass
                // would otherwise leave Create disabled with no explanation.
                if let hint = viewModel.validationHint, !viewModel.isSaving {
                    Text(hint)
                        .hooprFont(12)
                        .foregroundStyle(Color.hooprRed)
                }
            }
        }
    }

    private var visibilityCard: some View {
        card(title: "Who can join") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    visibilityOption(title: "Public", symbol: "globe", isPublic: true)
                    visibilityOption(title: "Invite only", symbol: "lock.fill", isPublic: false)
                }

                Text(viewModel.visibilityCaption)
                    .hooprFont(12)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private func visibilityOption(title: String, symbol: String, isPublic: Bool) -> some View {
        let isSelected = viewModel.isPublic == isPublic

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.isPublic = isPublic
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .hooprFont(12, weight: .semibold, maximumSize: 16)
                Text(title)
                    // Capped: the pill's height is fixed below, and two of
                    // these sit side by side across the sheet's width.
                    .hooprFont(14, weight: .semibold, maximumSize: 18)
            }
            .foregroundStyle(isSelected ? Color.hooprOnBrand : Color.hooprSecondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isSelected ? Color.hooprOrange : Color.hooprSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : Color.hooprBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var playersCard: some View {
        card(title: "Players") {
            HStack(spacing: 16) {
                stepperButton(symbol: "minus", enabled: viewModel.canDecreasePlayers, delta: -1)

                VStack(spacing: 2) {
                    Text("\(viewModel.maxPlayers)")
                        .hooprFont(28, weight: .bold)
                        .foregroundStyle(Color.hooprPrimaryText)
                        // Fixed-width digits so the row doesn't shift as the
                        // number changes width.
                        .monospacedDigit()

                    Text(viewModel.formatText ?? "max")
                        .hooprFont(12)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
                .frame(maxWidth: .infinity)

                stepperButton(symbol: "plus", enabled: viewModel.canIncreasePlayers, delta: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Maximum players")
            .accessibilityValue("\(viewModel.maxPlayers)")
        }
    }

    private func stepperButton(symbol: String, enabled: Bool, delta: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                viewModel.adjustPlayers(by: delta)
            }
        } label: {
            Image(systemName: symbol)
                // Capped to the fixed 44pt hit target it's centred in.
                .hooprFont(16, weight: .bold, maximumSize: 22)
                .foregroundStyle(enabled ? Color.hooprOrange : Color.hooprSecondaryText.opacity(0.4))
                .frame(width: 44, height: 44)
                .background(Color.hooprSurface)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.hooprBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(delta > 0 ? "Add a player" : "Remove a player")
    }

    private func card<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .hooprFont(13, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .textCase(.uppercase)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hooprFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

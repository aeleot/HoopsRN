import SwiftUI

/// The "Start Run" form, opened from a court's detail card on the map tab.
///
/// Collects the four things a host decides. The court is fixed by where the
/// form was opened from, so it's shown as context rather than as a field —
/// changing it here would mean re-picking a court you just tapped.
///
/// **Grouped panels, one row grammar (2026-09-23).** The Phase 2b version was
/// one form on one surface — the tip-off as a large numeral, two outlined
/// pills, a stepper with its own layout, a caption under each — and the user
/// found it "not very structured", with "more text and not a lot of icons".
/// Every section spoke a different visual language. Now the sheet is an iOS
/// inset-grouped form on `hooprGroupedBackground`: three `FormPanel`s (when;
/// how many; who can join), and every row in them is the same thing — an
/// accent glyph in one column, a title, and the value or control at the
/// trailing edge. The captions shrank to one short line under each visibility
/// option, and the icons carry the rest.
///
/// **Day and time are two rows, each opening its own picker in place.** The
/// day is a strip of chips (Today, Thu 24, …) covering the whole window the
/// rules allow; the time is a wheel. One is open at a time and neither is by
/// default, so the three-tap path — Start Run, Create, done — doesn't rise.
///
/// **The invite step tells the truth** (brief §5.11, a correctness fix): the
/// link opens nothing and an invite-only run holds only its host
/// (`gaps/GAMES.md`), so the step leads with the court and time to send, via
/// the system share sheet, and keeps the link below as a labelled reference.
struct CreateGameSheet: View {
    @StateObject private var viewModel: CreateGameViewModel
    let onCreated: () -> Void
    let onCancel: () -> Void
    /// The run was written — public or invite-only, at the moment the server
    /// accepted it, which for an invite-only run is before its Done. For the
    /// presenter's haptic: it outlives the sheet, which a public run dismisses
    /// in the same update.
    let onConfirmed: () -> Void

    /// Which picker is open, if either.
    @State private var openEditor: Editor?

    private enum Editor {
        case day
        case time
    }

    init(
        court: Court,
        gameService: GameService,
        onCreated: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onConfirmed: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: CreateGameViewModel(
            court: court,
            gameService: gameService
        ))
        self.onCreated = onCreated
        self.onCancel = onCancel
        self.onConfirmed = onConfirmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if let inviteLink = viewModel.inviteLink {
                        inviteStep(link: inviteLink)
                            .transition(.hooprLift)
                    } else {
                        Group {
                            courtHeading
                            whenPanel
                            playersPanel
                            visibilityPanel
                        }
                        .transition(.opacity)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        problem(errorMessage)
                    }
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The form giving way to the invite step: the run exists now,
                // and the step lifts in over the form it replaces.
                .animation(.hooprSwap, value: viewModel.inviteLink != nil)
            }
            .background(Color.hooprGroupedBackground)
            // The whole cycle is gated on `isSaving`, matching the profile
            // sheets: nothing can move out from under an in-flight write.
            .disabled(viewModel.isSaving)
            .navigationTitle(viewModel.inviteLink == nil ? "Start a Run" : "Run Created")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // The run already exists by the time the invite step shows, so
                // there is nothing left to cancel — offering it would read as
                // "discard the run".
                if viewModel.inviteLink == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .disabled(viewModel.isSaving)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else if viewModel.inviteLink != nil {
                        Button("Done", action: onCreated)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.hooprBrandAccent)
                    } else {
                        Button("Create") {
                            Task {
                                // A private run stays open on its invite step
                                // instead of dismissing — `inviteLink` is set
                                // by the time `create()` returns.
                                guard await viewModel.create() else { return }
                                onConfirmed()
                                if viewModel.inviteLink == nil {
                                    onCreated()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            viewModel.canSave ? Color.hooprBrandAccent : Color.hooprSecondaryText
                        )
                        .disabled(!viewModel.canSave)
                    }
                }
            }
        }
    }

    // MARK: - The court

    /// The form's heading: which court, set as the map card and Home's band
    /// set it so it's recognisably the one just tapped, over where it is.
    private var courtHeading: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            CourtTitle(name: viewModel.court.displayName, isHeader: true)

            if !place.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .hooprType(.caption)
                        .accessibilityHidden(true)
                    Text(place)
                        .hooprType(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.hooprSecondaryText)
            }
        }
    }

    private var place: String {
        viewModel.court.address.isEmpty ? viewModel.court.city : viewModel.court.address
    }

    // MARK: - When

    private var whenPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FormPanel {
                pickerRow(.day, symbol: "calendar", title: "Day", value: viewModel.tipOffDayText)

                if openEditor == .day {
                    dayStrip
                }

                pickerRow(.time, symbol: "clock.fill", title: "Tip-off", value: viewModel.tipOffTimeText)

                if openEditor == .time {
                    DatePicker(
                        "Tip-off",
                        selection: $viewModel.scheduledTime,
                        in: viewModel.scheduleRange,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                }
            }

            // A form left open long enough for its own tip-off to pass would
            // otherwise leave Create disabled with no explanation.
            if let hint = viewModel.validationHint, !viewModel.isSaving {
                problem(hint)
                    .padding(.horizontal, FormRowMetrics.horizontalPadding)
            }
        }
    }

    /// A row whose value opens a picker under it. The value turns to the
    /// accent while its picker is open, and the chevron turns over.
    private func pickerRow(_ editor: Editor, symbol: String, title: String, value: String) -> some View {
        let isOpen = openEditor == editor

        return Button {
            withAnimation(.hooprSpring) {
                openEditor = isOpen ? nil : editor
            }
        } label: {
            FormRow(glyph: FormRowGlyph(systemName: symbol)) {
                Text(title)
                    .hooprType(.subhead)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(1)
            } trailing: {
                HStack(spacing: 6) {
                    Text(value)
                        .hooprType(.subhead)
                        .foregroundStyle(isOpen ? Color.hooprBrandAccent : Color.hooprSecondaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .hooprFont(13, weight: .semibold, maximumSize: 17)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(isOpen ? "Closes the picker" : "Opens the picker")
    }

    /// Every day the rules allow, as chips, scrolled to the one picked.
    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(viewModel.dayOptions, id: \.self) { day in
                        dayChip(day)
                            .id(day)
                    }
                }
                .padding(.horizontal, FormRowMetrics.horizontalPadding)
                .padding(.vertical, Spacing.md)
            }
            .onAppear {
                if let picked = viewModel.dayOptions.first(where: viewModel.isSelectedDay) {
                    proxy.scrollTo(picked, anchor: .center)
                }
            }
        }
        .transition(.opacity)
    }

    private func dayChip(_ day: Date) -> some View {
        let text = CreateGameViewModel.dayChipText(for: day)
        let isSelected = viewModel.isSelectedDay(day)

        return Button {
            withAnimation(.hooprSnap) {
                viewModel.selectDay(day)
            }
        } label: {
            VStack(spacing: 2) {
                Text(text.weekday)
                    .hooprType(.label)
                    .foregroundStyle(isSelected ? Color.hooprOnBrand : Color.hooprSecondaryText)
                Text(text.number)
                    .hooprType(.headline)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.hooprOnBrand : Color.hooprPrimaryText)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.sm)
            // Wide enough for "TODAY", so every chip in the strip matches it.
            .frame(minWidth: 64, minHeight: 56)
            .background(
                isSelected ? Color.hooprOrange : Color.hooprFill,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.hooprPress)
        .accessibilityLabel(text.spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Players

    /// The cap, with the format it makes ("5-on-5") under the title, and a
    /// compact − n + at the trailing edge. VoiceOver gets one adjustable
    /// element rather than two buttons and a number.
    private var playersPanel: some View {
        FormPanel {
            FormRow(glyph: FormRowGlyph(systemName: "person.3.fill")) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Players")
                        .hooprType(.subhead)
                        .foregroundStyle(Color.hooprPrimaryText)
                    if let format = viewModel.formatText {
                        Text(format)
                            .hooprType(.caption)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                }
                .lineLimit(1)
            } trailing: {
                HStack(spacing: Spacing.xs) {
                    stepperButton(symbol: "minus", enabled: viewModel.canDecreasePlayers, delta: -1)

                    Text("\(viewModel.maxPlayers)")
                        .hooprType(.headline)
                        .monospacedDigit()
                        .foregroundStyle(Color.hooprPrimaryText)
                        .hooprNumericTransition(viewModel.maxPlayers)
                        .frame(minWidth: 32)

                    stepperButton(symbol: "plus", enabled: viewModel.canIncreasePlayers, delta: 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Players")
            .accessibilityValue(spokenPlayers)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: viewModel.adjustPlayers(by: 1)
                case .decrement: viewModel.adjustPlayers(by: -1)
                @unknown default: break
                }
            }
        }
    }

    private var spokenPlayers: String {
        let count = "\(viewModel.maxPlayers) players"
        return viewModel.formatText.map { "\(count), \($0.replacingOccurrences(of: "-", with: " "))" } ?? count
    }

    /// A 36pt disc in a 44pt target.
    private func stepperButton(symbol: String, enabled: Bool, delta: Int) -> some View {
        Button {
            viewModel.adjustPlayers(by: delta)
        } label: {
            Image(systemName: symbol)
                // Capped to the fixed disc it's centred in.
                .hooprFont(14, weight: .bold, maximumSize: 19)
                .foregroundStyle(enabled ? Color.hooprBrandAccent : Color.hooprSecondaryText)
                .frame(width: 36, height: 36)
                .background(Color.hooprFill, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.hooprPress)
        .disabled(!enabled)
        .accessibilityLabel(delta > 0 ? "Add a player" : "Remove a player")
    }

    // MARK: - Who can join

    private var visibilityPanel: some View {
        FormPanel {
            visibilityOption(isPublic: true, symbol: "globe", title: "Public")
            visibilityOption(isPublic: false, symbol: "lock.fill", title: "Invite only")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Who can join")
    }

    /// One option, as a row: its glyph, its name over one line saying what it
    /// does, and a radio mark. The unselected ring is `hooprSeparatorStrong`,
    /// which clears 3:1 on the panel.
    private func visibilityOption(isPublic: Bool, symbol: String, title: String) -> some View {
        let isSelected = viewModel.isPublic == isPublic

        return Button {
            withAnimation(.hooprSnap) {
                viewModel.isPublic = isPublic
            }
        } label: {
            HStack(alignment: .center, spacing: FormRowMetrics.glyphGap) {
                FormRowGlyph(systemName: symbol)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .hooprType(.subhead)
                        .foregroundStyle(Color.hooprPrimaryText)
                    Text(CreateGameViewModel.visibilityCaption(isPublic: isPublic))
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.sm)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .hooprFont(22, maximumSize: 28)
                    .foregroundStyle(isSelected ? Color.hooprBrandAccent : Color.hooprSeparatorStrong)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, FormRowMetrics.horizontalPadding)
            .padding(.vertical, FormRowMetrics.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: FormRowMetrics.minimumHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - After an invite-only run is created

    /// Leads with what works: the court and the time, to send through the
    /// share sheet. The link follows in the same panel as a reference. Its
    /// own "doesn't work yet" note is off here and only here, because the
    /// line under the title has just said it; on the run's card, where
    /// nothing else does, `InviteLinkCard` keeps it.
    private func inviteStep(link: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .hooprFont(40, maximumSize: 56)
                    .foregroundStyle(Color.hooprBrandAccent)
                    .accessibilityHidden(true)

                Text("Your run is set")
                    .hooprType(.title)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Invites don't work yet, so send your players the court and time.")
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FormPanel {
                FormRow(glyph: FormRowGlyph(.court, isLandscape: true)) {
                    summary(viewModel.court.displayName, detail: place)
                }
                .accessibilityElement(children: .combine)

                FormRow(glyph: FormRowGlyph(systemName: "clock.fill")) {
                    summary("\(viewModel.tipOffDayText) at \(viewModel.tipOffTimeText)", detail: nil)
                }
                .accessibilityElement(children: .combine)

                InviteLinkCard(link: link, showsUnopenableNote: false)
                    .padding(.horizontal, FormRowMetrics.horizontalPadding)
                    .padding(.vertical, FormRowMetrics.verticalPadding)
            }

            ShareLink(item: viewModel.shareText) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "square.and.arrow.up")
                        .hooprFont(15, weight: .semibold, maximumSize: 22)
                    Text("Send the court and time")
                        .hooprType(.body)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.hooprOnBrand)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(Color.hooprOrange))
                .contentShape(Capsule())
            }
            .buttonStyle(.hooprPress)
        }
    }

    private func summary(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .hooprType(.subhead)
                .foregroundStyle(Color.hooprPrimaryText)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Problems

    /// A validation hint or a failed write: red, marked, and one line where
    /// it fits.
    private func problem(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .hooprType(.caption)
                .accessibilityHidden(true)
            Text(message)
                .hooprType(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.hooprRed)
    }
}

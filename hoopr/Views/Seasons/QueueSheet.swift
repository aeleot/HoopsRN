import SwiftUI

/// Screen 4 — putting a squad in the queue.
///
/// **Two taps in the common case**, which is the whole design brief for this
/// sheet: a time chip is preselected to "Tonight" and the three nearest courts
/// are already ticked, so a leader who wants the obvious thing taps Save.
/// Everything else is there for the leader who wants something else.
///
/// The Save button and the inline hint both read `MatchTicket.validate`, the way
/// `CreateGameSheet` reads `Game.validate` — one function, mirroring the create
/// rule condition for condition, so the button is never enabled for a write the
/// server would refuse.
struct QueueSheet: View {
    @ObservedObject private var viewModel: MatchmakingViewModel

    private let squad: Squad
    private let onDismiss: () -> Void

    @State private var window: QueueWindow = .tonight
    @State private var selectedCourtIds: Set<String> = []
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var isSaving = false
    @State private var saveError: String?

    /// Re-evaluated on every render rather than held: "Tonight" stops being
    /// offerable at 9pm, and a sheet open across that boundary should notice.
    private var now: Date { Date() }

    init(viewModel: MatchmakingViewModel, squad: Squad, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.squad = squad
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    windowSection
                    if window == .custom { customWindowSection }
                    courtsSection

                    if let hint {
                        Text(hint)
                            .hooprFont(13)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let saveError {
                        Text(saveError)
                            .hooprFont(13)
                            .foregroundStyle(Color.hooprRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .background(Color.hooprBackground)
            .navigationTitle("Find a match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Queue up")
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .onAppear(perform: primeDefaults)
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                SquadCrest(squad: squad, size: SquadCrest.Size.card)

                VStack(alignment: .leading, spacing: 2) {
                    Text(squad.name)
                        .hooprFont(17, weight: .semibold)
                        .foregroundStyle(Color.hooprPrimaryText)

                    Text("\(squad.format.displayName) · \(squad.region)")
                        .hooprFont(13)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }

            Text("We'll look for another squad who can play one of your courts inside your window.")
                .hooprFont(14)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
    }

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("When")

            // Three chips fit in a row at ordinary text sizes and stop fitting
            // well before `.accessibility3`, where an `HStack` squeezes each
            // into a third of the width and the words break mid-character —
            // "Tomorrow evening" became four broken lines in a tall ellipse.
            // `ViewThatFits` takes the row while it fits and the column when it
            // doesn't, which is the reflow `Typography` asks for instead of a
            // `minimumScaleFactor`.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { windowChips }
                VStack(alignment: .leading, spacing: 8) { windowChips }
            }
        }
    }

    @ViewBuilder
    private var windowChips: some View {
        ForEach(QueueWindow.allCases) { option in
            chip(
                option.title,
                isSelected: window == option,
                // A chip whose window no longer holds a game disables
                // itself rather than offering something the rules would
                // refuse — "Tonight" at half past nine.
                isEnabled: option == .custom
                    || option.window(format: squad.format, now: now) != nil
            ) {
                window = option
            }
        }
    }

    private var customWindowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("From", selection: $customStart, in: now...)
                .hooprFont(15)
            DatePicker("Until", selection: $customEnd, in: customStart...)
                .hooprFont(15)
        }
        .padding(16)
        .cardChrome()
    }

    private var courtsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Where")
                Spacer()
                Text("\(selectedCourtIds.count) of \(MatchTicket.courtCountRange.upperBound)")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            VStack(spacing: 0) {
                if offeredCourtIds.isEmpty {
                    // The bundled dataset loads synchronously and holds 214
                    // courts, so an empty list means it failed to load rather
                    // than that nothing is nearby. A sentence, because an empty
                    // card under a "Where" heading reads as a broken screen.
                    Text("No courts loaded, so there's nowhere to offer. Reopen the app and try again.")
                        .hooprFont(13)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    ForEach(offeredCourtIds, id: \.self) { courtId in
                        courtRow(courtId)
                        if courtId != offeredCourtIds.last {
                            Divider().overlay(Color.hooprBorder)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .cardChrome()

            if !offeredCourtIds.isEmpty {
                Text("Ordered by preference — the first court you both accept is where you'll play.")
                    .hooprFont(12)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func courtRow(_ courtId: String) -> some View {
        Button {
            toggle(courtId)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedCourtIds.contains(courtId) ? "checkmark.circle.fill" : "circle")
                    .hooprFont(20)
                    .foregroundStyle(
                        selectedCourtIds.contains(courtId)
                            ? Color.hooprOrange
                            : Color.hooprSecondaryText
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.courtName(id: courtId))
                        .hooprFont(15, weight: .medium)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .multilineTextAlignment(.leading)

                    if let court = viewModel.court(id: courtId) {
                        Text(court.city)
                            .hooprFont(12)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedCourtIds.contains(courtId) ? [.isSelected] : [])
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .hooprFont(13, weight: .semibold)
            .foregroundStyle(Color.hooprSecondaryText)
            .textCase(.uppercase)
    }

    private func chip(
        _ title: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .hooprFont(14, weight: .medium)
                .foregroundStyle(
                    isSelected ? Color.hooprOnBrand
                        : isEnabled ? Color.hooprPrimaryText : Color.hooprSecondaryText
                )
                // One line at its natural width, so `ViewThatFits` measures the
                // chip the reader would actually get rather than a squeezed
                // one — without this the row "fits" by breaking words.
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.hooprOrange : Color.hooprSurface)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    // MARK: - State

    /// The courts a leader picks from: the nearest handful, plus anything
    /// already selected so a choice can't vanish when the list is recomputed.
    private var offeredCourtIds: [String] {
        let nearest = viewModel.nearestCourtIds(limit: 8)
        let extras = selectedCourtIds.subtracting(nearest)
        return nearest + extras.sorted()
    }

    private func primeDefaults() {
        guard selectedCourtIds.isEmpty else { return }

        selectedCourtIds = Set(viewModel.nearestCourtIds())

        if let tonight = QueueWindow.tonight.window(format: squad.format, now: now) {
            customStart = tonight.start
            customEnd = tonight.end
        } else {
            window = .tomorrowEvening
            let fallback = QueueWindow.tomorrowEvening.window(format: squad.format, now: now)
            customStart = fallback?.start ?? now.addingTimeInterval(3600)
            customEnd = fallback?.end ?? now.addingTimeInterval(3600 + squad.format.duration)
        }
    }

    private func toggle(_ courtId: String) {
        if selectedCourtIds.contains(courtId) {
            selectedCourtIds.remove(courtId)
        } else {
            guard selectedCourtIds.count < MatchTicket.courtCountRange.upperBound else { return }
            selectedCourtIds.insert(courtId)
        }
    }

    private var resolvedWindow: (start: Date, end: Date)? {
        window == .custom
            ? (customStart, customEnd)
            : window.window(format: squad.format, now: now)
    }

    /// The single source of truth for both the button and the hint below it —
    /// the same function the create rule mirrors.
    private var validationError: MatchTicketError? {
        guard let resolvedWindow else { return .invalidWindow }

        return MatchTicket.validate(
            courtIds: orderedSelection,
            windowStart: resolvedWindow.start,
            windowEnd: resolvedWindow.end,
            expiresAt: QueueWindow.expiry(forWindowEnd: resolvedWindow.end, now: now),
            format: squad.format,
            now: now
        )
    }

    /// Preference order is the order the courts are offered in — nearest first —
    /// which is what makes "the first court you both accept" mean something.
    private var orderedSelection: [String] {
        offeredCourtIds.filter { selectedCourtIds.contains($0) }
    }

    private var canSave: Bool { validationError == nil }

    private var hint: String? {
        guard let validationError else { return nil }
        return MatchmakingService.message(
            for: validationError,
            whileDoing: "queueing up",
            context: .write
        )
    }

    private func save() async {
        guard let resolvedWindow else { return }

        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            try await viewModel.queue(
                courtIds: orderedSelection,
                windowStart: resolvedWindow.start,
                windowEnd: resolvedWindow.end,
                expiresAt: QueueWindow.expiry(forWindowEnd: resolvedWindow.end, now: now)
            )
            onDismiss()
        } catch let error as MatchTicketError {
            saveError = MatchmakingService.message(
                for: error,
                whileDoing: "queueing up",
                context: .write
            )
        } catch {
            saveError = "Something went wrong while queueing up."
        }
    }
}

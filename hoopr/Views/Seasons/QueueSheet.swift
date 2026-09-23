import SwiftUI

/// Which day a squad wants to play. Not a model type — `QueueWindow` still
/// owns the actual preset windows and `expiry(forWindowEnd:)`, both still
/// unit-tested against `.tonight`/`.tomorrowEvening`. This is purely the
/// sheet's own segment state.
///
/// **All three cases mean the same kind of thing: a day.** That's why the
/// third one carries no date of its own here — it's `customDate` on the view,
/// and the segment shows it once it's picked. Keeping the day entirely in this
/// control is what lets both time rows stay time-only in every case, which is
/// the whole reason the rows no longer change width when the third segment is
/// the live one.
///
/// No `title` here for the same reason: the third segment reads "Custom date"
/// until a date exists and the date itself afterwards, which is view state,
/// not a property of the case. See `QueueSheet.title(for:)`.
private enum QueueDay: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case custom

    var id: String { rawValue }
}

/// Screen 4 — putting a squad in the queue.
///
/// **Two taps in the common case**, which is the whole design brief for this
/// sheet: Today is preselected with an evening window already filled in, and
/// the three nearest courts are already ticked, so a leader who wants the
/// obvious thing taps Save. Everything else is there for the leader who wants
/// something else.
///
/// **Redesigned in UI revamp Phase 2b** (`UI_REDESIGN_BRIEF.md` §5.11): one
/// form on one surface instead of three cards — the squad, the window (summed
/// up as a numeral line over its two rows), the courts — each under a `label`,
/// the rows separated by hairlines. The time rows' `ViewThatFits` ladder is
/// kept exactly; the brief names it as the pattern.
///
/// The Save button and the inline hint both read `MatchTicket.validate`, the way
/// `CreateGameSheet` reads `Game.validate` — one function, mirroring the create
/// rule condition for condition, so the button is never enabled for a write the
/// server would refuse.
struct QueueSheet: View {
    @ObservedObject private var viewModel: MatchmakingViewModel

    private let squad: Squad
    private let onDismiss: () -> Void

    @State private var selectedDay: QueueDay = .today
    @State private var selectedCourtIds: Set<String> = []
    @State private var customStart = Date()
    @State private var customEnd = Date()

    /// The day behind the third segment, `nil` until one is picked — which is
    /// exactly what makes that segment read "Custom date" rather than a date.
    @State private var customDate: Date?
    @State private var isPickingCustomDate = false
    /// The calendar's own selection while its sheet is up, so backing out of
    /// it leaves `customDate` alone.
    @State private var draftCustomDate = Date()
    @State private var courtSearchText = ""
    @FocusState private var isCourtSearchFocused: Bool
    @State private var isSaving = false
    @State private var saveError: String?

    /// Slides the selection behind the day segments — same trick, same
    /// reason, as `ProfileView`'s pane selector.
    @Namespace private var daySelection

    /// Re-evaluated on every render rather than held: a sheet open across
    /// midnight should have "Today" mean the day that's actually current.
    private var now: Date { Date() }

    init(viewModel: MatchmakingViewModel, squad: Squad, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.squad = squad
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    intro
                    windowSection
                    courtsSection

                    if let hint {
                        Text(hint)
                            .hooprType(.caption)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let saveError {
                        Text(saveError)
                            .hooprType(.caption)
                            .foregroundStyle(Color.hooprRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
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
        .sheet(isPresented: $isPickingCustomDate) {
            customDateSheet
        }
    }

    // MARK: - Sections

    /// Which squad, and what queueing does — the form's heading, not a card.
    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                SquadCrest(squad: squad, size: SquadCrest.Size.card)

                VStack(alignment: .leading, spacing: 2) {
                    Text(squad.name)
                        .hooprType(.headline)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(squad.format.displayName) · \(squad.region)")
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }
            .accessibilityElement(children: .combine)

            Text("We'll look for another squad who can play one of your courts inside your window.")
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Label, the day, the window as a numeral line, the two rows that set it,
    /// then the footnote — the grouped-form shape, without the card around the
    /// middle.
    private var windowSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("When")
            daySelector

            windowSummary
                .padding(.top, Spacing.xs)

            DividedRows {
                timeRow("From", picker: fromPicker)
                timeRow("Until", picker: untilPicker)
            }

            Text("Any time in this range works — tip-off lands on the earliest slot you and your opponent both have free.")
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The window as the number it is — "6:00 PM – 10:00 PM" — so it reads at
    /// a glance rather than across two compact pickers. On one line when it
    /// fits, the two ends stacked when it doesn't.
    private var windowSummary: some View {
        let start = customStart.formatted(date: .omitted, time: .shortened)
        let end = customEnd.formatted(date: .omitted, time: .shortened)

        return ViewThatFits(in: .horizontal) {
            Text("\(start) – \(end)")
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(start) –")
                Text(end)
            }
        }
        .hooprType(.title)
        .monospacedDigit()
        .foregroundStyle(Color.hooprPrimaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(start) until \(end)")
    }

    /// Three labels with a sliding accent underline — `ProfileView`'s pane
    /// selector and the map list's tabs, so the app switches between things
    /// one way. It was an orange pill sliding on a grey track, and its labels
    /// shrank to fit (`minimumScaleFactor(0.8)`); they wrap now.
    ///
    /// The third segment is the one that isn't just a toggle: it opens a
    /// calendar, and once a date is chosen it *becomes* that date. Tapping it
    /// again reopens the calendar rather than doing nothing, which is the
    /// only way to change a date that is now the control's own label.
    private var daySelector: some View {
        HStack(spacing: 0) {
            ForEach(QueueDay.allCases) { day in
                let isSelected = selectedDay == day

                Button {
                    if day == .custom {
                        beginPickingCustomDate()
                    } else {
                        withAnimation(.hooprSpring) {
                            selectDay(day)
                        }
                    }
                } label: {
                    VStack(spacing: Spacing.sm) {
                        Text(title(for: day))
                            .hooprType(.subhead)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(
                                isSelected ? Color.hooprPrimaryText : Color.hooprSecondaryText
                            )

                        ZStack {
                            Color.clear.frame(height: 2)
                            if isSelected {
                                Capsule()
                                    .fill(Color.hooprBrandAccent)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "day", in: daySelection)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(for: day))
                .accessibilityHint(day == .custom ? "Double tap to pick a date" : "")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hooprBorder)
                .frame(height: 1)
        }
    }

    /// "Today", "Tomorrow", and either "Custom date" or the date itself.
    private func title(for day: QueueDay) -> String {
        switch day {
        case .today:
            return "Today"
        case .tomorrow:
            return "Tomorrow"
        case .custom:
            guard let customDate else { return "Custom date" }
            return customDate.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// The calendar behind the third segment. A sheet rather than an inline
    /// expansion because the date is *shown on the segment* afterwards —
    /// somewhere to land is the whole point, and a picker that stayed open
    /// under the control would say the same thing twice.
    private var customDateSheet: some View {
        NavigationStack {
            DatePicker(
                "Date",
                selection: $draftCustomDate,
                in: Calendar.current.startOfDay(for: now)...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Color.hooprBrandAccent)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.hooprBackground)
            .navigationTitle("Pick a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPickingCustomDate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitCustomDate() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// One field row: label leading, picker trailing.
    ///
    /// The `ViewThatFits` fallback matters most in Custom date, where the
    /// picker carries a date *and* a time — a row is far roomier than the
    /// two side-by-side fields this replaced, but at the largest text sizes
    /// the pair still stops fitting on one line, and stacking beats clipping.
    private func timeRow(_ label: String, picker: some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                timeRowLabel(label)
                Spacer(minLength: 8)
                picker
            }

            VStack(alignment: .leading, spacing: 8) {
                timeRowLabel(label)
                picker
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeRowLabel(_ label: String) -> some View {
        Text(label)
            .hooprType(.body)
            .foregroundStyle(Color.hooprPrimaryText)
            .lineLimit(1)
    }

    /// Time only, in all three cases — the segment above already said which
    /// day, including when that segment *is* a date. This is what keeps both
    /// rows the same width whichever day is live, and it's why the row layout
    /// no longer has a wide case to survive.
    private var fromPicker: some View {
        DatePicker(
            "From",
            selection: $customStart,
            in: dayLowerBound...,
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .datePickerStyle(.compact)
    }

    private var untilPicker: some View {
        DatePicker(
            "Until",
            selection: $customEnd,
            in: customStart...,
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .datePickerStyle(.compact)
    }

    private var courtsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Where")
                Spacer()
                Text("\(selectedCourtIds.count) of \(MatchTicket.courtCountRange.upperBound)")
                    .hooprType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            HooprSearchField(
                text: $courtSearchText,
                placeholder: "Search all courts by name or city",
                isFocused: $isCourtSearchFocused
            )

            if offeredCourtIds.isEmpty {
                // The bundled dataset loads synchronously and holds 214
                // courts, so an empty list with no search typed means it
                // failed to load rather than that nothing is nearby. A
                // sentence, because an empty list under a "Where" heading
                // reads as a broken screen.
                Text(courtsEmptyText)
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
            } else {
                DividedRows(leadingInset: 26 + 12) {
                    ForEach(offeredCourtIds, id: \.self) { courtId in
                        courtRow(courtId)
                    }
                }

                Text(courtsHintText)
                    .hooprType(.caption)
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
                    .hooprFont(20, maximumSize: 26)
                    .foregroundStyle(
                        selectedCourtIds.contains(courtId)
                            ? Color.hooprBrandAccent
                            : Color.hooprSecondaryText
                    )
                    // As wide as the glyph's cap, so the names line up at
                    // every text size.
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.courtName(id: courtId))
                        .hooprType(.subhead)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let court = viewModel.court(id: courtId) {
                        Text(court.city)
                            .hooprType(.caption)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedCourtIds.contains(courtId) ? [.isSelected] : [])
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .hooprType(.label)
            .foregroundStyle(Color.hooprSecondaryText)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - State

    /// Whether the "Where" list is showing search results rather than nearby
    /// courts — the one flag both `offeredCourtIds` and its surrounding copy
    /// branch on.
    private var isSearchingCourts: Bool {
        !courtSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The courts a leader picks from: the nearest handful by default, plus
    /// anything already selected so a choice can't vanish when the list is
    /// recomputed — or, while searching, every match across the full 214
    /// rather than just what's nearby. A court selected through search that
    /// no longer matches the box is not in this list, but it stays selected —
    /// see `orderedSelection`, which reads `selectedCourtIds` directly rather
    /// than filtering through whatever's currently on screen.
    private var offeredCourtIds: [String] {
        guard isSearchingCourts else {
            let nearest = viewModel.nearestCourtIds(limit: 8)
            let extras = selectedCourtIds.subtracting(nearest)
            return nearest + extras.sorted()
        }
        return viewModel.searchCourts(matching: courtSearchText).map(\.id)
    }

    private var courtsEmptyText: String {
        isSearchingCourts
            ? "No courts match “\(courtSearchText)”."
            : "No courts loaded, so there's nowhere to offer. Reopen the app and try again."
    }

    private var courtsHintText: String {
        isSearchingCourts
            ? "Tap any to add it — the first one you both accept is where you'll play."
            : "Nearest first — the first one you both accept is where you'll play. Search above for one further away."
    }

    private func primeDefaults() {
        guard selectedCourtIds.isEmpty else { return }
        selectedCourtIds = Set(viewModel.nearestCourtIds())
        seed(for: selectedDay)
    }

    /// Fills the time range with a sensible default for `day`, overwriting
    /// whatever was there. Called on first appearance and on every day
    /// switch — not on every render — so a leader who hand-edits a time isn't
    /// fighting a default that keeps reasserting itself.
    private func seed(for day: QueueDay) {
        switch day {
        case .today:
            if let tonight = QueueWindow.tonight.window(format: squad.format, now: now) {
                customStart = tonight.start
                customEnd = tonight.end
            } else {
                // Evening no longer fits before midnight. Today doesn't
                // disable itself the way the old "Tonight" chip did — the
                // range is freely editable to any hour left in the day — so
                // the fallback is "as soon as it could actually start"
                // rather than refusing to offer a default at all.
                let start = MatchRules.roundedUpToGrain(now.addingTimeInterval(Game.minimumLeadTime))
                customStart = start
                customEnd = start.addingTimeInterval(squad.format.duration + MatchRules.comfortMargin.upperBound)
            }
        case .tomorrow:
            let fallback = QueueWindow.tomorrowEvening.window(format: squad.format, now: now)
            customStart = fallback?.start ?? now.addingTimeInterval(86400)
            customEnd = fallback?.end
                ?? now.addingTimeInterval(86400 + squad.format.duration + MatchRules.comfortMargin.upperBound)

        case .custom:
            // Nothing to seed. The day arrives from the calendar sheet, and
            // `commitCustomDate()` sets the times against it — seeding a
            // guessed day here would put a date on the segment nobody chose.
            break
        }
    }

    private func selectDay(_ day: QueueDay) {
        guard selectedDay != day else { return }
        selectedDay = day
        seed(for: day)
    }

    /// Opens the calendar, starting on whatever's already chosen — or two days
    /// out, which is the first day Today and Tomorrow don't already cover.
    private func beginPickingCustomDate() {
        let calendar = Calendar.current
        draftCustomDate = customDate
            ?? calendar.startOfDay(for: now.addingTimeInterval(2 * 86400))
        isPickingCustomDate = true
    }

    /// Takes the calendar's date and moves the time range onto it.
    ///
    /// **First pick seeds the evening; later ones keep the hours.** The times
    /// sitting there on a first pick belong to Today or Tomorrow — 8:43pm
    /// because that happens to be now, not because anyone chose it — so
    /// carrying them onto a date weeks out would hand over a window nobody
    /// asked for. Once a custom date exists the hours *were* chosen, and
    /// changing the date shouldn't throw them away.
    private func commitCustomDate() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: draftCustomDate)
        let isFirstPick = customDate == nil

        if isFirstPick {
            customStart = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day) ?? day
            customEnd = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day) ?? day
        } else {
            customStart = time(of: customStart, onto: day, fallbackHour: 17)
            customEnd = time(of: customEnd, onto: day, fallbackHour: 22)
        }

        customDate = day
        isPickingCustomDate = false

        withAnimation(.hooprSpring) {
            selectedDay = .custom
        }
    }

    /// `date`'s hour and minute, on `day`.
    private func time(of date: Date, onto day: Date, fallbackHour: Int) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return calendar.date(
            bySettingHour: parts.hour ?? fallbackHour,
            minute: parts.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }

    /// The earliest instant the "From" picker will accept for the live day.
    ///
    /// The compact picker only exposes hour and minute, so the *day* comes
    /// from `customStart` itself; this only stops a time landing in the past.
    /// A custom date is clamped to `now` as well, since the calendar allows
    /// picking today.
    private var dayLowerBound: Date {
        let calendar = Calendar.current
        switch selectedDay {
        case .today:
            return now
        case .tomorrow:
            return calendar.startOfDay(for: now.addingTimeInterval(86400))
        case .custom:
            guard let customDate else { return now }
            return max(now, calendar.startOfDay(for: customDate))
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

    /// The single source of truth for both the button and the hint below it —
    /// the same function the create rule mirrors.
    private var validationError: MatchTicketError? {
        MatchTicket.validate(
            courtIds: orderedSelection,
            windowStart: customStart,
            windowEnd: customEnd,
            expiresAt: QueueWindow.expiry(forWindowEnd: customEnd, now: now),
            format: squad.format,
            now: now
        )
    }

    /// Preference order is nearest-first, independent of whichever courts
    /// happen to be on screen right now — see `offeredCourtIds`'s doc comment
    /// for why the two can't be the same list once search can filter one of
    /// them out without touching the selection itself.
    private var orderedSelection: [String] {
        viewModel.sortedByDistance(selectedCourtIds)
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
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            try await viewModel.queue(
                courtIds: orderedSelection,
                windowStart: customStart,
                windowEnd: customEnd,
                expiresAt: QueueWindow.expiry(forWindowEnd: customEnd, now: now)
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

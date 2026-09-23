import Combine
import Foundation

/// Backs the "Start Run" form.
///
/// Only collects what a person actually decides: when, who can see it, and how
/// many can play. The court comes from wherever the form was opened, and
/// everything else the schema stores — host, status, rosters, timestamps — is
/// derived by `GameService` on the write path.
@MainActor
final class CreateGameViewModel: ObservableObject {
    @Published var scheduledTime: Date
    @Published var isPublic = true
    @Published var maxPlayers = Game.defaultMaxPlayers

    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    /// Set once a **private** run is written, which turns the form into its
    /// confirmation step. Public runs leave this `nil` and the sheet dismisses
    /// straight away — there's nothing to hand out.
    ///
    /// It's shown here rather than only on the run's card because this is the
    /// one moment the host is certain to be looking. **The link opens nothing
    /// yet** (`gaps/GAMES.md`), so the step leads with the court and time as
    /// the thing to send, and offers the link as a labelled reference.
    @Published private(set) var inviteLink: String?

    let court: Court

    private let gameService: GameService

    init(court: Court, gameService: GameService) {
        self.court = court
        self.gameService = gameService
        self.scheduledTime = Self.defaultTipOff()
    }

    // MARK: - Bounds

    /// The window `firestore.rules` enforces, so the picker can't offer a date
    /// the server will reject.
    var scheduleRange: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(Game.minimumLeadTime)
            ... now.addingTimeInterval(Game.schedulingWindow)
    }

    var canDecreasePlayers: Bool {
        !isSaving && maxPlayers > Game.maxPlayersRange.lowerBound
    }

    var canIncreasePlayers: Bool {
        !isSaving && maxPlayers < Game.maxPlayersRange.upperBound
    }

    func adjustPlayers(by delta: Int) {
        maxPlayers = Game.validMaxPlayers(maxPlayers + delta)
    }

    /// Names the format when the roster happens to be an even side, which is
    /// how people actually describe a run. Silent otherwise rather than
    /// inventing a label for 7.
    var formatText: String? {
        guard maxPlayers.isMultiple(of: 2) else { return nil }
        let perSide = maxPlayers / 2
        return "\(perSide)-on-\(perSide)"
    }

    /// **Says what invite-only actually does today** (UI revamp Phase 2b,
    /// brief §5.11). It promised "a link to share with the players you want
    /// in" — but the link opens nothing, and the `games` read rule refuses a
    /// non-member, so an invite-only run holds only its host
    /// (`gaps/GAMES.md`). Choosing it on that promise is the kind of claim the
    /// revamp's §2d fails outright. `nonisolated static` so it's testable
    /// without a `GameService`.
    ///
    /// Each is one short line under its option (2026-09-23 — the sheet had
    /// "more text and not a lot of icons"); the globe and the lock say the
    /// rest.
    nonisolated static func visibilityCaption(isPublic: Bool) -> String {
        isPublic
            ? "Anyone nearby can find and join."
            : "Hidden. Just you until invites work."
    }

    // MARK: - The day

    /// One chip per day a run can be on: today, if a tip-off is still
    /// possible, through the last day `firestore.rules` allows.
    var dayOptions: [Date] { Self.dayOptions(in: scheduleRange) }

    nonisolated static func dayOptions(in range: ClosedRange<Date>, calendar: Calendar = .current) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: range.lowerBound)
        let last = calendar.startOfDay(for: range.upperBound)
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    func isSelectedDay(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: scheduledTime)
    }

    /// Moves the run to `day` and keeps its time — the host picked a day, not
    /// a new time.
    func selectDay(_ day: Date) {
        scheduledTime = Self.tipOff(on: day, keepingTimeOf: scheduledTime, within: scheduleRange)
    }

    /// `day` at `time`'s hour and minute, kept inside `range`.
    ///
    /// A time already past on that day (moving a 9 AM run to today, at noon)
    /// becomes the next quarter hour the rules allow, on the same day where
    /// there is one; a time past the end of the window becomes its end.
    nonisolated static func tipOff(
        on day: Date,
        keepingTimeOf time: Date,
        within range: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> Date {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        let candidate = calendar.date(
            bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day
        ) ?? day

        if candidate < range.lowerBound {
            let rounded = roundedUpToQuarterHour(range.lowerBound)
            return calendar.isDate(rounded, inSameDayAs: day) ? min(rounded, range.upperBound) : range.lowerBound
        }
        return min(candidate, range.upperBound)
    }

    /// What a day chip says: "Today" or the weekday over the date's number,
    /// and the whole date for VoiceOver.
    struct DayChipText: Equatable {
        let weekday: String
        let number: String
        let spoken: String
    }

    nonisolated static func dayChipText(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> DayChipText {
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return DayChipText(
            weekday: isToday ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)),
            number: day.formatted(.dateTime.day()),
            spoken: isToday ? "Today, \(date)" : date
        )
    }

    // MARK: - The pick, as it reads

    /// "Tonight" / "Tomorrow" / "Sat, Sep 27" — `Game`'s own split, so the pick
    /// reads exactly as the run will once it exists.
    var tipOffDayText: String { Game.dayText(for: scheduledTime) }

    /// "7:30 PM" — the sheet's numeral.
    var tipOffTimeText: String { Game.timeText(for: scheduledTime) }

    /// What a host sends their players for an invite-only run: where and when,
    /// which works today, rather than a link that doesn't.
    var shareText: String {
        Self.shareText(
            courtName: court.displayName,
            city: court.city,
            day: tipOffDayText,
            time: tipOffTimeText
        )
    }

    /// "Pickup run at East End Park, Durham — Tonight at 7:30 PM".
    nonisolated static func shareText(courtName: String, city: String, day: String, time: String) -> String {
        let place = city.isEmpty ? courtName : "\(courtName), \(city)"
        return "Pickup run at \(place) — \(day) at \(time)"
    }

    /// The one check the form runs, shared with the write path — the button
    /// and the service can't disagree about what a valid run is.
    private var validationError: GameError? {
        Game.validate(
            courtId: court.id,
            scheduledTime: scheduledTime,
            maxPlayers: maxPlayers
        )
    }

    var canSave: Bool {
        !isSaving && validationError == nil
    }

    /// Names the problem in place rather than leaving Create greyed out with no
    /// explanation — which happens on its own if the form sits open long enough
    /// for the picked time to arrive.
    var validationHint: String? {
        validationError.map {
            GameService.message(for: $0, whileDoing: "starting your run", context: .write)
        }
    }

    // MARK: - Saving

    /// - Returns: `true` once the run is written. The new run arrives in the
    ///   Local Runs tab on the listener that's already open, so a public run
    ///   has nothing left to show and the caller dismisses. A private one sets
    ///   `inviteLink` first — the caller checks it before dismissing.
    func create() async -> Bool {
        guard !isSaving, inviteLink == nil else { return false }
        if let invalid = validationError {
            errorMessage = GameService.message(for: invalid, whileDoing: "starting your run", context: .write)
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let gameId = try await gameService.createGame(
                courtId: court.id,
                scheduledTime: scheduledTime,
                isPublic: isPublic,
                maxPlayers: maxPlayers
            )
            errorMessage = nil
            if !isPublic {
                inviteLink = InviteLink.text(forGameId: gameId)
            }
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// An hour out, rounded up to the next quarter hour — close enough to be
    /// the answer for a spontaneous run, tidy enough not to read as a
    /// timestamp.
    private static func defaultTipOff(from now: Date = Date()) -> Date {
        roundedUpToQuarterHour(now.addingTimeInterval(60 * 60))
    }

    nonisolated static func roundedUpToQuarterHour(_ date: Date) -> Date {
        let quarterHour: TimeInterval = 15 * 60
        let rounded = (date.timeIntervalSinceReferenceDate / quarterHour).rounded(.up) * quarterHour
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    private static func message(for error: Error) -> String {
        guard let gameError = error as? GameError else {
            return error.localizedDescription
        }
        return GameService.message(for: gameError, whileDoing: "starting your run", context: .write)
    }
}

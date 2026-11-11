import CoreLocation
import MapKit
import UIKit
import XCTest
@testable import hoopr

/// Pins `HomeViewModel.rankHotCourts`, the one piece of derived logic on the
/// Home tab.
///
/// Worth pinning because two of its rules are invisible until they break in
/// production: a `[String: Int]` has no stable iteration order, so without the
/// name tie-break the hot list silently reshuffles itself between rebuilds
/// while showing identical numbers; and a court with no games has to be absent
/// rather than a zero, or "hot right now" fills up with cold courts the moment
/// a city is quiet.
///
/// Pure and `nonisolated`, so none of this needs a service or Firebase — the
/// same shape `MapViewModelTests` uses for `gameCountsByFacility`.
final class HomeViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func court(
        _ id: String,
        name: String,
        city: String = "Durham",
        facilityId: String? = nil,
        latitude: Double = 35.99,
        longitude: Double = -78.90
    ) -> Court {
        Court(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            address: "1 Test Way",
            city: city,
            hoops: 2,
            surface: nil,
            isLit: nil,
            isCovered: nil,
            access: .public,
            facilityId: facilityId,
            osmType: nil,
            osmId: nil
        )
    }

    // MARK: - The stats scoreboard

    private func squad(named name: String = "Hornets") -> Squad {
        Squad(
            id: "squad-1",
            name: name,
            nameLower: name.lowercased(),
            leaderId: "leader",
            memberIds: ["leader"],
            format: .threeVThree,
            iconKey: "basketball.fill",
            colorKey: "orange",
            region: "durham",
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func scoreboard(
        completed: Int = 12,
        thisWeek: Int = 2,
        streak: Int = 3,
        last: String = "Yesterday",
        squad: Squad? = nil,
        wins: Int = 4,
        losses: Int = 1
    ) -> [HomeViewModel.ScoreboardStat] {
        HomeViewModel.scoreboardStats(
            completedCount: completed,
            runsThisWeek: thisWeek,
            streak: streak,
            lastCompletedText: last,
            squadStanding: squad.map {
                HomeViewModel.SquadStanding(squad: $0, record: SeasonGame.Record(wins: wins, losses: losses))
            }
        )
    }

    /// The panels take turns in this order — this week first, because it is
    /// the one that changes — and each says what it is, its number and its unit.
    func testTheScoreboardsRunPanelsInOrder() {
        let stats = scoreboard()

        XCTAssertEqual(stats.map(\.kind), [.thisWeek, .streak, .total, .lastRun])
        XCTAssertEqual(stats.map(\.label), ["Done this week", "Streak", "Total", "Last run"])
        XCTAssertEqual(stats.map(\.value), ["2", "3", "12", "Yesterday"])
        XCTAssertEqual(stats.map(\.unit), ["runs", "wks", "runs", nil])
    }

    /// A squad's record slots in second, with the squad's name as its label.
    func testASquadsRecordComesSecond() {
        let stats = scoreboard(squad: squad())

        XCTAssertEqual(stats.map(\.kind), [.thisWeek, .squad, .streak, .total, .lastRun])
        let record = stats[1]
        XCTAssertEqual(record.label, "Hornets")
        XCTAssertEqual(record.value, "4–1")
        XCTAssertNil(record.unit)
        XCTAssertEqual(record.standing?.record, SeasonGame.Record(wins: 4, losses: 1))
    }

    /// No runs yet: the run panels would be zeros and a dash, so they're left
    /// out and a squad shows alone. Neither: nothing, and Home hides the board.
    func testWithNoRunsOnlyASquadShowsAndWithNeitherNothingDoes() {
        XCTAssertEqual(scoreboard(completed: 0, thisWeek: 0, squad: squad()).map(\.kind), [.squad])
        XCTAssertTrue(scoreboard(completed: 0, thisWeek: 0).isEmpty)
    }

    /// "1 run", "1 wk" — the old card once said "1 wks".
    func testUnitsAreSingularAtOne() {
        let stats = scoreboard(completed: 1, thisWeek: 1, streak: 1)

        XCTAssertEqual(stats.map(\.unit), ["run", "wk", "run", nil])
    }

    /// VoiceOver reads the board as sentences, never as abbreviations.
    func testEveryPanelSpeaksAsASentence() {
        let stats = scoreboard(squad: squad())

        XCTAssertEqual(stats.map(\.spoken), [
            "2 runs done this week",
            "Hornets, 4 wins, 1 loss this season",
            "3 week streak",
            "12 runs in all",
            "last run yesterday",
        ])
        XCTAssertEqual(scoreboard(completed: 1, thisWeek: 1, streak: 1).map(\.spoken).prefix(3), [
            "1 run done this week", "1 week streak", "1 run in all",
        ])
    }

    /// **The count is completed runs only, and the label says so** (design
    /// critique, 2026-10-09). "This week · 0 runs" under a hero reading
    /// "Hosting tonight" read as a contradiction; the number never changed, so
    /// only the words do — and VoiceOver hears the same words.
    func testThisWeeksPanelSaysItCountsRunsThatAreDone() {
        let none = scoreboard(thisWeek: 0)[0]
        XCTAssertEqual(none.kind, .thisWeek)
        XCTAssertEqual(none.label, "Done this week")
        XCTAssertEqual(none.value, "0")
        XCTAssertEqual(none.spoken, "0 runs done this week")

        XCTAssertEqual(scoreboard(thisWeek: 1)[0].spoken, "1 run done this week")
    }

    /// **Two tiers, the user's call (2026-10-05).** The confirmed record takes
    /// the numeral the band uses for it; the self-reported counts stop a step
    /// below, never at the record's size.
    @MainActor
    func testTheRecordTakesTheNumeralAndTheRunCountsATierBelow() {
        XCTAssertEqual(StatsScoreboard.role(for: .squad), .numeral)
        for kind in [HomeViewModel.ScoreboardStat.Kind.thisWeek, .streak, .total, .lastRun] {
            XCTAssertEqual(StatsScoreboard.role(for: kind), .title, "\(kind)")
        }
    }

    /// The stats card's icons stay on the board's labels; the squad shows its
    /// crest instead.
    @MainActor
    func testEveryRunPanelKeepsItsIcon() {
        XCTAssertEqual(StatsScoreboard.symbol(for: .streak), "flame.fill")
        XCTAssertEqual(StatsScoreboard.symbol(for: .total), "basketball.fill")
        XCTAssertEqual(StatsScoreboard.symbol(for: .lastRun), "clock.fill")
        XCTAssertNotNil(StatsScoreboard.symbol(for: .thisWeek))
        XCTAssertNil(StatsScoreboard.symbol(for: .squad))
    }

    // MARK: - The scoreboard cannot break a value

    /// Every size, smallest to largest.
    private let everySize: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]

    /// **Every value fits one line of the screen**, so a number never breaks
    /// and "Yesterday" never becomes "Yester / day". The panel is a single line
    /// by design; this is what keeps that honest.
    ///
    /// At Home's full width at every size, the largest accessibility size
    /// included — it is what the board gets once the calendar tile goes under
    /// it. Beside the tile at every size the tile is beside it, which has to
    /// include the default one.
    @MainActor
    func testEveryScoreboardValueFitsOnOneLineAtEverySize() {
        let besideTile = HomeHeroMetrics.contentWidth - Spacing.md - RunCalendarTileMetrics.width

        func assertFits(cardWidth: CGFloat, _ category: UIContentSizeCategory) {
            let inner = StatsScoreboardMetrics.innerWidth(cardWidth: cardWidth)
            for line in StatsScoreboardMetrics.worstCase {
                let width = StatsScoreboardMetrics.lineWidth(
                    value: line.value,
                    unit: line.unit,
                    role: StatsScoreboard.role(for: line.kind),
                    at: category
                )
                XCTAssertLessThanOrEqual(
                    width, inner,
                    "\"\(line.value)\" would break at \(category.rawValue): \(width)pt in \(inner)pt"
                )
            }
        }

        for category in everySize {
            assertFits(cardWidth: HomeHeroMetrics.contentWidth, category)
            if HomeStatsLayout.isSideBySide(at: category) {
                assertFits(cardWidth: besideTile, category)
            }
        }
        XCTAssertTrue(HomeStatsLayout.isSideBySide(at: .large), "the default size has the tile beside the board")
    }

    /// **Every run panel's label fits one line, at every size** (2026-10-09)
    /// — beside the calendar tile at the sizes the tile is beside the board,
    /// at Home's full width from the size it goes under. The labels are read
    /// from `scoreboardStats`, so a renamed one is measured as written.
    ///
    /// The squad panel's label is the squad's name, any length the create
    /// form allows; it wraps, and isn't held to a line.
    @MainActor
    func testEveryRunPanelsLabelFitsOnOneLineAtEverySize() {
        let besideTile = HomeHeroMetrics.contentWidth - Spacing.md - RunCalendarTileMetrics.width

        XCTAssertEqual(
            StatsScoreboardMetrics.runPanelLabels.map(\.label),
            ["Done this week", "Streak", "Total", "Last run"]
        )
        for category in everySize {
            let card = HomeStatsLayout.isSideBySide(at: category) ? besideTile : HomeHeroMetrics.contentWidth
            let available = StatsScoreboardMetrics.innerWidth(cardWidth: card) - StatsScoreboardMetrics.pauseReserve
            for panel in StatsScoreboardMetrics.runPanelLabels {
                let width = StatsScoreboardMetrics.labelWidth(
                    panel.label,
                    symbol: StatsScoreboard.symbol(for: panel.kind),
                    at: category
                )
                XCTAssertLessThanOrEqual(
                    width, available,
                    "\"\(panel.label)\" would wrap at \(category.rawValue): \(width)pt in \(available)pt"
                )
            }
        }
    }

    /// **"Done this week" is what moves the tile under the board at
    /// `.extraLarge`** — every value would still fit beside it there, the
    /// label wouldn't. One size earlier than the values alone, rather than a
    /// label broken onto two lines (the user's call, 2026-10-09).
    @MainActor
    func testTheLabelMovesTheTileUnderTheBoardAtExtraLarge() {
        let besideTile = HomeHeroMetrics.contentWidth - Spacing.md - RunCalendarTileMetrics.width

        XCTAssertTrue(HomeStatsLayout.isSideBySide(at: .large))
        XCTAssertTrue(StatsScoreboardMetrics.everyLabelFits(cardWidth: besideTile, at: .large))

        XCTAssertTrue(StatsScoreboardMetrics.everyValueFits(cardWidth: besideTile, at: .extraLarge))
        XCTAssertFalse(StatsScoreboardMetrics.everyLabelFits(cardWidth: besideTile, at: .extraLarge))
        XCTAssertFalse(HomeStatsLayout.isSideBySide(at: .extraLarge))
    }

    // MARK: - Choosing the next run

    private func queuedRun(
        _ id: String,
        at scheduledTime: Date,
        status: Game.Status = .open,
        courtId: String = "court-a"
    ) -> Game {
        Game(
            id: id,
            hostId: "host",
            courtId: courtId,
            scheduledTime: scheduledTime,
            isPublic: false,
            maxPlayers: 10,
            status: status,
            playerIds: ["host"],
            queuedPlayerIds: [],
            createdAt: scheduledTime,
            updatedAt: scheduledTime,
            completedAt: status == .completed ? scheduledTime : nil
        )
    }

    /// **The bug this guards was live on 2026-09-22.** A run the host had
    /// marked complete stayed in `queuedGames` — the listener doesn't filter by
    /// status — and Home's hero announced it as tonight's run while the map
    /// said the same court had nothing on.
    func testACompletedRunIsNeverTheNextRun() {
        let now = Date()
        let finished = queuedRun("finished", at: now.addingTimeInterval(-60 * 60), status: .completed)
        let later = queuedRun("later", at: now.addingTimeInterval(2 * 60 * 60))

        XCTAssertEqual(HomeViewModel.nextRun(from: [finished, later], at: now)?.id, "later")
        XCTAssertNil(HomeViewModel.nextRun(from: [finished], at: now))
    }

    /// Past the grace window a run ages out of Home exactly when it ages out
    /// of the Runs tab and the map — they all ask `isVisible(at:)`.
    func testARunPastTheGraceWindowIsNotTheNextRun() {
        let now = Date()
        let stale = queuedRun("stale", at: now.addingTimeInterval(-(Game.visibilityGrace + 60)))
        XCTAssertNil(HomeViewModel.nextRun(from: [stale], at: now))
    }

    /// A run that has started but isn't over still counts — it's the one
    /// you're late for.
    func testARunUnderwayIsStillTheNextRun() {
        let now = Date()
        let underway = queuedRun("underway", at: now.addingTimeInterval(-30 * 60))
        XCTAssertEqual(HomeViewModel.nextRun(from: [underway], at: now)?.id, "underway")
    }

    // MARK: - "Tonight nearby" without the hero's court

    /// Noon today, so "later today" and "tomorrow" never straddle a midnight
    /// the test happened to run across.
    private var noon: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }

    private func hot(_ id: String, _ count: Int) -> HomeViewModel.HotCourt {
        HomeViewModel.HotCourt(court: court(id, name: id.capitalized), gameCount: count)
    }

    /// The hero's run: tonight at Long Meadow, unless told otherwise.
    private func booked(at courtId: String = "long-meadow", hoursFromNoon: Double = 5.75) -> Game {
        queuedRun("booked", at: noon.addingTimeInterval(hoursFromNoon * 60 * 60), courtId: courtId)
    }

    /// **The critique's repeat.** The hero says Long Meadow tonight; its only
    /// run today is that one, so the list doesn't say it again — and the
    /// spare ranked court takes its row.
    func testTheBookedCourtIsDroppedWhenItsOnlyRunTodayIsTheBookedOne() {
        let ranked = [hot("alpha", 3), hot("long-meadow", 1), hot("bravo", 1), hot("charlie", 1)]

        let nearby = HomeViewModel.excludingBookedCourt(from: ranked, bookedRun: booked(), limit: 3, now: noon)

        XCTAssertEqual(nearby.map(\.court.id), ["alpha", "bravo", "charlie"])
    }

    /// Other runs at the booked court today are news the hero doesn't carry.
    func testTheBookedCourtStaysWhenItHasOtherRunsToday() {
        let ranked = [hot("long-meadow", 2), hot("alpha", 1)]

        let nearby = HomeViewModel.excludingBookedCourt(from: ranked, bookedRun: booked(), limit: 3, now: noon)

        XCTAssertEqual(nearby.map(\.court.id), ["long-meadow", "alpha"])
    }

    /// "Tonight nearby" is about today. A hero reading "Tomorrow" repeats
    /// nothing in it, so nothing is dropped — and only `limit` rows show.
    func testNothingIsDroppedWhenTheBookedRunIsNotToday() {
        let ranked = [hot("long-meadow", 1), hot("alpha", 1), hot("bravo", 1), hot("charlie", 1)]
        let tomorrow = booked(hoursFromNoon: 24)

        let nearby = HomeViewModel.excludingBookedCourt(from: ranked, bookedRun: tomorrow, limit: 3, now: noon)

        XCTAssertEqual(nearby.map(\.court.id), ["long-meadow", "alpha", "bravo"])
    }

    /// No hero, nothing to repeat.
    func testNothingIsDroppedWithoutABookedRun() {
        let ranked = [hot("long-meadow", 1), hot("alpha", 1)]

        let nearby = HomeViewModel.excludingBookedCourt(from: ranked, bookedRun: nil, limit: 3, now: noon)

        XCTAssertEqual(nearby.map(\.court.id), ["long-meadow", "alpha"])
    }

    /// **The booked court was the whole list: it stays.** Dropping it would
    /// empty the list, and an empty list switches the section to its map
    /// preview — "Nothing on nearby yet" — beside a hero saying you're playing
    /// tonight. The live account on 2026-10-09 is exactly this case.
    func testTheListIsKeptWhenTheBookedCourtIsAllOfIt() {
        let ranked = [hot("long-meadow", 1)]

        let nearby = HomeViewModel.excludingBookedCourt(from: ranked, bookedRun: booked(), limit: 3, now: noon)

        XCTAssertEqual(nearby.map(\.court.id), ["long-meadow"])
        XCTAssertEqual(
            HomeViewModel.nearbySection(hasLoaded: true, hasHotCourts: !nearby.isEmpty, hasError: false, isRecovering: false),
            .list
        )
    }

    /// Only the booked court can go: another court down to one run today is
    /// still a place to play.
    func testOnlyTheBookedCourtIsEverDropped() {
        let ranked = [hot("alpha", 1), hot("long-meadow", 1), hot("bravo", 1)]

        let nearby = HomeViewModel.excludingBookedCourt(from: ranked, bookedRun: booked(), limit: 3, now: noon)

        XCTAssertEqual(nearby.map(\.court.id), ["alpha", "bravo"])
    }

    func testAZeroLimitShowsNothing() {
        XCTAssertTrue(
            HomeViewModel.excludingBookedCourt(from: [hot("alpha", 1)], bookedRun: nil, limit: 0, now: noon).isEmpty
        )
    }

    // MARK: - Ranking

    func testOrdersByGameCountDescending() {
        let courts = [
            court("a", name: "Alpha"),
            court("b", name: "Bravo"),
            court("c", name: "Charlie"),
        ]

        let ranked = HomeViewModel.rankHotCourts(
            counts: ["a": 1, "b": 5, "c": 3],
            courts: courts,
            limit: 3
        )

        XCTAssertEqual(ranked.map(\.court.id), ["b", "c", "a"])
        XCTAssertEqual(ranked.map(\.gameCount), [5, 3, 1])
    }

    /// The rule that keeps the list from reshuffling between rebuilds.
    func testTiesBreakOnDisplayNameSoOrderIsStable() {
        let courts = [
            court("z", name: "Zulu"),
            court("a", name: "Alpha"),
            court("m", name: "Mike"),
        ]
        let counts = ["z": 2, "a": 2, "m": 2]

        let first = HomeViewModel.rankHotCourts(counts: counts, courts: courts, limit: 3)
        XCTAssertEqual(first.map(\.court.id), ["a", "m", "z"])

        // Same inputs in a different order must produce the same output — a
        // dictionary's iteration order is not guaranteed between runs.
        let reversed = HomeViewModel.rankHotCourts(
            counts: counts,
            courts: courts.reversed(),
            limit: 3
        )
        XCTAssertEqual(reversed.map(\.court.id), ["a", "m", "z"])
    }

    /// Ties break on `displayName`, not the stored `name` — the dataset's
    /// "Basketball Court" boilerplate would otherwise sort courts by a string
    /// the user never sees.
    func testTieBreakUsesDisplayNameNotStoredName() {
        let courts = [
            court("first", name: "Basketball Court Alpha"),
            court("second", name: "Basketball Court Zulu"),
        ]

        let ranked = HomeViewModel.rankHotCourts(
            counts: ["first": 1, "second": 1],
            courts: courts,
            limit: 2
        )

        XCTAssertEqual(
            ranked.map(\.court.displayName),
            courts.map(\.displayName).sorted(),
            "the tie-break must agree with what the row actually renders"
        )
    }

    func testCourtsWithNoGamesAreAbsentRatherThanZero() {
        let courts = [court("a", name: "Alpha"), court("b", name: "Bravo")]

        let ranked = HomeViewModel.rankHotCourts(
            counts: ["a": 2],
            courts: courts,
            limit: 3
        )

        XCTAssertEqual(ranked.map(\.court.id), ["a"])
    }

    /// A count of zero is as good as absent — neither is "hot".
    func testAnExplicitZeroCountIsDroppedToo() {
        let ranked = HomeViewModel.rankHotCourts(
            counts: ["a": 0],
            courts: [court("a", name: "Alpha")],
            limit: 3
        )

        XCTAssertTrue(ranked.isEmpty)
    }

    func testHonoursTheLimit() {
        let courts = (1...10).map { court("c\($0)", name: "Court \($0)") }
        let counts = Dictionary(uniqueKeysWithValues: courts.map { ($0.id, 1) })

        let ranked = HomeViewModel.rankHotCourts(counts: counts, courts: courts, limit: 3)

        XCTAssertEqual(ranked.count, 3)
    }

    /// Guards the `limit > 0` early return — a non-positive limit must produce
    /// an empty list rather than trapping in `prefix`.
    func testANonPositiveLimitYieldsNothing() {
        let courts = [court("a", name: "Alpha")]

        XCTAssertTrue(HomeViewModel.rankHotCourts(counts: ["a": 3], courts: courts, limit: 0).isEmpty)
        XCTAssertTrue(HomeViewModel.rankHotCourts(counts: ["a": 3], courts: courts, limit: -1).isEmpty)
    }

    /// A count for a court that isn't in the dataset can't be rendered, so it
    /// must be skipped rather than crashing the ranking.
    func testCountsForUnknownCourtsAreIgnored() {
        let ranked = HomeViewModel.rankHotCourts(
            counts: ["ghost": 9, "a": 1],
            courts: [court("a", name: "Alpha")],
            limit: 3
        )

        XCTAssertEqual(ranked.map(\.court.id), ["a"])
    }

    func testAnEmptyDatasetYieldsNothing() {
        XCTAssertTrue(HomeViewModel.rankHotCourts(counts: ["a": 4], courts: [], limit: 3).isEmpty)
    }

    /// The Home tab shows three. Pinned so a change to the constant is a
    /// deliberate edit here rather than a silent layout shift.
    func testHotCourtLimitIsThree() {
        XCTAssertEqual(HomeViewModel.hotCourtLimit, 3)
    }

    // MARK: - Nearest courts (the empty state's map preview)

    /// Downtown Durham, the fallback origin (`LocationService.defaultLocation`).
    /// A degree of latitude is ~111km, so 0.01 is about 1.1km — far enough
    /// apart that the order is unambiguous.
    private let origin = CLLocationCoordinate2D(latitude: 35.9940, longitude: -78.8986)

    private func court(_ id: String, name: String, northOfOriginBy degrees: Double) -> Court {
        court(id, name: name, latitude: origin.latitude + degrees, longitude: origin.longitude)
    }

    func testNearestCourtsAreOrderedByDistance() {
        let courts = [
            court("far", name: "Alpha", northOfOriginBy: 0.03),
            court("near", name: "Bravo", northOfOriginBy: 0.01),
            court("middle", name: "Charlie", northOfOriginBy: -0.02),
        ]

        let nearest = HomeViewModel.nearestCourts(to: origin, in: courts, limit: 3)

        XCTAssertEqual(nearest.map(\.id), ["near", "middle", "far"])
    }

    /// Two courts at one distance — two hoops at the same park — must not swap
    /// places between rebuilds, or the preview's dots would move under nothing.
    func testNearestCourtsBreakTiesOnDisplayName() {
        let courts = [
            court("z", name: "Zulu", northOfOriginBy: 0.01),
            court("a", name: "Alpha", northOfOriginBy: 0.01),
            court("m", name: "Mike", northOfOriginBy: 0.01),
        ]

        XCTAssertEqual(
            HomeViewModel.nearestCourts(to: origin, in: courts, limit: 3).map(\.id),
            ["a", "m", "z"]
        )
        XCTAssertEqual(
            HomeViewModel.nearestCourts(to: origin, in: courts.reversed(), limit: 3).map(\.id),
            ["a", "m", "z"]
        )
    }

    /// The tie-break is the name the user would see, as `rankHotCourts`' is.
    func testNearestCourtsTieBreakUsesDisplayNameNotStoredName() {
        let courts = [
            court("second", name: "Basketball Court Zulu", northOfOriginBy: 0.01),
            court("first", name: "Basketball Court Alpha", northOfOriginBy: 0.01),
        ]

        let nearest = HomeViewModel.nearestCourts(to: origin, in: courts, limit: 2)

        XCTAssertEqual(nearest.map(\.displayName), courts.map(\.displayName).sorted())
    }

    func testNearestCourtsHonourTheLimit() {
        let courts = (1...10).map { court("c\($0)", name: "Court \($0)", northOfOriginBy: Double($0) * 0.01) }

        let nearest = HomeViewModel.nearestCourts(to: origin, in: courts, limit: 5)

        XCTAssertEqual(nearest.map(\.id), ["c1", "c2", "c3", "c4", "c5"])
    }

    func testNearestCourtsWithANonPositiveLimitYieldNothing() {
        let courts = [court("a", name: "Alpha", northOfOriginBy: 0.01)]

        XCTAssertTrue(HomeViewModel.nearestCourts(to: origin, in: courts, limit: 0).isEmpty)
        XCTAssertTrue(HomeViewModel.nearestCourts(to: origin, in: courts, limit: -1).isEmpty)
    }

    func testNearestCourtsOfAnEmptyDatasetAreNothing() {
        XCTAssertTrue(HomeViewModel.nearestCourts(to: origin, in: [], limit: 5).isEmpty)
    }

    /// Pinned like `hotCourtLimit`, so a change is a deliberate edit here.
    @MainActor
    func testPreviewCourtLimitIsFive() {
        XCTAssertEqual(HomeViewModel.previewCourtLimit, 5)
    }

    // MARK: - Which "Tonight nearby" shows

    func testTheMapPreviewShowsOnlyWhenLoadedEmptyAndHealthy() {
        XCTAssertEqual(
            HomeViewModel.nearbySection(hasLoaded: true, hasHotCourts: false, hasError: false, isRecovering: false),
            .preview
        )
        XCTAssertEqual(
            HomeViewModel.nearbySection(hasLoaded: true, hasHotCourts: true, hasError: false, isRecovering: false),
            .list
        )
        XCTAssertEqual(
            HomeViewModel.nearbySection(hasLoaded: false, hasHotCourts: false, hasError: false, isRecovering: false),
            .loading
        )
    }

    /// With the listener down an empty list means "couldn't look", so the
    /// empty state — which says "nothing's on" — must not show.
    func testAFailedOrRecoveringListenerIsNeverTheEmptyState() {
        for hasLoaded in [false, true] {
            XCTAssertEqual(
                HomeViewModel.nearbySection(hasLoaded: hasLoaded, hasHotCourts: false, hasError: true, isRecovering: false),
                .unavailable
            )
            XCTAssertEqual(
                HomeViewModel.nearbySection(hasLoaded: hasLoaded, hasHotCourts: false, hasError: false, isRecovering: true),
                .unavailable
            )
        }
    }

    /// A list already on screen stays through a failure: stale, not wrong.
    func testAListAlreadyShownSurvivesAFailure() {
        XCTAssertEqual(
            HomeViewModel.nearbySection(hasLoaded: true, hasHotCourts: true, hasError: true, isRecovering: false),
            .list
        )
        XCTAssertEqual(
            HomeViewModel.nearbySection(hasLoaded: true, hasHotCourts: true, hasError: false, isRecovering: true),
            .list
        )
    }

    // MARK: - The preview's framing

    /// One court next door still frames a neighbourhood, not a street.
    func testThePreviewNeverFramesTighterThanTheMinimumSpan() {
        let region = NearbyPreviewFraming.region(
            around: origin,
            framing: [court("next door", name: "Alpha", northOfOriginBy: 0.0005)]
        )
        let floor = NearbyPreviewFraming.minimumSpanMeters

        XCTAssertGreaterThanOrEqual(region.span.latitudeDelta * 111_000, floor * 0.99)
        XCTAssertEqual(region.center.latitude, origin.latitude, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, origin.longitude, accuracy: 1e-9)
    }

    /// The frame reaches past the farthest court on each axis.
    func testThePreviewFramesTheFarthestCourt() {
        let far = court("far", name: "Alpha", latitude: origin.latitude - 0.03, longitude: origin.longitude + 0.05)
        let region = NearbyPreviewFraming.region(around: origin, framing: [far])

        XCTAssertGreaterThan(region.span.latitudeDelta / 2, 0.03)
        XCTAssertGreaterThan(region.span.longitudeDelta / 2, 0.05)
    }

    /// Outside the dataset's cities the nearest court can be a state away; the
    /// frame stops at the maximum rather than zooming out to the coastline.
    func testThePreviewNeverFramesWiderThanTheMaximumSpan() {
        XCTAssertEqual(
            NearbyPreviewFraming.span(holding: 500_000),
            NearbyPreviewFraming.maximumSpanMeters
        )
        XCTAssertEqual(NearbyPreviewFraming.span(holding: 0), NearbyPreviewFraming.minimumSpanMeters)
    }

    // MARK: - lastCompletedText

    /// Same shape as the `rankHotCourts` tests above: pure function, no
    /// service construction. Dates are computed off the real `Date()` rather
    /// than hardcoded literals, because `lastCompletedText` resolves
    /// "today"/"yesterday" via `Calendar.isDateInToday`/`isDateInYesterday`,
    /// which compare against the actual current date regardless of the
    /// `relativeTo` argument — see the note in the report-back for why that
    /// parameter doesn't make the relative cases independently testable.
    private func expectedMonthDay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    /// The lazy-init / brand-new-account default.
    func testNilDateReturnsEmDash() {
        XCTAssertEqual(HomeViewModel.lastCompletedText(for: nil), "—")
    }

    func testTodayReturnsToday() {
        XCTAssertEqual(HomeViewModel.lastCompletedText(for: Date()), "Today")
    }

    func testYesterdayReturnsYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(HomeViewModel.lastCompletedText(for: yesterday), "Yesterday")
    }

    /// The boundary between the two relative cases and the absolute fallback.
    func testTwoDaysAgoReturnsFormattedDateNotTodayOrYesterday() {
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        XCTAssertEqual(HomeViewModel.lastCompletedText(for: twoDaysAgo), expectedMonthDay(for: twoDaysAgo))
    }

    /// Pins the deliberate no-year simplification so it can't drift in silently.
    func testOverAYearAgoStillOmitsTheYear() {
        let overAYearAgo = Calendar.current.date(byAdding: .day, value: -400, to: Date())!
        let text = HomeViewModel.lastCompletedText(for: overAYearAgo)

        XCTAssertEqual(text, expectedMonthDay(for: overAYearAgo))
        XCTAssertFalse(text.contains(String(Calendar.current.component(.year, from: overAYearAgo))))
    }

    // MARK: - Facilities

    /// A park OSM split into three surfaces is one destination, and `counts` is
    /// keyed by facility — so without the dedup all three rows would appear,
    /// each showing the same tally, filling "Hot right now" with one place.
    func testAFacilityAppearsOnceInTheHotList() {
        let courts = [
            court("lm-1", name: "Long Meadow Park Basketball Court #1", facilityId: "f-lm"),
            court("lm-2", name: "Long Meadow Park Basketball Court #2", facilityId: "f-lm"),
            court("lm-3", name: "Long Meadow Park Basketball Court #3", facilityId: "f-lm"),
            court("wt", name: "Walltown Park Basketball Court", facilityId: "f-wt"),
        ]

        let ranked = HomeViewModel.rankHotCourts(
            counts: ["f-lm": 3, "f-wt": 1],
            courts: courts,
            limit: 3
        )

        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked.map(\.court.id), ["lm-1", "wt"])
        XCTAssertEqual(ranked.map(\.gameCount), [3, 1])
    }

    /// The representative is stable across rebuilds: `courts` arrives name-sorted
    /// from `CourtService`, so the same surface speaks for the facility every
    /// time rather than whichever one a dictionary happened to yield first.
    func testTheFacilityRepresentativeIsStable() {
        let courts = [
            court("lm-1", name: "Long Meadow Park Basketball Court #1", facilityId: "f-lm"),
            court("lm-2", name: "Long Meadow Park Basketball Court #2", facilityId: "f-lm"),
        ]
        let counts = ["f-lm": 2]

        XCTAssertEqual(
            HomeViewModel.rankHotCourts(counts: counts, courts: courts, limit: 3)
                .map(\.court.id),
            ["lm-1"]
        )
        XCTAssertEqual(
            HomeViewModel.rankHotCourts(counts: counts, courts: courts, limit: 3)
                .map(\.court.id),
            ["lm-1"]
        )
    }
}

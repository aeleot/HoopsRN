import SwiftUI

/// The Home tab: what you're committed to, then where the action is.
///
/// The app used to open on the map. The map answers "where can I hoop?" — a
/// question you only have once you've already decided to go out. It can't
/// answer "am I signed up for something tonight?", which is the more common
/// reason to open the app at all, so that answer is what this screen leads
/// with.
///
/// **The redesign is about which element says it** (`UI_REDESIGN_BRIEF.md`
/// §5.1). The screen asked the right question and then buried the answer: the
/// largest type on it was a greeting carrying no information, and the run was
/// a 17pt line inside a box, under a 12pt label, below the stats card for
/// anyone who had stats. Now the run *is* the screen — the tip-off time set as
/// the hero numeral in a full-bleed band, the court under it, everything else
/// below a baseline.
///
/// Three things follow from that and are load-bearing rather than stylistic:
///
/// - **The band replaces the cards.** Five `cardChrome()` call sites became
///   none. What grouped by drawing edges now groups by layer — one region, one
///   hairline — which is also what survives Dynamic Type: at `.accessibility3`
///   the hero-to-caption size ratio falls from 3.4× to 2.3× (`Typography.swift`),
///   so a hierarchy carried only by point size is a third gone. Position is not.
/// - **The stats are a card below the answer, at row weight.** They are
///   self-reported counters the owner's client writes and they under-count by
///   construction, so they never take the hero's numeral tier — that is kept for
///   the answer and for a squad's record, which is a query over results two
///   leaders confirmed. (The redesign first cut them to one grey sentence; that
///   read as broken, and `StatsCard` records why it went back.)
/// - **Loading is not emptiness.** `hasLoaded` distinguishes "you have nothing
///   on" from "we haven't looked yet". Without it the empty state's call to
///   action flashed at people who were, in fact, signed up for something.
struct HomeTab: View {
    @StateObject private var viewModel: HomeViewModel
    @ObservedObject private var friendService: FriendService
    @ObservedObject private var squadService: SquadService

    /// Handed up rather than handled here — switching tabs is the shell's job,
    /// and Home is the one screen that wants to send you somewhere else.
    let onOpenProfile: () -> Void
    let onOpenRuns: () -> Void
    let onOpenMap: (Court?) -> Void

    init(
        authService: AuthService,
        courtService: CourtService,
        gameService: GameService,
        userProfileService: UserProfileService,
        friendService: FriendService,
        squadService: SquadService,
        onOpenProfile: @escaping () -> Void,
        onOpenRuns: @escaping () -> Void,
        onOpenMap: @escaping (Court?) -> Void
    ) {
        self.friendService = friendService
        self.squadService = squadService
        self.onOpenProfile = onOpenProfile
        self.onOpenRuns = onOpenRuns
        self.onOpenMap = onOpenMap
        _viewModel = StateObject(wrappedValue: HomeViewModel(
            authService: authService,
            courtService: courtService,
            gameService: gameService,
            userProfileService: userProfileService,
            friendService: friendService
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroBand

                VStack(alignment: .leading, spacing: Spacing.section) {
                    if let message = viewModel.errorMessage {
                        ErrorBanner(message: message)
                    }

                    hotCourts

                    if viewModel.incomingRequestCount > 0 {
                        friendRequestRow
                    }

                    if viewModel.hasStats {
                        yourStats
                    }
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.xxl)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .background(Color.hooprBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The band

    /// The hero (`UI_REDESIGN_BRIEF.md` M2). Full-bleed, grounded in
    /// `hooprHeroBand`, closed by a `hooprSeparatorStrong` baseline.
    ///
    /// The ground ignores the top safe area so the band runs under the status
    /// bar while its content stays below it — the band is *content*, not
    /// chrome, so it scrolls away with everything else rather than pinning.
    private var heroBand: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text(bandLabel)
                    .hooprType(.label)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .padding(.top, Spacing.xs)

                Spacer(minLength: 0)

                ProfileButton(
                    friendService: friendService,
                    squadService: squadService,
                    action: onOpenProfile
                )
            }

            bandAnswer
        }
        .padding(.horizontal, Spacing.pageMargin)
        // The profile button's slot — the same point on every tab.
        .padding(.top, ProfileButton.Slot.top)
        .padding(.bottom, Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.hooprHeroBand.ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hooprSeparatorStrong)
                .frame(height: 1)
        }
    }

    /// The label above the answer. It names the *day* when there is a run,
    /// because that is the one thing the hero numeral can't say on its own.
    private var bandLabel: String {
        guard viewModel.hasLoaded else { return "Tonight" }
        return viewModel.nextRun == nil ? "Tonight" : viewModel.nextRunDayLabel
    }

    @ViewBuilder
    private var bandAnswer: some View {
        if !viewModel.hasLoaded {
            loadingAnswer
        } else if let listing = viewModel.nextRun {
            Button(action: onOpenRuns) {
                bookedAnswer(listing)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Double tap to open your runs")
        } else {
            openAnswer
        }
    }

    // MARK: - The band's three states

    /// You're on a run. The time is the hero: the decision this screen
    /// supports is *when do I leave*, and the court answers *where* second.
    ///
    /// Everything under the time carries an icon (2026-09-22, at the user's
    /// request, for visibility): the court, the spots, the distance. An icon
    /// here is not decoration — it is what lets the line be scanned instead of
    /// read, which is the whole job of a screen glanced at on the way out.
    private func bookedAnswer(_ listing: LocalRunsViewModel.Listing) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(viewModel.nextRunTimeText)
                .hooprType(.numeral)
                .foregroundStyle(Color.hooprPrimaryText)
                .lineLimit(1)

            courtLine(listing)

            detailLine(for: listing)
                .padding(.top, Spacing.xs)

            openRunsCue
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Where. The glyph is a court rather than a pin: the line names *which
    /// court*, and a pin next to the distance below would say "location"
    /// twice.
    ///
    /// Aligned on the first text baseline, so when a long court name wraps —
    /// five in the dataset need three or four lines at `.accessibility3`
    /// (`HomeHeroMetrics`) — the glyph stays with the first line.
    private func courtLine(_ listing: LocalRunsViewModel.Listing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "sportscourt.fill")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprBrandAccent)
                .accessibilityHidden(true)

            Text(listing.courtName)
                .hooprType(.title)
                .foregroundStyle(Color.hooprPrimaryText)
                .lineLimit(HomeHeroMetrics.courtNameLineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    /// Your standing on the run, the spots, the distance — on a line that
    /// wraps rather than truncates.
    ///
    /// **This is where the HOSTING pill sat off the line.** The row mixed a
    /// 20pt numeral with 13pt captions and a capsule, and an `HStack` centred
    /// the capsule against the tall numeral while the caption beside it sat on
    /// its baseline — so the pill read as floating slightly high. Now every
    /// fact is the same size, the numbers carry their weight through weight
    /// and colour instead of point size, and `FlowLayout` centres each item on
    /// its line — which also means that when the line wraps, it wraps only the
    /// item that has to move.
    private func detailLine(for listing: LocalRunsViewModel.Listing) -> some View {
        FlowLayout(spacing: Spacing.lg, lineSpacing: Spacing.sm) {
            if let badge {
                Text(badge.text)
                    .hooprType(.badge)
                    .foregroundStyle(badge.foreground)
                    .padding(.horizontal, Spacing.Pill.horizontal)
                    .padding(.vertical, Spacing.Pill.vertical)
                    .background(Capsule().fill(badge.wash.opacity(0.12)))
            }

            spotsItem(listing.game)

            if let meters = listing.distanceMeters {
                detailItem(
                    symbol: "location.fill",
                    value: Distance.valueText(meters),
                    unit: Distance.unit,
                    spoken: "\(Distance.text(meters)) away"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func spotsItem(_ game: Game) -> some View {
        if game.isFull {
            detailItem(symbol: "person.2.fill", value: "Full", unit: nil, spoken: "Full")
        } else {
            detailItem(
                symbol: "person.2.fill",
                value: "\(game.openSlots)",
                unit: game.openSlots == 1 ? "spot left" : "spots left",
                spoken: game.spotsText
            )
        }
    }

    /// One icon, one fact. The number is set in the primary colour at a
    /// heavier weight and the unit beside it in secondary — so it reads as a
    /// number (the redesign's P2, and what a blind review of the first build
    /// asked for) without the point-size jump that knocked the pill off the
    /// line.
    private func detailItem(symbol: String, value: String, unit: String?, spoken: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)

            if let unit {
                Text("\(Text(value).fontWeight(.semibold).foregroundStyle(Color.hooprPrimaryText)) \(unit)")
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
            } else {
                Text(value)
                    .hooprType(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The band is a button, and until this line nothing said so.
    ///
    /// **A blind reviewer shown only the screenshots could not find a primary
    /// action anywhere on Home** — the band navigates to Runs, but it drew no
    /// affordance at all, so the most-opened screen in the app read as a
    /// scoreboard you cannot act on. The archetype this screen is built to
    /// (`UI_REDESIGN_BRIEF.md` §4, A1) requires one action in or under the
    /// band; the first build implemented everything but that clause.
    ///
    /// Deliberately a cue rather than a filled button: the action is
    /// *navigation to a decision*, not the decision itself — join, leave and
    /// cancel belong on Runs, which is the rationale `UI_SHELL.md` records for
    /// this card being read-only, and a filled button here would promise the
    /// commitment rather than the trip.
    private var openRunsCue: some View {
        HStack(spacing: 4) {
            Text("Your runs")
                .hooprType(.body)
                .fontWeight(.semibold)

            Image(systemName: "chevron.right")
                .hooprFont(12, weight: .semibold, maximumSize: 16)
        }
        .foregroundStyle(Color.hooprBrandAccent)
        .padding(.top, Spacing.xs)
    }

    /// Nothing booked. The answer is a phrase rather than a number, so it
    /// takes the display tier and the action that fixes it sits right under
    /// it — the hot list below the baseline says *where*, so this doesn't
    /// repeat it.
    private var openAnswer: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Nothing on tonight")
                .hooprType(.display)
                .foregroundStyle(Color.hooprPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onOpenMap(nil)
            } label: {
                Text("Find a court")
                    .hooprType(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.hooprOnBrand)
                    .padding(.horizontal, Spacing.xl)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .background(Color.hooprOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The listener hasn't answered yet. Two blocks at the hero's own
    /// proportions, so nothing moves when the answer lands — and the band
    /// keeps its height either way.
    private var loadingAnswer: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            placeholder(width: 180, height: 46)
            placeholder(width: 240, height: 30)
            placeholder(width: 140, height: 16)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Loading your next run")
    }

    private func placeholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.hooprHoverFill)
            .frame(width: width, height: height)
    }

    /// Matches `GameCard`'s priority order — your own relationship to the run
    /// says more than its status does — and its split of `foreground` from
    /// `wash`, for the reason recorded there.
    private var badge: (text: String, foreground: Color, wash: Color)? {
        if viewModel.isHostingNextRun { return ("Hosting", Color.hooprBrandAccent, Color.hooprOrange) }
        if viewModel.isWaitlistedOnNextRun { return ("Waitlist", Color.hooprSecondaryText, Color.hooprSecondaryText) }
        if viewModel.nextRun?.game.isFull == true { return ("Full", Color.hooprSecondaryText, Color.hooprSecondaryText) }
        return nil
    }

    // MARK: - Below the baseline

    /// Where the action is. Rows on the page rather than rows in a card: the
    /// list is already one group, and a box around it grouped nothing a
    /// heading didn't.
    @ViewBuilder
    private var hotCourts: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Tonight nearby")
                .hooprType(.label)
                .foregroundStyle(Color.hooprSecondaryText)

            if !viewModel.hasLoaded {
                Text("Checking what's on…")
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
            } else if viewModel.hotCourts.isEmpty {
                Text("Nothing scheduled anywhere today. Be the first.")
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.hotCourts.enumerated()), id: \.element.id) { index, hot in
                        if index > 0 {
                            Divider()
                                .overlay(Color.hooprBorder)
                        }

                        hotCourtRow(hot)
                    }
                }
            }
        }
    }

    private func hotCourtRow(_ hot: HomeViewModel.HotCourt) -> some View {
        Button {
            onOpenMap(hot.court)
        } label: {
            HStack(spacing: Spacing.md) {
                // The same scale the map pins use, so a court's colour means
                // the same thing on both screens.
                Circle()
                    .fill(CourtHeat.color(forGameCount: hot.gameCount))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hot.court.displayName)
                        .hooprType(.subhead)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(hot.court.city)
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprSecondaryText)
                }

                Spacer(minLength: Spacing.sm)

                // A count is content, not a caption — so it is set as one.
                // `gameCountText` still ceilings at "4+", because a row must
                // not promise a distinction the map pin can't draw.
                // The unit stays attached. The first build set a bare "1"
                // under no column header, so nothing on the screen said
                // whether it counted runs, players or miles — the number was
                // promoted and its meaning dropped on the way.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(gameCountText(hot.gameCount))
                        .hooprType(.headline)
                        .monospacedDigit()
                        .foregroundStyle(Color.hooprPrimaryText)

                    Text("today")
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hot.court.displayName), \(hot.court.city), \(gameCountText(hot.gameCount)) today")
    }

    /// The participation card, under the same kind of label as the hot list.
    ///
    /// Below the answer and below what's on tonight, because it looks back
    /// rather than forward — but a card again, not the sentence the redesign
    /// first cut it to. See `StatsCard` for why, and for why it can't break
    /// mid-word any more.
    private var yourStats: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Your stats")
                .hooprType(.label)
                .foregroundStyle(Color.hooprSecondaryText)

            StatsCard(
                completedCount: viewModel.completedGameCount,
                participationStreak: viewModel.participationStreak,
                lastCompletedText: viewModel.lastCompletedText
            )
        }
    }

    /// Someone is blocked on you. It was a card below the fold; it is a row
    /// above it now. Still navigation only — answering a request is a write,
    /// and writes belong on the screen that owns them.
    private var friendRequestRow: some View {
        Button(action: onOpenProfile) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .hooprType(.headline)
                    .foregroundStyle(Color.hooprBrandAccent)

                Text(requestText)
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Spacing.sm)

                Image(systemName: "chevron.right")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var requestText: String {
        viewModel.incomingRequestCount == 1
            ? "1 friend request waiting"
            : "\(viewModel.incomingRequestCount) friend requests waiting"
    }

    /// Caps at the same ceiling the heat ramp does — the colour runs out of
    /// luma past four, so a row that said "7" would claim a distinction the
    /// pin beside it can't draw.
    private func gameCountText(_ count: Int) -> String {
        count > CourtHeat.maxTier ? "\(CourtHeat.maxTier)+" : "\(count)"
    }
}

/// What the Home band's hero has to survive, and the measurement that proves
/// it does.
///
/// **This exists because a two-line cap looked fine and wasn't.** The court
/// name is the band's second line, set in the `title` role — 28pt, which
/// `UIFontMetrics` takes to 47pt at `.accessibility3`. At that size the page's
/// 362pt of content width holds about thirteen characters a line, and five
/// courts in the bundled dataset need **three or four lines**; the longest,
/// "Saint Thomas More Academy High School Campus", needs four. A
/// `.lineLimit(2)` truncated every one of them — invisibly, because the court
/// the screenshots happened to show was short enough to fit.
///
/// So the cap is `nil` and `HomeHeroMetricsTests` measures **every court in
/// the shipped dataset** against it. The band is the top of a scroll view; it
/// can grow. Clipping the screen's own answer is the one thing it must not do
/// (`UI_REVAMP_PROMPT.md` §2c, "reflow, don't clip").
///
/// The same shape as `ResultPillMetrics`: the number the layout depends on
/// lives beside the view that draws it, and a test asks whether it still
/// holds.
nonisolated enum HomeHeroMetrics {
    /// iPhone 17's 402pt width, less `Spacing.pageMargin` on each side. The
    /// device the evidence is captured on; a narrower phone would need more
    /// lines, not fewer, which is the direction `nil` already covers.
    static let contentWidth: CGFloat = 402 - (Spacing.pageMargin * 2)

    /// **Deliberately `nil`.** See above — any finite cap truncates a real
    /// court at `.accessibility3`.
    static let courtNameLineLimit: Int? = nil

    /// How many lines `text` needs in `role` at `category`, in `width`.
    ///
    /// Measured with the same `UIFont` the modifier resolves to, so this can't
    /// drift from what the screen actually draws.
    static func lineCount(
        of text: String,
        role: HooprTextRole,
        width: CGFloat = contentWidth,
        at category: UIContentSizeCategory
    ) -> Int {
        let size = HooprFontMetrics.scaledSize(role.size, maximumSize: role.maximumSize, at: category)
        let font = UIFont.systemFont(ofSize: size, weight: role.uiFontWeight)
        let box = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return max(1, Int((box.height / font.lineHeight).rounded()))
    }
}

#if DEBUG
import SwiftUI

/// Every token, colour role, type style, button, badge, avatar, card, glass
/// treatment and motion in the app, in isolation — **the single place to judge
/// the design system** (UI revamp Phase 6).
///
/// Reached by triple-tapping the version caption at the bottom of Profile, in a
/// debug build. Compiled out of release builds entirely: it is a tool for the
/// people building the app, not a screen for the people using it.
///
/// Everything here is the real component, fed plain values — nothing is
/// redrawn for the gallery, so what looks wrong here is wrong in the app. The
/// switches at the top set the appearance and the text size for everything
/// under them, which is how a pairing is checked in both appearances and at
/// `.accessibility3` without leaving the screen.
struct ComponentGallery: View {
    let onDone: () -> Void

    private enum Appearance: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        var id: String { rawValue }
    }

    private enum TextSize: String, CaseIterable, Identifiable {
        case standard = "Default"
        case large = "XXXL"
        case accessibility = "AX3"
        var id: String { rawValue }

        var size: DynamicTypeSize {
            switch self {
            case .standard:      return .large
            case .large:         return .xxxLarge
            case .accessibility: return .accessibility3
            }
        }
    }

    @State private var appearance: Appearance = .system
    @State private var textSize: TextSize = .standard
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    GallerySection("Colour roles") { ColourRoles() }
                    GallerySection("Type") { TypeRoles() }
                    GallerySection("Spacing") { SpacingScale() }
                    GallerySection("Buttons") { Buttons() }
                    GallerySection("Badges") { Badges() }
                    GallerySection("Avatars") { Avatars() }
                    GallerySection("Crests and form") { Crests() }
                    GallerySection("Cards and banners") { Cards() }
                    GallerySection("Bands") { Bands() }
                    GallerySection("Glass") { GlassDemo() }
                    GallerySection("Motion") { MotionDemos() }
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.vertical, Spacing.xl)
            }
            .background(Color.hooprBackground)
            .environment(\.colorScheme, scheme)
            .dynamicTypeSize(textSize.size)
            .safeAreaInset(edge: .top, spacing: 0) { switches }
            .navigationTitle("Components")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hooprBrandAccent)
                }
            }
        }
    }

    private var scheme: ColorScheme {
        switch appearance {
        case .system: return systemScheme
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Outside the scaled content, so the switches stay usable at AX3.
    private var switches: some View {
        VStack(spacing: Spacing.sm) {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Text size", selection: $textSize) {
                ForEach(TextSize.allCases) { Text($0.rawValue).tag($0) }
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.vertical, Spacing.sm)
        .background(Color.hooprBackground)
    }
}

// MARK: - Scaffolding

private struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .hooprType(.label)
                .foregroundStyle(Color.hooprSecondaryText)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A caption naming what's above or beside it.
private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .hooprType(.caption)
            .foregroundStyle(Color.hooprSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Colour

private struct ColourRoles: View {
    private let roles: [(String, Color)] = [
        ("hooprBackground", .hooprBackground),
        ("hooprSurface", .hooprSurface),
        ("hooprElevatedSurface", .hooprElevatedSurface),
        ("hooprGroupedBackground", .hooprGroupedBackground),
        ("hooprHeroBand", .hooprHeroBand),
        ("hooprFill", .hooprFill),
        ("hooprHoverFill", .hooprHoverFill),
        ("hooprBorder", .hooprBorder),
        ("hooprSeparatorStrong", .hooprSeparatorStrong),
        ("hooprPrimaryText", .hooprPrimaryText),
        ("hooprSecondaryText", .hooprSecondaryText),
        ("hooprOrange", .hooprOrange),
        ("hooprBrandAccent", .hooprBrandAccent),
        ("hooprDarkOrange", .hooprDarkOrange),
        ("hooprOnBrand", .hooprOnBrand),
        ("hooprRed", .hooprRed),
        ("hooprOnRed", .hooprOnRed),
        ("hooprOnCrest", .hooprOnCrest),
        ("hooprFormWin", .hooprFormWin),
        ("hooprFormLoss", .hooprFormLoss),
        ("hooprFormUnplayed", .hooprFormUnplayed),
        ("hooprOnFormResult", .hooprOnFormResult),
        ("hooprBrandWash", .hooprBrandWash),
        ("hooprBrandWatermark", .hooprBrandWatermark),
        ("hooprCourtGlow", .hooprCourtGlow),
        ("hooprShadow(0.25)", .hooprShadow(opacity: 0.25)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(roles, id: \.0) { name, color in
                    HStack(spacing: Spacing.md) {
                        swatch(color)
                        Text(name)
                            .hooprType(.body)
                            .monospaced()
                            .foregroundStyle(Color.hooprPrimaryText)
                    }
                }
            }

            strip("hooprHeat(tier:) 0…\(Color.hooprHeatMaxTier)",
                  (0...Color.hooprHeatMaxTier).map { Color.hooprHeat(tier: $0) })
            strip("hooprSquad(_:)", Squad.colorKeys.map { Color.hooprSquad($0) })
            strip("hooprSquadWash(_:)", Squad.colorKeys.map { Color.hooprSquadWash($0) })
        }
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: 44, height: 28)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hooprBorder, lineWidth: 1))
    }

    private func strip(_ title: String, _ colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 4) {
                ForEach(colors.indices, id: \.self) { swatch(colors[$0]) }
            }
            Caption(title)
        }
    }
}

// MARK: - Type and spacing

private struct TypeRoles: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(Array(HooprTextRole.allCases.enumerated()), id: \.offset) { _, role in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tip-off at 6:30")
                        .hooprType(role)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Caption("\(String(describing: role)) · \(Int(role.size))pt"
                            + (role.maximumSize.map { ", capped at \(Int($0))" } ?? ""))
                }
            }
        }
    }
}

private struct SpacingScale: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Spacing.scale, id: \.self) { step in
                HStack(spacing: Spacing.md) {
                    Rectangle()
                        .fill(Color.hooprBrandAccent)
                        .frame(width: step * 4, height: 12)
                    Caption("\(Int(step))pt")
                }
            }
            Caption("Bars drawn at 4× the step. pageMargin \(Int(Spacing.pageMargin)) · section \(Int(Spacing.section)) · cardPadding \(Int(Spacing.cardPadding))")
        }
    }
}

// MARK: - Controls

private struct Buttons: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(HooprButtonStyle.Role.allCases, id: \.self) { role in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Button("Invite") {}
                            .buttonStyle(.hooprFilled(.compact, role: role))
                        Button {} label: {
                            HStack(spacing: 6) {
                                Image(systemName: "map.fill")
                                Text("Find a court")
                            }
                        }
                        .buttonStyle(.hooprFilled(.regular, role: role))
                    }
                    Button("Queue up") {}
                        .buttonStyle(.hooprFilled(.large, role: role))
                    Caption("\(String(describing: role)) — compact, regular, large")
                }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Button {} label: { ProgressView() }
                    .buttonStyle(.hooprFilled(.large))
                    .disabled(true)
                Caption("Pending: full colour, a spinner, disabled")

                Button("Join") {}
                    .buttonStyle(.hooprFilled(.compact, fillsWidth: true))
                    .disabled(true)
                    .opacity(0.5)
                Caption("Blocked by another write: the caller dims it")

                Button("Sign In") {}
                    .buttonStyle(.hooprFilled(.large, shape: .form))
                // Verbatim, or SwiftUI reads the literal as Markdown and draws
                // the address as a blue link.
                Text(verbatim: "you@example.com")
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hooprFieldChrome(isFocused: false)
                Caption("Form shape: a submit under rounded fields (hooprFieldChrome)")
            }

            HStack(spacing: Spacing.sm) {
                GlassChip(symbolName: "flame.fill", label: "Games today", isActive: true) {}
                GlassChip(symbolName: "person.2.fill", label: "Open spots", isActive: false) {}
            }
            Caption("GlassChip — active, inactive")
        }
    }
}

private struct Badges: View {
    private let court = Court(
        id: "gallery", name: "Rockwood Park", latitude: 35.99, longitude: -78.9,
        address: "1 Main St", city: "Durham", hoops: 2, surface: "asphalt",
        isLit: true, isCovered: nil, access: .restricted, osmType: nil, osmId: nil
    )

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    ForEach(RunStatus.allCases, id: \.self) { HooprBadge($0, on: .surface) }
                }
                Caption("RunStatus on a card — \(Int(HooprBadge.washOnSurface * 100))% wash")
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardChrome()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    ForEach(RunStatus.allCases, id: \.self) { HooprBadge($0, on: .band) }
                }
                Caption("RunStatus on a band — \(Int(HooprBadge.washOnBand * 100))% wash")
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hooprHeroBand)

            HStack(spacing: Spacing.sm) {
                HooprBadge(text: "3 spots", style: .filled(foreground: .hooprOnBrand, fill: .hooprOrange))
                HooprBadge(text: "Full", style: .filled(foreground: .hooprSecondaryText, fill: .hooprFill))
            }
            Caption("Filled — the map's Now list")

            HStack(spacing: Spacing.lg) {
                HooprCountBadge(text: "3", count: 3)
                HooprCountBadge(text: "9+", count: 12)
                HooprNotificationDot()
            }
            Caption("Count badge (inbox), notification dot (profile button)")

            CourtBadges(court: court)
            Caption("CourtBadges — amenity chips, a caution outlined")
        }
    }
}

// MARK: - Identity

private struct Avatars: View {
    private let sizes: [(String, CGFloat)] = [
        ("inline", PlayerAvatar.Size.inline),
        ("roster", PlayerAvatar.Size.roster),
        ("row", PlayerAvatar.Size.row),
        ("sheet", PlayerAvatar.Size.sheet),
        ("profile", PlayerAvatar.Size.profile),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .bottom, spacing: Spacing.md) {
                ForEach(sizes, id: \.0) { _, diameter in
                    PlayerAvatar(initial: "J", diameter: diameter)
                }
            }
            HStack(alignment: .bottom, spacing: Spacing.md) {
                ForEach(sizes, id: \.0) { _, diameter in
                    PlayerAvatar(initial: "", diameter: diameter)
                }
            }
            Caption("PlayerAvatar.Size — " + sizes.map { "\($0.0) \(Int($0.1))" }.joined(separator: " · ") + ". Unresolved name below.")
        }
    }
}

private struct Crests: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(Squad.colorKeys.enumerated()), id: \.offset) { index, key in
                    SquadCrest(
                        iconKey: Squad.iconKeys[index % Squad.iconKeys.count],
                        colorKey: key,
                        size: SquadCrest.Size.row
                    )
                }
            }
            HStack(alignment: .bottom, spacing: Spacing.md) {
                ForEach([SquadCrest.Size.inline, SquadCrest.Size.pool, SquadCrest.Size.row,
                         SquadCrest.Size.card, SquadCrest.Size.hero], id: \.self) { size in
                    SquadCrest(iconKey: Squad.defaultIconKey, colorKey: Squad.defaultColorKey, size: size)
                }
            }
            FormGuide(form: [.win, .win, .loss, .win])
            SquadRecordLine(
                record: SeasonGame.Record(wins: 3, losses: 1),
                form: [.win, .win, .loss, .win]
            )
            Caption("Every crest colour; every crest size; the form dots; the record line")
        }
    }
}

// MARK: - Containers

private struct Cards: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("A card: hooprSurface, a hooprBorder edge, a soft shadow.")
                .hooprType(.body)
                .foregroundStyle(Color.hooprPrimaryText)
                .padding(Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardChrome()

            StatsCard(completedCount: 12, participationStreak: 3, lastCompletedText: "2 days ago")

            ErrorBanner(message: "Couldn't load your runs. Check your connection.", onRetry: {}, onDismiss: {})

            DividedRows(leadingInset: 0) {
                ForEach(["First row", "Second row", "Third row"], id: \.self) { title in
                    Text(title)
                        .hooprType(.subhead)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.md)
                }
            }
            Caption("cardChrome, StatsCard, ErrorBanner, DividedRows")
        }
    }
}

private struct Bands: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            band(.plain, "plain")
            band(.leading(.hooprBrandWash), "leading(hooprBrandWash) — Home, Runs, Login")
            band(.leading(.hooprSquadWash("red")), "leading(hooprSquadWash) — a squad's band")
            band(.centred(.hooprSquadWash("blue")), "centred(hooprSquadWash)")
        }
    }

    private func band(_ placement: HeroWash.Placement, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("This season")
                .hooprType(.label)
                .foregroundStyle(Color.hooprSecondaryText)
            Text("3–1")
                .hooprType(.numeral)
                .foregroundStyle(Color.hooprPrimaryText)
            Caption(title)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { HeroWash(placement: placement) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hooprSeparatorStrong).frame(height: 1)
        }
    }
}

private struct GlassDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack {
                HeroWash(placement: .centred(.hooprBrandWash))
                Image(systemName: "basketball.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .foregroundStyle(Color.hooprBrandWatermark)

                HooprGlassGroup(spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        GlassChip(symbolName: "flame.fill", label: "Games today", isActive: true) {}
                        Text("hooprGlass")
                            .hooprType(.subhead)
                            .foregroundStyle(Color.hooprPrimaryText)
                            .padding(.horizontal, Spacing.lg)
                            .frame(minHeight: 44)
                            .hooprGlass(interactive: false, in: Capsule())
                    }
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Caption("Glass over content: a grouped chip and a plain glass capsule. iOS 18 draws the material fallback.")
        }
    }
}

// MARK: - Motion

private struct MotionDemos: View {
    @State private var showsCard = false
    @State private var showsBadge = false
    @State private var count = 3
    @State private var confetti: UInt64?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Button(showsCard ? "Remove" : "Lift in") {
                    withAnimation(.hooprSwap) { showsCard.toggle() }
                }
                .buttonStyle(.hooprFilled(.compact, role: .secondary))

                Button(showsBadge ? "Hide badge" : "Pop badge") {
                    showsBadge.toggle()
                }
                .buttonStyle(.hooprFilled(.compact, role: .secondary))
            }

            ZStack(alignment: .topTrailing) {
                Group {
                    if showsCard {
                        Text("hooprLift — arrives lifting, leaves fading")
                            .hooprType(.body)
                            .foregroundStyle(Color.hooprPrimaryText)
                            .padding(Spacing.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardChrome()
                            .transition(.hooprLift)
                    }
                }
                .frame(minHeight: 60)

                if showsBadge {
                    HooprCountBadge(text: "2", count: 2)
                        .transition(.hooprPop)
                }
            }
            .animation(.hooprSnap, value: showsBadge)

            HStack(spacing: Spacing.md) {
                Image(systemName: "tray.fill")
                    .hooprFont(22)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .hooprBounce(onRiseOf: count)
                Text("\(count)")
                    .hooprType(.numeral)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .hooprNumericTransition(count)
                Stepper("Count", value: $count, in: 0...99)
                    .labelsHidden()
            }
            Caption("hooprNumericTransition rolls the digits; the tray bounces only on a rise")

            HStack(spacing: Spacing.lg) {
                ForEach(2...4, id: \.self) { games in
                    HStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(CourtHeat.color(forGameCount: games))
                            .frame(width: 10, height: 10)
                            .background {
                                if CourtHeat.glows(forGameCount: games) { CourtGlowHalo() }
                            }
                        Caption("\(games) runs")
                    }
                }
            }
            Caption("The busy-court glow, from \(CourtHeat.glowsFrom) runs. Holds still under Reduce Motion.")

            Button("Throw confetti") {
                confetti = UInt64.random(in: 0...UInt64.max)
            }
            .buttonStyle(.hooprFilled(.regular))
            Caption("ConfettiBurst — takes no touch; draws nothing under Reduce Motion")
        }
        .overlay {
            if let seed = confetti {
                ConfettiBurst(
                    colors: [.hooprSquad("red"), .hooprSquad("red"), .hooprOrange, .hooprSquad("gold")],
                    seed: seed,
                    onFinished: { confetti = nil }
                )
                .id(seed)
            }
        }
    }
}

#Preview {
    ComponentGallery(onDone: {})
}
#endif

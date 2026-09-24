import SwiftUI

/// The "Create a squad" form.
///
/// Four decisions: a name, a crest glyph, a crest colour, and a format. The
/// region isn't among them and deliberately isn't shown as a field: it's
/// derived from the leader's nearest court, there's exactly one right answer,
/// and a picker would invite someone to choose a pool they can't actually get
/// to. It's stated as context instead, so nobody has to wonder why their squad
/// only ever sees Durham opponents.
///
/// **Redesigned in UI revamp Phase 2b**. Four
/// cards became one form: **the crest preview is the hero** — the one crest in
/// the app that is feedback rather than decoration — centred at the top, large,
/// over the name as it will read; then Name, Crest and Format under `label`s on
/// the page. This is where a squad's colour (M3) is chosen, so the preview is
/// the thing the two grids are edited against.
struct CreateSquadSheet: View {
    @ObservedObject var viewModel: SquadViewModel

    let onCreated: (String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var iconKey = Squad.defaultIconKey
    @State private var colorKey = Squad.defaultColorKey
    @State private var format: SquadFormat = .threeVThree
    @State private var isSaving = false

    /// Suppresses the "too short" hint until the field has been used, so the
    /// form doesn't open already complaining.
    @State private var hasEdited = false

    private var nameProblem: SquadError? {
        Squad.validate(name: name)
    }

    private var canSave: Bool {
        nameProblem == nil && viewModel.regionForNewSquad != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    preview
                    nameSection
                    crestSection
                    formatSection
                    regionNote
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Color.hooprBackground)
            // The whole form is gated on the write, matching CreateGameSheet:
            // nothing can move out from under an in-flight create.
            .disabled(isSaving)
            .navigationTitle("Create a Squad")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create", action: create)
                            .fontWeight(.semibold)
                            .foregroundStyle(canSave ? Color.hooprBrandAccent : Color.hooprSecondaryText)
                            .disabled(!canSave)
                    }
                }
            }
        }
    }

    private func create() {
        Task {
            isSaving = true
            defer { isSaving = false }

            if let id = await viewModel.createSquad(
                name: name, format: format, iconKey: iconKey, colorKey: colorKey
            ) {
                onCreated(id)
            }
        }
    }

    // MARK: - Preview

    /// The crest as the form's hero, centred and larger than anywhere else in
    /// the app, with the name under it as it will read — so the two grids below
    /// are edited against the thing they're editing rather than against an
    /// abstract swatch.
    private var preview: some View {
        VStack(spacing: Spacing.sm) {
            // The one crest in the app that isn't merely decorative: it is the
            // only feedback that the two grids below did anything, and the
            // grids announce their own selections one at a time rather than the
            // pairing. Labelled rather than hidden for that reason alone.
            SquadCrest(iconKey: iconKey, colorKey: colorKey, size: Self.previewCrestSize)
                .accessibilityHidden(false)
                .accessibilityLabel("Crest: \(Self.iconName(iconKey)) in \(colorKey)")
                .padding(.bottom, Spacing.xs)

            Text(Squad.normalizedName(name).isEmpty ? "Your squad" : Squad.normalizedName(name))
                .hooprType(.title)
                .foregroundStyle(
                    Squad.normalizedName(name).isEmpty
                        ? Color.hooprSecondaryText
                        : Color.hooprPrimaryText
                )
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(format.displayName) · 0–0")
                .hooprType(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.md)
    }

    /// Half again the hero crest: this is the one screen where the crest is the
    /// subject. Every proportion inside `SquadCrest` derives from its size.
    private static let previewCrestSize: CGFloat = SquadCrest.Size.hero * 1.5

    // MARK: - Name

    /// The field's edge is `hooprSeparatorStrong` (3:1), as Login's are: a
    /// `hooprFill` ground on the white page is 1.09:1, so without it the one
    /// field on the form was barely drawn.
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            fieldTitle("Name")

            TextField("Rim Reapers", text: $name)
                .textFieldStyle(.plain)
                .hooprFont(16, maximumSize: 24)
                .foregroundStyle(Color.hooprPrimaryText)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color.hooprFill)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.hooprSeparatorStrong, lineWidth: 1)
                )
                .onChange(of: name) { _, _ in hasEdited = true }

            // The hint restates the bound the rules enforce, so a rejected name
            // is caught here rather than coming back as `permission-denied`.
            if hasEdited, let problem = nameProblem {
                Text(SquadService.message(
                    for: problem, whileDoing: "naming your squad", context: .write
                ))
                .hooprType(.caption)
                .foregroundStyle(Color.hooprRed)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(Squad.nameLengthRange.lowerBound)–\(Squad.nameLengthRange.upperBound) characters.")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Crest

    private var crestSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            fieldTitle("Crest")

            iconGrid
            colorGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(Squad.iconKeys, id: \.self) { key in
                Button {
                    iconKey = key
                } label: {
                    Image(systemName: key)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            key == iconKey ? Color.hooprPrimaryText : Color.hooprSecondaryText
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(key == iconKey ? Color.hooprFill : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    key == iconKey ? Color.hooprBrandAccent : Color.hooprBorder,
                                    lineWidth: key == iconKey ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.hooprPress)
                .accessibilityLabel(Self.iconName(key))
                .accessibilityAddTraits(key == iconKey ? [.isSelected] : [])
            }
        }
    }

    private var colorGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(Squad.colorKeys, id: \.self) { key in
                Button {
                    colorKey = key
                } label: {
                    Circle()
                        .fill(Color.hooprSquad(key))
                        .frame(width: 34, height: 34)
                        .overlay(
                            // The selected ring sits *outside* the swatch so it
                            // never covers the colour being chosen.
                            Circle()
                                .stroke(
                                    key == colorKey ? Color.hooprPrimaryText : Color.hooprBorder,
                                    lineWidth: key == colorKey ? 2 : 1
                                )
                        )
                        // 44pt tap target around a 34pt swatch, the same widening
                        // `ProfileButton` applies to its glyph.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hooprPress)
                .accessibilityLabel(key.capitalized)
                .accessibilityAddTraits(key == colorKey ? [.isSelected] : [])
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 10)]
    }

    /// A readable name for an SF Symbol key — "flame.fill" reads as "flame" to
    /// VoiceOver rather than as three words and a full stop.
    private static func iconName(_ key: String) -> String {
        key.replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
    }

    // MARK: - Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            fieldTitle("Format")

            HStack(spacing: Spacing.sm) {
                ForEach(SquadFormat.allCases, id: \.self) { option in
                    formatChip(option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 1v1 and 5v5 render as "soon" rather than being hidden: the schema
    /// carries `format` from day one, and showing what's coming is the honest
    /// version of a field with one option.
    private func formatChip(_ option: SquadFormat) -> some View {
        Button {
            guard option.isAvailable else { return }
            format = option
        } label: {
            VStack(spacing: 2) {
                Text(option.displayName)
                    .hooprType(.subhead)

                if !option.isAvailable {
                    Text("soon")
                        .hooprType(.caption)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .foregroundStyle(chipForeground(option))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(option == format ? Color.hooprOrange : Color.hooprFill)
            )
        }
        .buttonStyle(.hooprPress)
        .disabled(!option.isAvailable)
        .accessibilityLabel(
            option.isAvailable
                ? option.displayName
                : "\(option.displayName), coming soon"
        )
        .accessibilityAddTraits(option == format ? [.isSelected] : [])
    }

    private func chipForeground(_ option: SquadFormat) -> Color {
        if option == format { return .hooprOnBrand }
        return option.isAvailable ? .hooprPrimaryText : .hooprSecondaryText
    }

    // MARK: - Region

    /// Stated, not chosen. Matchmaking pools by city, and a squad that can't
    /// name one can't be created — so the absence is an explanation rather than
    /// a silently disabled button.
    @ViewBuilder
    private var regionNote: some View {
        if let region = viewModel.regionForNewSquad {
            Text("Your squad will queue for matches in \(region).")
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("We couldn't work out which city to queue you in, so a squad can't be created yet. Open the map once to let the app find your nearest court.")
                .hooprType(.caption)
                .foregroundStyle(Color.hooprRed)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .hooprType(.label)
            .foregroundStyle(Color.hooprSecondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

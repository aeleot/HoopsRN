import SwiftUI

/// The "Create a squad" form — plan §5, screen 3.
///
/// Four decisions: a name, a crest glyph, a crest colour, and a format. The
/// region isn't among them and deliberately isn't shown as a field: it's
/// derived from the leader's nearest court, there's exactly one right answer,
/// and a picker would invite someone to choose a pool they can't actually get
/// to. It's stated as context instead, so nobody has to wonder why their squad
/// only ever sees Durham opponents.
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
                VStack(spacing: 16) {
                    preview
                    nameCard
                    crestCard
                    formatCard
                    regionNote
                }
                .padding(Spacing.pageMargin)
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

    /// The crest at hero size with the name beside it, so the two grids below
    /// are edited against the thing they're editing rather than against an
    /// abstract swatch.
    private var preview: some View {
        HStack(spacing: 14) {
            // The one crest in the app that isn't merely decorative: it is the
            // only feedback that the two grids below did anything, and the
            // grids announce their own selections one at a time rather than the
            // pairing. Labelled rather than hidden for that reason alone.
            SquadCrest(iconKey: iconKey, colorKey: colorKey, size: SquadCrest.Size.hero)
                .accessibilityHidden(false)
                .accessibilityLabel("Crest: \(Self.iconName(iconKey)) in \(colorKey)")

            VStack(alignment: .leading, spacing: 4) {
                Text(Squad.normalizedName(name).isEmpty ? "Your squad" : Squad.normalizedName(name))
                    .hooprFont(20, weight: .bold)
                    .foregroundStyle(
                        Squad.normalizedName(name).isEmpty
                            ? Color.hooprSecondaryText
                            : Color.hooprPrimaryText
                    )
                    .lineLimit(2)

                Text("\(format.displayName) · 0–0")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.cardPadding)
        .cardChrome()
    }

    // MARK: - Name

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldTitle("Name")

            TextField("Rim Reapers", text: $name)
                .textFieldStyle(.plain)
                .hooprFont(16)
                .foregroundStyle(Color.hooprPrimaryText)
                .padding(12)
                .background(Color.hooprFill)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: name) { _, _ in hasEdited = true }

            // The hint restates the bound the rules enforce, so a rejected name
            // is caught here rather than coming back as `permission-denied`.
            if hasEdited, let problem = nameProblem {
                Text(SquadService.message(
                    for: problem, whileDoing: "naming your squad", context: .write
                ))
                .hooprFont(13)
                .foregroundStyle(Color.hooprRed)
            } else {
                Text("\(Squad.nameLengthRange.lowerBound)–\(Squad.nameLengthRange.upperBound) characters.")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardChrome()
    }

    // MARK: - Crest

    private var crestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldTitle("Crest")

            iconGrid
            colorGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardChrome()
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
                .buttonStyle(.plain)
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
                .buttonStyle(.plain)
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

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldTitle("Format")

            HStack(spacing: 8) {
                ForEach(SquadFormat.allCases, id: \.self) { option in
                    formatChip(option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardChrome()
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
                    .hooprFont(15, weight: .semibold)

                if !option.isAvailable {
                    Text("soon")
                        .hooprFont(11)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(chipForeground(option))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(option == format ? Color.hooprOrange : Color.hooprFill)
            )
        }
        .buttonStyle(.plain)
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
                .hooprFont(13)
                .foregroundStyle(Color.hooprSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("We couldn't work out which city to queue you in, so a squad can't be created yet. Open the map once to let the app find your nearest court.")
                .hooprFont(13)
                .foregroundStyle(Color.hooprRed)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .hooprFont(13, weight: .semibold)
            .foregroundStyle(Color.hooprSecondaryText)
            .textCase(.uppercase)
    }
}

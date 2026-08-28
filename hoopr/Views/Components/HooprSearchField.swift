import SwiftUI

/// The app's search field, in one place.
///
/// There were three near-identical copies of this chrome before it was
/// extracted — Friends, the home-court picker, and the map's new one would have
/// been a fourth. They differed only in height, capitalization and placeholder,
/// which is exactly the shape of thing that belongs in parameters rather than
/// in a copy.
///
/// Deliberately stateless. It renders a binding and reports intent, so the
/// screen around it keeps ownership of both the query and the focus — which is
/// what lets Friends put the field in a pinned section header while its results
/// scroll in the section body, and lets the map raise its sheet on focus.
struct HooprSearchField: View {
    /// Which surface the field is sitting on. This is a visual contract, not a
    /// style preference: a field on an opaque surface needs a hairline to
    /// separate it from that surface, and a field floating over the map needs
    /// glass because you look *past* map chrome.
    enum Ground {
        /// `hooprFill` with a hairline. For a field on a sheet or a form.
        case fill
        /// Liquid glass. For a field floating over the map.
        case glass
    }

    /// Mirrors the `.textInputAutocapitalization` cases the app actually uses.
    ///
    /// Declared rather than taking `TextInputAutocapitalization` directly
    /// because that type doesn't exist on every platform, and a stored property
    /// can't sit behind the `#if` the modifier already needs.
    enum Capitalization {
        case never
        case words
    }

    @Binding var text: String
    let placeholder: String

    /// Owned by the screen, so clearing the query can put the keyboard back and
    /// leaving the screen can take it away.
    var isFocused: FocusState<Bool>.Binding

    var ground: Ground = .fill
    /// 46 on Friends and the map, 48 in the home-court picker, which has a
    /// whole sheet to fill. Parameterised rather than unified: the map's row is
    /// height-budgeted against the sheet's detents.
    var height: CGFloat = 46
    var capitalization: Capitalization = .never

    /// Runs in place of simply emptying `text`. Callers whose clear does more
    /// than reset a string — dropping stale results, cancelling a request —
    /// pass their own; everyone else gets the obvious behaviour.
    var onClear: (() -> Void)?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    /// `nil` means no stroke at all.
    ///
    /// Glass already carries its own edge, so a hairline on top of it reads as
    /// a seam — only the focus ring earns a stroke there. On an opaque fill the
    /// hairline is what separates the field from the surface behind it, so it's
    /// always drawn.
    private var strokeColor: Color? {
        if isFocused.wrappedValue { return Color.hooprOrange }
        switch ground {
        case .fill:  return Color.hooprBorder
        case .glass: return nil
        }
    }

    var body: some View {
        row
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(background)
            .overlay {
                if let strokeColor {
                    shape.stroke(strokeColor, lineWidth: 1)
                }
            }
            // A clear or glass fill doesn't hit-test on its own, so without
            // this the tap target is the text only.
            .contentShape(shape)
    }

    @ViewBuilder
    private var background: some View {
        switch ground {
        case .fill:
            Color.hooprFill.clipShape(shape)
        case .glass:
            Color.clear.glassEffect(.regular.interactive(), in: shape)
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .hooprFont(15, weight: .medium, maximumSize: 20)
                .foregroundStyle(Color.hooprSecondaryText)

            TextField(placeholder, text: $text)
                .hooprFont(16, maximumSize: 22)
                .foregroundStyle(Color.hooprPrimaryText)
                .focused(isFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(
                    capitalization == .words ? .words : .never
                )
                #endif

            if !text.isEmpty {
                Button {
                    if let onClear {
                        onClear()
                    } else {
                        text = ""
                    }
                    // Clearing is a correction, not a dismissal — the keyboard
                    // stays up so the next query can be typed straight away.
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .hooprFont(15, maximumSize: 20)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
    }
}

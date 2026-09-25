import SwiftUI

// MARK: - One recipe for the five sheets
//
// UI revamp Phase 2b: these five sheets carried
// five card recipes — a filled panel here, an always-orange field border there
// — and two margins. Now every sheet sets its content on the page at
// `Spacing.pageMargin`, under the navigation bar, with no panel around it; a
// text field is `editSheetField(isFocused:)`; a heading is a `label`; a value
// the sheet exists to change is a numeral.

private extension View {
    /// Every field on these sheets. The chrome is `hooprFieldChrome`, shared
    /// with Login (UI revamp Phase 6); this name stays so the call sites read
    /// as what they are.
    func editSheetField(isFocused: Bool) -> some View {
        hooprFieldChrome(isFocused: isFocused)
    }
}

/// Edits the stored `userName`. Kept as a sheet rather than an inline field so
/// every editable attribute uses the same interaction as more are added.
struct EditUserNameSheet: View {
    @Binding var draft: String
    let isSaving: Bool
    let canSave: Bool
    let errorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("Your name", text: $draft, prompt: .hooprPrompt("Your name"))
                    .hooprFont(17, maximumSize: 24)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .focused($isFieldFocused)
                    .submitLabel(.done)
                    #if os(iOS) || os(visionOS)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    #endif
                    .editSheetField(isFocused: isFieldFocused)
                    .onSubmit { if canSave { onSave() } }

                if let errorMessage {
                    Text(errorMessage)
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.top, Spacing.lg)
            .background(Color.hooprBackground)
            .navigationTitle("Username")
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
                        Button("Save", action: onSave)
                            .fontWeight(.semibold)
                            .foregroundStyle(canSave ? Color.hooprBrandAccent : Color.hooprSecondaryText)
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear { isFieldFocused = true }
        }
    }
}

/// Picks a home court by search alone: a single field, with suggestions
/// appearing as you type. The bundled dataset runs to well over a hundred
/// courts, so an up-front list is noise — you already know which court is
/// yours, you just need to find it.
struct HomeCourtPickerSheet: View {
    let courts: [Court]
    let selectedCourtId: String?
    let isSaving: Bool
    let errorMessage: String?
    /// `nil` clears the home court.
    let onSelect: (String?) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// Shared with the map's search — see `CourtSearch`, which also explains
    /// why both of a court's name spellings are searched rather than just the
    /// stored one.
    private var suggestions: [Court] {
        CourtSearch.matches(courts, query: trimmedQuery)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                if let errorMessage {
                    Text(errorMessage)
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.pageMargin)
                        .padding(.bottom, Spacing.sm)
                }

                if trimmedQuery.isEmpty {
                    emptyState
                } else if suggestions.isEmpty {
                    message("No courts match “\(trimmedQuery)”.")
                } else {
                    suggestionList
                }
            }
            .background(Color.hooprBackground)
            .disabled(isSaving)
            .navigationTitle("Home Court")
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
                    if isSaving { ProgressView() }
                }
            }
            .onAppear { isSearchFocused = true }
        }
    }

    private var searchField: some View {
        HooprSearchField(
            text: $query,
            placeholder: "Search for your court",
            isFocused: $isSearchFocused,
            height: 48,
            capitalization: .words
        )
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.vertical, Spacing.lg)
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(suggestions) { court in
                    Button {
                        onSelect(court.id)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(court.displayName)
                                    .hooprType(.subhead)
                                    .foregroundStyle(Color.hooprPrimaryText)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(court.city)
                                    .hooprType(.caption)
                                    .foregroundStyle(Color.hooprSecondaryText)
                            }
                            Spacer()
                            if court.id == selectedCourtId {
                                Image(systemName: "checkmark")
                                    .hooprFont(15, weight: .semibold, maximumSize: 20)
                                    .foregroundStyle(Color.hooprBrandAccent)
                                    .accessibilityLabel("Your home court")
                            }
                        }
                        .padding(.horizontal, Spacing.pageMargin)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }

                    Rectangle()
                        .fill(Color.hooprBorder)
                        .frame(height: 1)
                        .padding(.horizontal, Spacing.pageMargin)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            message("Start typing to find your court.")

            // Only offered when there's something to undo, so the sheet stays
            // a search field in the common case.
            if selectedCourtId != nil {
                Button {
                    onSelect(nil)
                } label: {
                    Text("Remove home court")
                        .hooprType(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hooprRed)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .hooprType(.body)
            .foregroundStyle(Color.hooprSecondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.top, Spacing.xxl)
            .frame(maxWidth: .infinity)
    }
}

/// Edits how far out the nearby-courts list reaches. A slider rather than a
/// text field: the value is a coarse preference with hard bounds, so there's
/// nothing to validate and no keyboard to dismiss.
struct EditRadiusSheet: View {
    @Binding var radius: Double
    let isSaving: Bool
    let errorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    private var range: ClosedRange<Double> { UserProfile.preferredRadiusRange }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Nearby courts within")
                        .hooprType(.label)
                        .foregroundStyle(Color.hooprSecondaryText)

                    // The value this sheet exists to change, as the numeral.
                    // Tabular (the role's own), so the slider below doesn't
                    // shift as the number changes width mid-drag.
                    Text(UserProfile.radiusText(radius))
                        .hooprType(.numeral)
                        .foregroundStyle(Color.hooprPrimaryText)
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: Spacing.md) {
                    Text(UserProfile.radiusText(range.lowerBound))
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprSecondaryText)

                    // Steps by whole miles so the stored value always
                    // matches what the profile row renders.
                    Slider(value: $radius, in: range, step: 1)
                        .tint(Color.hooprBrandAccent)
                        .accessibilityLabel("Search radius in miles")

                    Text(UserProfile.radiusText(range.upperBound))
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprSecondaryText)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.top, Spacing.lg)
            .background(Color.hooprBackground)
            // Matches the court picker: the whole cycle is gated on `isSaving`,
            // so the value can't move out from under an in-flight write.
            .disabled(isSaving)
            .navigationTitle("Preferred Radius")
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
                        Button("Save", action: onSave)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.hooprBrandAccent)
                    }
                }
            }
        }
    }
}

/// Starts a password change.
///
/// **Deliberately collects no password.** Firebase Auth owns the credential —
/// this app has never held it and doesn't store it anywhere, so there is no
/// field here to type a new one into. What the sheet does is send the account's
/// address a one-time link; the new password is chosen on that link's page.
/// Being signed in *is* the authorisation, which is why no current password is
/// asked for either.
///
/// Two states, not three: explain-and-send, then sent. There's no "changed"
/// state to show because nothing tells this app when the link is used.
struct ChangePasswordSheet: View {
    let email: String
    let isSending: Bool
    let didSend: Bool
    let errorMessage: String?
    let onSend: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if didSend {
                    sent
                } else {
                    explanation

                    if let errorMessage {
                        Text(errorMessage)
                            .hooprType(.caption)
                            .foregroundStyle(Color.hooprRed)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    sendButton
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.top, Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hooprBackground)
            .navigationTitle("Password")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Gone once the mail is out: there's nothing left to back
                    // out of, and the link is valid whatever this sheet does.
                    if !didSend {
                        Button("Cancel", action: onCancel)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .disabled(isSending)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if didSend {
                        Button("Done", action: onDone)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.hooprBrandAccent)
                    }
                }
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: "envelope.badge")
                .hooprFont(22, maximumSize: 28)
                .foregroundStyle(Color.hooprBrandAccent)
                .accessibilityHidden(true)

            Text("We'll email a reset link to")
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)

            // Wraps rather than shrinking — it used `minimumScaleFactor(0.7)`,
            // which the app no longer uses anywhere — and breaks in the middle
            // only if even two lines won't hold it.
            Text(email)
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)

            Text("hoopsRN never stores your password, so you'll choose the new one on the link's page. Opening it signs you out on your other devices.")
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A `form` button, rounded like the sheets' fields (the user's call,
    /// 2026-09-24).
    private var sendButton: some View {
        Button(action: onSend) {
            if isSending {
                ProgressView()
            } else {
                Text("Send reset link")
            }
        }
        .buttonStyle(.hooprFilled(.large, shape: .form))
        .disabled(isSending)
    }

    private var sent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .hooprFont(40, maximumSize: 52)
                .foregroundStyle(Color.hooprBrandAccent)

            Text("Check your inbox")
                .hooprType(.title)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("We sent a link to \(email). It expires in an hour — start again from here if it does.")
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl)
    }
}

/// Picks the app's appearance. Unlike its siblings here, nothing is written to
/// Firestore — the choice lands in `UserDefaults` and takes effect immediately,
/// so the sheet itself repaints as you tap. That's why there's a Done button
/// and no Save: there is no in-flight state to guard and nothing to roll back.
struct AppearanceSheet: View {
    @Binding var preference: AppearancePreference
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ForEach(AppearancePreference.allCases) { option in
                    Button {
                        // Animated because the whole app recolours behind the
                        // sheet — an instant swap reads as a glitch.
                        withAnimation(.hooprSwap) {
                            preference = option
                        }
                    } label: {
                        row(for: option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == preference ? .isSelected : [])

                    if option != AppearancePreference.allCases.last {
                        Rectangle()
                            .fill(Color.hooprBorder)
                            .frame(height: 1)
                            .padding(.horizontal, Spacing.pageMargin)
                    }
                }

                Spacer()
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hooprBackground)
            .navigationTitle("Appearance")
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

    private func row(for option: AppearancePreference) -> some View {
        let isSelected = option == preference

        return HStack(spacing: 14) {
            Image(systemName: option.symbolName)
                .hooprFont(17, maximumSize: 22)
                .foregroundStyle(isSelected ? Color.hooprBrandAccent : Color.hooprSecondaryText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .hooprType(.subhead)
                    .foregroundStyle(Color.hooprPrimaryText)
                Text(option.subtitle)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .hooprFont(15, weight: .semibold, maximumSize: 20)
                    .foregroundStyle(Color.hooprBrandAccent)
            }
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    AppearanceSheet(preference: .constant(.system), onDone: {})
}

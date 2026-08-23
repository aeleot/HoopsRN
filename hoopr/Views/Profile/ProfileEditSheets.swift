import SwiftUI

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
            VStack(spacing: 16) {
                TextField("Your name", text: $draft)
                    .hooprFont(17, maximumSize: 24)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .focused($isFieldFocused)
                    .submitLabel(.done)
                    #if os(iOS) || os(visionOS)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    #endif
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.hooprFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.hooprOrange, lineWidth: 1)
                    )
                    .onSubmit { if canSave { onSave() } }

                if let errorMessage {
                    Text(errorMessage)
                        .hooprFont(13)
                        .foregroundStyle(Color.hooprRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(20)
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
                            .foregroundStyle(canSave ? Color.hooprOrange : Color.hooprSecondaryText)
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

    /// Enough to scroll through without rendering the whole dataset for a
    /// one-letter query.
    private static let maximumSuggestions = 25

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// Name matches rank above city matches, so typing a court's name doesn't
    /// bury it under everything in the same town.
    private var suggestions: [Court] {
        guard !trimmedQuery.isEmpty else { return [] }

        let nameMatches = courts.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
        }
        let cityOnlyMatches = courts.filter {
            !$0.name.localizedCaseInsensitiveContains(trimmedQuery)
                && $0.city.localizedCaseInsensitiveContains(trimmedQuery)
        }

        return Array((nameMatches + cityOnlyMatches).prefix(Self.maximumSuggestions))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                if let errorMessage {
                    Text(errorMessage)
                        .hooprFont(13)
                        .foregroundStyle(Color.hooprRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .hooprFont(15, weight: .medium, maximumSize: 20)
                .foregroundStyle(Color.hooprSecondaryText)

            TextField("Search for your court", text: $query)
                .hooprFont(16, maximumSize: 22)
                .foregroundStyle(Color.hooprPrimaryText)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.words)
                #endif

            if !query.isEmpty {
                Button {
                    query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .hooprFont(15, maximumSize: 20)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.hooprFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSearchFocused ? Color.hooprOrange : Color.hooprBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
                                    .hooprFont(16, weight: .medium)
                                    .foregroundStyle(Color.hooprPrimaryText)
                                    .multilineTextAlignment(.leading)
                                Text(court.city)
                                    .hooprFont(13)
                                    .foregroundStyle(Color.hooprSecondaryText)
                            }
                            Spacer()
                            if court.id == selectedCourtId {
                                Image(systemName: "checkmark")
                                    .hooprFont(15, weight: .semibold)
                                    .foregroundStyle(Color.hooprOrange)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }

                    Rectangle()
                        .fill(Color.hooprBorder)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
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
                        .hooprFont(15, weight: .medium)
                        .foregroundStyle(Color.hooprRed)
                }
            }

            Spacer()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .hooprFont(14)
            .foregroundStyle(Color.hooprSecondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 24)
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
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("Search radius for nearby courts")
                        .hooprFont(15)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(UserProfile.radiusText(radius))
                        .hooprFont(34, weight: .bold)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Fixed width digits, so the slider below doesn't
                        // shift as the number changes width mid-drag.
                        .monospacedDigit()

                    HStack(spacing: 12) {
                        Text(UserProfile.radiusText(range.lowerBound))
                            .hooprFont(13)
                            .foregroundStyle(Color.hooprSecondaryText)

                        // Steps by whole miles so the stored value always
                        // matches what the profile row renders.
                        Slider(value: $radius, in: range, step: 1)
                            .tint(Color.hooprOrange)
                            .accessibilityLabel("Search radius in miles")

                        Text(UserProfile.radiusText(range.upperBound))
                            .hooprFont(13)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                }
                .padding(16)
                .background(Color.hooprFill)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .hooprFont(13)
                        .foregroundStyle(Color.hooprRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(20)
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
                            .foregroundStyle(Color.hooprOrange)
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
            VStack(spacing: 20) {
                if didSend {
                    sent
                } else {
                    explanation

                    if let errorMessage {
                        Text(errorMessage)
                            .hooprFont(13)
                            .foregroundStyle(Color.hooprRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    sendButton
                }

                Spacer()
            }
            .padding(20)
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
                            .foregroundStyle(Color.hooprOrange)
                    }
                }
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "envelope.badge")
                .hooprFont(22, maximumSize: 28)
                .foregroundStyle(Color.hooprOrange)

            Text("We'll email a reset link to")
                .hooprFont(15)
                .foregroundStyle(Color.hooprSecondaryText)

            Text(email)
                .hooprFont(17, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text("hoopsRN never stores your password, so you'll choose the new one on the link's page. Opening it signs you out on your other devices.")
                .hooprFont(13)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hooprFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Group {
                if isSending {
                    ProgressView()
                        .tint(Color.hooprOnBrand)
                } else {
                    Text("Send reset link")
                        .hooprFont(17, weight: .semibold, maximumSize: 24)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Color.hooprOnBrand)
            .background(Color.hooprOrange)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isSending)
    }

    private var sent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .hooprFont(40, maximumSize: 52)
                .foregroundStyle(Color.hooprOrange)

            Text("Check your inbox")
                .hooprFont(22, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("We sent a link to \(email). It expires in an hour — start again from here if it does.")
                .hooprFont(14)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, 8)
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
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                            .padding(.horizontal, 20)
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
                        .foregroundStyle(Color.hooprOrange)
                }
            }
        }
    }

    private func row(for option: AppearancePreference) -> some View {
        let isSelected = option == preference

        return HStack(spacing: 14) {
            Image(systemName: option.symbolName)
                .hooprFont(17, maximumSize: 22)
                .foregroundStyle(isSelected ? Color.hooprOrange : Color.hooprSecondaryText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .hooprFont(16, weight: .medium)
                    .foregroundStyle(Color.hooprPrimaryText)
                Text(option.subtitle)
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprOrange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    AppearanceSheet(preference: .constant(.system), onDone: {})
}

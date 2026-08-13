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
                    .font(.system(size: 17))
                    .foregroundStyle(.black)
                    .focused($isFieldFocused)
                    .submitLabel(.done)
                    #if os(iOS) || os(visionOS)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    #endif
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.hooprLightGray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.hooprOrange, lineWidth: 1)
                    )
                    .onSubmit { if canSave { onSave() } }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.hooprRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.white)
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
                        .font(.system(size: 13))
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
            .background(Color.white)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.hooprSecondaryText)

            TextField("Search for your court", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(.black)
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
                        .font(.system(size: 15))
                        .foregroundStyle(Color.hooprSecondaryText)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.hooprLightGray)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSearchFocused ? Color.hooprOrange : Color.hooprBorderGray, lineWidth: 1)
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
                                Text(court.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.black)
                                    .multilineTextAlignment(.leading)
                                Text(court.city)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.hooprSecondaryText)
                            }
                            Spacer()
                            if court.id == selectedCourtId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.hooprOrange)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }

                    Rectangle()
                        .fill(Color.hooprBorderGray)
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
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.hooprRed)
                }
            }

            Spacer()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
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
                        .font(.system(size: 15))
                        .foregroundStyle(Color.hooprSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(UserProfile.radiusText(radius))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Fixed width digits, so the slider below doesn't
                        // shift as the number changes width mid-drag.
                        .monospacedDigit()

                    HStack(spacing: 12) {
                        Text(UserProfile.radiusText(range.lowerBound))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.hooprSecondaryText)

                        // Steps by whole miles so the stored value always
                        // matches what the profile row renders.
                        Slider(value: $radius, in: range, step: 1)
                            .tint(Color.hooprOrange)
                            .accessibilityLabel("Search radius in miles")

                        Text(UserProfile.radiusText(range.upperBound))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                }
                .padding(16)
                .background(Color.hooprLightGray)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.hooprRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.white)
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

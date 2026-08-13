import Combine
import Foundation

/// Backs the profile screen: identity display, editing the user-owned profile
/// fields, and signing out.
@MainActor
final class ProfileViewModel: ObservableObject {
    /// Which field the edit sheet is currently presenting, if any. Only
    /// user-editable fields appear here — `email` is owned by Firebase Auth
    /// and `dateJoined` is immutable by design.
    enum EditableField: String, Identifiable {
        case userName
        case homeCourt
        case preferredRadius

        var id: String { rawValue }

        var title: String {
            switch self {
            case .userName:       "Username"
            case .homeCourt:      "Home Court"
            case .preferredRadius: "Preferred Radius"
            }
        }
    }

    /// Stored profile name. `nil` until the first snapshot lands.
    @Published private(set) var userName: String?

    /// Sourced from Auth rather than the profile document, so it still renders
    /// if the profile hasn't been provisioned yet.
    @Published private(set) var email: String?

    @Published private(set) var homeCourtId: String?
    @Published private(set) var preferredRadius: Double?
    @Published private(set) var dateJoined: Date?
    @Published private(set) var courts: [Court] = []
    @Published private(set) var errorMessage: String?

    @Published var editingField: EditableField?
    @Published var nameDraft = ""
    @Published var radiusDraft = UserProfile.defaultPreferredRadius
    @Published private(set) var isSaving = false

    private let authService: AuthService
    private let userProfileService: UserProfileService
    private var cancellables = Set<AnyCancellable>()

    init(
        authService: AuthService,
        userProfileService: UserProfileService,
        courtService: CourtService
    ) {
        self.authService = authService
        self.userProfileService = userProfileService

        // `sink` with a weak capture rather than `assign(to:on: self)`, which
        // would retain self through self's own cancellable set.
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.email = user?.email
            }
            .store(in: &cancellables)

        userProfileService.$currentProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.userName = profile?.userName
                self?.homeCourtId = profile?.homeCourtId
                self?.preferredRadius = profile?.preferredRadius
                self?.dateJoined = profile?.createdAt
            }
            .store(in: &cancellables)

        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] courts in
                self?.courts = courts
            }
            .store(in: &cancellables)

        // Surface load/provisioning failures the service reports on its own,
        // not just the ones raised by actions taken on this screen.
        userProfileService.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)
    }

    // MARK: - Display values

    /// Resolved against the bundled court dataset. Falls back to a placeholder
    /// if the stored ID no longer matches a court — e.g. after a dataset
    /// rebuild drops one.
    var homeCourtName: String? {
        guard let homeCourtId else { return nil }
        return courts.first { $0.id == homeCourtId }?.name ?? "Unknown court"
    }

    var dateJoinedText: String? {
        dateJoined.map { Self.joinedDateFormatter.string(from: $0) }
    }

    /// `nil` until a *usable* radius is stored, so the row renders the default
    /// in placeholder styling. That reads honestly: 5 miles is what the map is
    /// searching with, but it isn't a choice the user has made.
    ///
    /// An out-of-range stored value (a `0` seeded in the console) counts as
    /// unset here for the same reason — showing "0 mi" would contradict the
    /// list, which is searching 5.
    var preferredRadiusText: String? {
        guard let preferredRadius,
              UserProfile.preferredRadiusRange.contains(preferredRadius) else { return nil }
        return UserProfile.radiusText(preferredRadius)
    }

    /// Shown in place of `preferredRadiusText` when nothing is stored.
    var defaultRadiusText: String {
        UserProfile.radiusText(UserProfile.defaultPreferredRadius)
    }

    private static let joinedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Editing

    var canSaveName: Bool {
        !nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    func beginEditing(_ field: EditableField) {
        errorMessage = nil
        switch field {
        case .userName:
            nameDraft = userName ?? ""
        case .preferredRadius:
            // Via `validRadius` so an out-of-range stored value doesn't seed
            // the slider below its own minimum, which would leave the thumb
            // pinned at 1 mi while the binding still read 0.
            radiusDraft = UserProfile.validRadius(preferredRadius)
        case .homeCourt:
            break
        }
        editingField = field
    }

    func cancelEditing() {
        editingField = nil
        nameDraft = ""
        radiusDraft = UserProfile.defaultPreferredRadius
        errorMessage = nil
    }

    func saveName() async {
        guard canSaveName else { return }

        isSaving = true
        do {
            try await userProfileService.updateUserName(nameDraft)
            editingField = nil
            nameDraft = ""
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
        isSaving = false
    }

    /// Pass `nil` to clear the home court.
    func saveHomeCourt(_ courtId: String?) async {
        guard !isSaving else { return }

        isSaving = true
        do {
            try await userProfileService.updateHomeCourt(courtId: courtId)
            editingField = nil
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
        isSaving = false
    }

    func saveRadius() async {
        guard !isSaving else { return }

        isSaving = true
        do {
            try await userProfileService.updatePreferredRadius(radiusDraft)
            editingField = nil
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
        isSaving = false
    }

    func signOut() {
        do {
            try authService.signOut()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't sign out. Try again."
        }
    }

    private static func message(for error: Error) -> String {
        guard let profileError = error as? UserProfileError else {
            return error.localizedDescription
        }

        switch profileError {
        case .notSignedIn:      return "You're signed out."
        case .emptyUserName:    return "Your name can't be blank."
        case .permissionDenied: return "Not allowed to save yet. Check the Firestore security rules."
        case .network:          return "Can't reach the network. Check your connection."
        case .decodingFailed:   return "Your profile is stored in an unexpected format."
        case .unknown:          return "Couldn't save your changes. Try again."
        }
    }
}

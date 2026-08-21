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
    }

    /// Stored profile name. `nil` until the first snapshot lands.
    @Published private(set) var userName: String?

    /// Sourced from Auth rather than the profile document, so it still renders
    /// if the profile hasn't been provisioned yet.
    @Published private(set) var email: String?

    /// The Auth uid, which is also the profile's document ID. From the same
    /// source and for the same reason as `email`: it resolves as soon as the
    /// session does, without waiting on a Firestore snapshot.
    @Published private(set) var userId: String?

    @Published private(set) var homeCourtId: String?
    @Published private(set) var preferredRadius: Double?
    @Published private(set) var dateJoined: Date?

    /// Starred from the map, never from this screen — the profile only counts
    /// them. Absent on profiles provisioned before favourites existed, which
    /// reads the same as none.
    @Published private(set) var favoriteCourtCount = 0
    @Published private(set) var courts: [Court] = []
    @Published private(set) var errorMessage: String?

    @Published var editingField: EditableField?
    @Published var nameDraft = ""
    @Published var radiusDraft = UserProfile.defaultPreferredRadius
    @Published private(set) var isSaving = false

    /// The password reset's state, kept apart from `isSaving`/`errorMessage`
    /// for the same reason appearance is kept out of `EditableField`: this is
    /// an Auth action, not a write to the profile document. Sharing the
    /// document flow's error would also surface it in the screen's bottom bar,
    /// which only hides itself while an `editingField` sheet is up.
    @Published private(set) var isSendingPasswordReset = false
    @Published private(set) var didSendPasswordReset = false
    @Published private(set) var passwordResetError: String?

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
                self?.userId = user?.id
            }
            .store(in: &cancellables)

        userProfileService.$currentProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.userName = profile?.userName
                self?.homeCourtId = profile?.homeCourtId
                self?.preferredRadius = profile?.preferredRadius
                self?.dateJoined = profile?.createdAt
                self?.favoriteCourtCount = profile?.favoriteCourtIds?.count ?? 0
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

    /// Resolved against the bundled court dataset. `nil` when nothing is
    /// stored, and also when the stored ID no longer matches a court — e.g.
    /// after a dataset rebuild drops one, which `homeCourtName` reports.
    private var homeCourt: Court? {
        guard let homeCourtId else { return nil }
        return courts.first { $0.id == homeCourtId }
    }

    /// `displayName`, not `name`: "Bethesda Park Basketball Court" is
    /// "Bethesda Park" on a row that already says Home Court, and the words it
    /// drops are the ones that push a real name past the width.
    ///
    /// Falls back to a placeholder when a court is stored but unresolvable, so
    /// the row doesn't read as "not set" when it is.
    var homeCourtName: String? {
        guard homeCourtId != nil else { return nil }
        return homeCourt?.displayName ?? "Unknown court"
    }

    /// The row's trailing detail. `nil` for an unresolvable court, where
    /// there's no city to name.
    var homeCourtCity: String? {
        homeCourt?.city
    }

    /// `nil` at zero so the row renders it in placeholder styling — nothing
    /// starred yet isn't a value worth reading as one.
    var favoriteCourtCountText: String? {
        favoriteCourtCount == 0 ? nil : "\(favoriteCourtCount)"
    }

    var favoriteCourtUnitText: String {
        favoriteCourtCount == 1 ? "court" : "courts"
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

    /// `.medium` ("Aug 7, 2026") rather than `.long`: the spelled-out month
    /// buys nothing on a row that truncates rather than wraps.
    private static let joinedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Editing

    var canSaveName: Bool {
        UserProfile.validate(userName: nameDraft) == nil && !isSaving
    }

    /// Why the draft name can't be saved, or `nil` when it can. Shown under the
    /// field so an over-long name is caught before the write rather than coming
    /// back as a server rejection.
    var nameDraftHint: String? {
        guard !nameDraft.isEmpty,
              let error = UserProfile.validate(userName: nameDraft) else { return nil }
        return Self.message(for: error)
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

    // MARK: - Password

    /// A reset is only offerable when there's an address to send it to. The
    /// profile screen expresses "can't" by rendering the card read-only, so
    /// this is what gates the card's `onEdit`.
    var canChangePassword: Bool {
        email?.isEmpty == false
    }

    func beginChangingPassword() {
        didSendPasswordReset = false
        passwordResetError = nil
    }

    func cancelChangingPassword() {
        didSendPasswordReset = false
        passwordResetError = nil
    }

    /// Sends the reset link and reports only whether it went out. There's no
    /// success to wait for beyond that — the password itself is changed later,
    /// on the link's page, and this app is never told when.
    func sendPasswordReset() async {
        guard let email, !isSendingPasswordReset else { return }

        isSendingPasswordReset = true
        passwordResetError = nil
        do {
            try await authService.sendPasswordResetEmail(to: email)
            didSendPasswordReset = true
        } catch {
            passwordResetError = Self.passwordResetMessage(for: error)
        }
        isSendingPasswordReset = false
    }

    /// Worded for this flow rather than shared with `LoginViewModel`'s mapping:
    /// the same `AuthError` means something different when you're signed in and
    /// asking for a link than it does at the sign-in form.
    ///
    /// `userNotFound` is listed for completeness only — the address comes from
    /// the session, and newer Firebase projects mask it behind a silent success
    /// anyway, to keep the endpoint from confirming who has an account.
    private static func passwordResetMessage(for error: Error) -> String {
        guard let authError = error as? AuthError else {
            return error.localizedDescription
        }

        switch authError {
        case .invalidEmail:     return "This account's email address isn't valid, so we can't send a link."
        case .userNotFound:     return "We couldn't find this account. Try signing out and back in."
        case .userDisabled:     return FailureText.accountDisabled
        case .network:          return FailureText.network
        case .tooManyRequests:  return "Too many attempts. Try again in a few minutes."
        case .notConfigured:    return FailureText.authNotConfigured
        case .providerDisabled: return FailureText.providerDisabled
        case .unknown(let description): return description
        default:                return "Couldn't send the reset link. Try again."
        }
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

        // Everything this screen raises comes from a write it just attempted,
        // so the write reading of `permissionDenied` is the right one — see
        // `UserProfileService.message(for:whileDoing:context:)`.
        switch profileError {
        case .unknown: return "Couldn't save your changes. Try again."
        default:
            return UserProfileService.message(
                for: profileError,
                whileDoing: "saving your changes",
                context: .write
            )
        }
    }
}

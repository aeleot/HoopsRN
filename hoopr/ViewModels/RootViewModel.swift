import Combine
import Foundation

/// Decides which top-level screen the app shows. Kept separate from `RootView`
/// so the gating rule is testable without rendering anything.
final class RootViewModel: ObservableObject {
    enum Destination: Equatable {
        /// Session state not yet known — holding here avoids flashing the login
        /// screen at users Firebase is about to restore a session for.
        case launching
        case login
        case main
    }

    @Published private(set) var destination: Destination = .launching

    private var cancellables = Set<AnyCancellable>()

    init(authService: AuthService) {
        authService.$currentUser
            .combineLatest(authService.$hasLoadedInitialState)
            .map { user, loaded -> Destination in
                guard loaded else { return .launching }
                return user == nil ? .login : .main
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            // `sink` with a weak capture rather than `assign(to:on: self)`,
            // which would retain self through self's own cancellable set —
            // the same reason `ProfileViewModel` and `LocalRunsViewModel`
            // avoid it.
            .sink { [weak self] destination in
                self?.destination = destination
            }
            .store(in: &cancellables)
    }
}

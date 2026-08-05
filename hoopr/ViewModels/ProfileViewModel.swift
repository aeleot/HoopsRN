import Combine
import Foundation

final class ProfileViewModel: ObservableObject {
    @Published private(set) var email: String?
    @Published private(set) var errorMessage: String?

    private let authService: AuthService
    private var cancellables = Set<AnyCancellable>()

    init(authService: AuthService) {
        self.authService = authService

        authService.$currentUser
            .map { $0?.email }
            .receive(on: DispatchQueue.main)
            .assign(to: \.email, on: self)
            .store(in: &cancellables)
    }

    func signOut() {
        do {
            try authService.signOut()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't sign out. Try again."
        }
    }
}

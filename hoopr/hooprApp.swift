import SwiftUI
import FirebaseCore

#if os(iOS) || os(visionOS)
/// Retained as the hook for future UIKit-level callbacks (APNs registration
/// for push notifications). Firebase itself is configured in `hooprApp.init()`
/// — see the note there — so this must not configure it a second time.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }
}
#endif

@main
struct hooprApp: App {
    #if os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #endif

    // Services are owned here for the app's lifetime and injected downward, so
    // every view model can be constructed with a stub in tests.
    @StateObject private var authService: AuthService
    @StateObject private var courtService = CourtService()
    @StateObject private var locationService = LocationService()
    @StateObject private var recentCourtsStore = RecentCourtsStore()
    /// Depend on `authService`, so all three are built in `init()` — a property
    /// initializer can't reference another property.
    @StateObject private var userProfileService: UserProfileService
    @StateObject private var gameService: GameService
    @StateObject private var friendService: FriendService

    /// Applied at the window root so it reaches every screen *and* every sheet
    /// presented from one — a `preferredColorScheme` set further down would
    /// leave modals resolving against the device appearance instead.
    @AppStorage(AppearancePreference.storageKey)
    private var appearance: AppearancePreference = .system

    init() {
        // Must run before any service is constructed: `AuthService.init()`
        // calls `Auth.auth()`, which traps if Firebase isn't configured yet.
        // Building the services here (rather than in property initializers,
        // which `StateObject` defers via @autoclosure) makes them eager, so
        // configuration can't be left to the app delegate's later callback.
        FirebaseApp.configure()

        let authService = AuthService()
        _authService = StateObject(wrappedValue: authService)
        _userProfileService = StateObject(wrappedValue: UserProfileService(authService: authService))
        _gameService = StateObject(wrappedValue: GameService(authService: authService))
        _friendService = StateObject(wrappedValue: FriendService(authService: authService))
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                authService: authService,
                courtService: courtService,
                locationService: locationService,
                userProfileService: userProfileService,
                gameService: gameService,
                friendService: friendService,
                recentCourtsStore: recentCourtsStore
            )
            .preferredColorScheme(appearance.colorScheme)
        }
    }
}

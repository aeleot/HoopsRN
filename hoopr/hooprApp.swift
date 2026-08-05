import SwiftUI
import FirebaseCore

#if os(iOS) || os(visionOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        return true
    }
}
#endif

@main
struct hooprApp: App {
    #if os(iOS) || os(visionOS)
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #else
    init() {
        FirebaseApp.configure()
    }
    #endif

    // Services are owned here for the app's lifetime and injected downward, so
    // every view model can be constructed with a stub in tests.
    @StateObject private var authService = AuthService()
    @StateObject private var courtService = CourtService()
    @StateObject private var locationService = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView(
                authService: authService,
                courtService: courtService,
                locationService: locationService
            )
        }
    }
}

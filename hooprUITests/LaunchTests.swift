import XCTest

/// The UI test target's one real test.
///
/// It replaces three generated files that asserted nothing — a `testExample`
/// that launched the app and stopped, a launch-time `measure` block, and a
/// screenshot-only test. All three passed unconditionally, including on a build
/// that crashed on launch, so they reported health they had never checked.
///
/// This asserts the one thing a UI test can check without a signed-in fixture:
/// the app launches, survives `FirebaseApp.configure()` and the eager service
/// construction in `hooprApp.init()`, and reaches the foreground. That is a
/// real regression guard — a misconfigured `GoogleService-Info.plist` or a trap
/// in `AuthService.init()` fails here rather than in someone's hands.
///
/// Deliberately no assertion about *which* screen appears: `RootView` gates on
/// Firebase restoring a cached session, so a fresh simulator lands on login and
/// a warm one lands on the tabs. Asserting either would be a flake.
final class LaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndStaysInTheForeground() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "The app should reach the foreground after launch"
        )

        // Still foregrounded a moment later, so a crash during Firebase
        // configuration or the first snapshot doesn't pass as a launch.
        XCTAssertEqual(
            app.state, .runningForeground,
            "The app should still be running once launch settles"
        )
    }
}

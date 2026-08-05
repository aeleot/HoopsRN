import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    private let authService: AuthService
    private let courtService: CourtService
    private let locationService: LocationService

    init(
        authService: AuthService,
        courtService: CourtService,
        locationService: LocationService
    ) {
        self.authService = authService
        self.courtService = courtService
        self.locationService = locationService

        #if os(iOS)
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        appearance.shadowColor = UIColor(red: 232 / 255, green: 232 / 255, blue: 232 / 255, alpha: 1)

        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.black.withAlphaComponent(0.6)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.black.withAlphaComponent(0.6),
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FindAMatchTab(courtService: courtService, locationService: locationService)
                .tag(0)
                .tabItem {
                    Label("Find a Match", systemImage: "map")
                }

            LocalGamesTab()
                .tag(1)
                .tabItem {
                    Label("Local Games", systemImage: "list.bullet")
                }

            ProfileTab(authService: authService)
                .tag(2)
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
        .tint(Color.hooprOrange)
    }
}

#Preview {
    MainTabView(
        authService: AuthService(),
        courtService: CourtService(),
        locationService: LocationService()
    )
}

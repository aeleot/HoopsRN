import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showProfile = false

    @ObservedObject private var authService: AuthService
    @ObservedObject private var userProfileService: UserProfileService
    private let courtService: CourtService
    private let locationService: LocationService

    private let tabs: [(String, String)] = [
        ("Court Map", "map"),
        ("Local Games", "list.bullet"),
        ("Find Match", "figure.run"),
    ]

    init(
        authService: AuthService,
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService
    ) {
        self.authService = authService
        self.courtService = courtService
        self.locationService = locationService
        self.userProfileService = userProfileService
    }

    var body: some View {
        // The profile takes over the whole screen — it has its own header and
        // back button — so it replaces this interface rather than rendering
        // inside it.
        if showProfile {
            ProfileView(
                authService: authService,
                userProfileService: userProfileService,
                courtService: courtService
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showProfile = false
                }
            }
            .transition(.opacity)
        } else {
            mainInterface
        }
    }

    private var mainInterface: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    HStack {
                        Text("Let's go hoop \(Text(userName).fontWeight(.bold)).")
                            .font(.system(size: 28))
                            .foregroundStyle(.black)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showProfile = true
                            }
                        } label: {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.hooprSecondaryText)
                        }
                        .accessibilityLabel("Profile")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                    HStack(spacing: 6) {
                        ForEach(0..<tabs.count, id: \.self) { index in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = index
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tabs[index].1)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(tabs[index].0)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity)
                                .background(
                                    selectedTab == index ? Color.hooprOrange : Color.hooprLightGray
                                )
                                .foregroundStyle(
                                    selectedTab == index ? .white : Color.hooprSecondaryText
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(height: geo.size.height * 0.14)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.hooprBorderGray)
                        .frame(height: 1)
                }
                .zIndex(1)

                ZStack {
                    FindAMatchTab(
                        courtService: courtService,
                        locationService: locationService,
                        userProfileService: userProfileService
                    )
                        .opacity(selectedTab == 0 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 0)

                    if selectedTab == 1 {
                        LocalGamesTab()
                    }

                    if selectedTab == 2 {
                        FindMatchTab()
                    }
                }
                .clipped()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Reads the stored profile name. Falls back to a neutral greeting while
    /// the first snapshot is in flight or before provisioning finishes.
    private var userName: String {
        userProfileService.currentProfile?.userName ?? "there"
    }
}

#Preview {
    let authService = AuthService()
    MainTabView(
        authService: authService,
        courtService: CourtService(),
        locationService: LocationService(),
        userProfileService: UserProfileService(authService: authService)
    )
}

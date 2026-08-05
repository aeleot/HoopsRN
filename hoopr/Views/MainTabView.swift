import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showProfile = false

    @ObservedObject private var authService: AuthService
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
        locationService: LocationService
    ) {
        self.authService = authService
        self.courtService = courtService
        self.locationService = locationService
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    HStack {
                        (Text("Let's go hoop ") + Text(userName).fontWeight(.bold) + Text("."))
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
                                .foregroundStyle(showProfile ? Color.hooprOrange : Color.hooprSecondaryText)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                    HStack(spacing: 6) {
                        ForEach(0..<tabs.count, id: \.self) { index in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = index
                                    showProfile = false
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
                                    !showProfile && selectedTab == index
                                        ? Color.hooprOrange
                                        : Color.hooprLightGray
                                )
                                .foregroundStyle(
                                    !showProfile && selectedTab == index
                                        ? .white
                                        : Color.hooprSecondaryText
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
                    if showProfile {
                        ProfileTab(authService: authService)
                    } else {
                        FindAMatchTab(courtService: courtService, locationService: locationService)
                            .opacity(selectedTab == 0 ? 1 : 0)
                            .allowsHitTesting(selectedTab == 0)

                        if selectedTab == 1 {
                            LocalGamesTab()
                        }

                        if selectedTab == 2 {
                            FindMatchTab()
                        }
                    }
                }
                .clipped()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Firebase only gives us an email, so the part before the @ stands in as a display name.
    private var userName: String {
        guard let email = authService.currentUser?.email,
              let localPart = email.split(separator: "@").first else {
            return "there"
        }
        return String(localPart)
    }
}

#Preview {
    MainTabView(
        authService: AuthService(),
        courtService: CourtService(),
        locationService: LocationService()
    )
}

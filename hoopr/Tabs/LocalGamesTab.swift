import SwiftUI

struct LocalGamesTab: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Local Games")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

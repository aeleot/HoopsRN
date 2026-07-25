import SwiftUI

struct ProfileTab: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Profile")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

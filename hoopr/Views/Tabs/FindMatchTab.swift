import SwiftUI

struct FindMatchTab: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Find Match")
                .hooprFont(18, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hooprBackground)
    }
}

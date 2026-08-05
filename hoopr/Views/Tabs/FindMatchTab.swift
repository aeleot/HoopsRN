import SwiftUI

struct FindMatchTab: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Find Match")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

import SwiftUI

/// One entry in the nearby-courts list: name and address on the left, distance
/// pinned right.
struct CourtRow: View {
    let nearbyCourt: NearbyCourt

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(nearbyCourt.court.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)

                if !nearbyCourt.court.address.isEmpty {
                    Text(nearbyCourt.court.address)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.hooprSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            Text(nearbyCourt.distanceText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

import SwiftUI

/// A hero band's ground with colour in it (UI revamp Phase 4): a
/// `MeshGradient` from a luminance-matched wash — `Color.hooprSquadWash`,
/// `Color.hooprBrandWash` — into the plain `hooprHeroBand`.
///
/// **Identity, not ornament.** §2d fails a gradient whose only job is looks;
/// each use of this one answers a question the band otherwise answers only
/// once you've read it. On Seasons and squad detail, *whose squad is this* —
/// more than one squad is legal, and a pushed screen looked the same for all of
/// them. On game day, *which of my squads is playing*. On Login, *what is this
/// app*, before a word of it is read.
///
/// **Every colour in the mesh has the band's luminance** (see
/// `Color.hooprSquadWash`), so the text, marks and baseline drawn over it keep
/// the ratios `ThemeContrastTests` asserts on the band. The test asserts them
/// again on each wash and on the mixes the mesh passes through, because two
/// equal-luminance colours mixed in sRGB land very slightly darker. The mesh
/// interpolates linearly (`smoothsColors: false`) so that nothing it draws
/// lies outside those mixes.
///
/// **Static.** Nothing drifts: Phase 3's rule that nothing animates on
/// appearance stands, and a mesh moving behind a record would compete with it.
struct HeroWash: View {
    enum Placement: Equatable {
        /// Colour from the leading edge — where the crest sits — easing into
        /// the plain band toward the trailing edge.
        case leading(Color)
        /// Colour rising from behind a centred mark: Login's glyph.
        case centred(Color)
        /// No colour: the plain band, for the moments before a squad has
        /// loaded.
        case plain
    }

    let placement: Placement

    /// The plain band is always underneath, and the mesh fades in over it.
    /// Swapping one for the other cross-faded two half-transparent layers
    /// over the page, and the band dipped nearly to black mid-way when a
    /// squad loaded (device, 2026-09-23).
    var body: some View {
        ZStack {
            ground
            wash
        }
    }

    @ViewBuilder
    private var wash: some View {
        switch placement {
        case .plain:
            EmptyView()
        case .leading(let wash):
            mesh(
                points: [
                    [0, 0], [0.55, 0], [1, 0],
                    [0, 0.5], [0.4, 0.6], [1, 0.5],
                    [0, 1], [0.45, 1], [1, 1],
                ],
                colors: [
                    wash, wash, ground,
                    wash, wash.mix(with: ground, by: 0.5), ground,
                    wash, ground, ground,
                ]
            )
        case .centred(let wash):
            mesh(
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.45], [0.5, 0.4], [1, 0.45],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    ground, wash.mix(with: ground, by: 0.5), ground,
                    wash.mix(with: ground, by: 0.5), wash, wash.mix(with: ground, by: 0.5),
                    ground, ground, ground,
                ]
            )
        }
    }

    private var ground: Color { Color.hooprHeroBand }

    private func mesh(points: [SIMD2<Float>], colors: [Color]) -> some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: colors,
            background: ground,
            smoothsColors: false
        )
    }
}

#Preview {
    VStack(spacing: 0) {
        HeroWash(placement: .leading(.hooprSquadWash("red"))).frame(height: 180)
        HeroWash(placement: .leading(.hooprSquadWash("blue"))).frame(height: 180)
        HeroWash(placement: .centred(.hooprBrandWash)).frame(height: 300)
    }
}

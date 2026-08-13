import Combine
import Foundation

extension Publisher where Output == UserProfile?, Failure == Never {
    /// The radius the nearby lists should search with, in miles.
    ///
    /// `FindAMatchViewModel` and `LocalRunsViewModel` both need exactly this —
    /// the stored preference coerced through `effectivePreferredRadius`, with
    /// the default standing in while signed out or before the first snapshot
    /// lands — and each carried a byte-identical copy of the pipeline,
    /// `removeDuplicates()` and `receive(on:)` included.
    ///
    /// Sharing the operator chain rather than the subscription keeps the
    /// isolation at each call site exactly as it was: the view models still
    /// reach for `userProfileService.$currentProfile` themselves, and only the
    /// derivation is common. What that buys is one place to change the
    /// fallback rule — previously it could be changed for the court list and
    /// silently not for the runs list.
    var preferredRadiusMiles: AnyPublisher<Double, Never> {
        map { $0?.effectivePreferredRadius ?? UserProfile.defaultPreferredRadius }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

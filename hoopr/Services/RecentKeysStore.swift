import Foundation

/// A short list of keys this device has seen, most recent first, kept in
/// `UserDefaults` — the one ring buffer behind `CelebratedWinsStore`,
/// `InboxDismissalsStore` and `RecentCourtsStore`, which used to carry three
/// copies of it.
///
/// On-device by design: each of those records what *this phone* has shown or
/// opened, which means nothing anywhere else and isn't worth a document. A
/// repeat moves to the front rather than duplicating, and anything past
/// `capacity` falls off — in every case the entries already aged out of use.
///
/// `defaults` is injectable so tests can run against a scratch suite instead
/// of the real one.
class RecentKeysStore {
    let capacity: Int

    private let defaults: UserDefaults
    private let storageKey: String

    init(storageKey: String, capacity: Int, defaults: UserDefaults = .standard) {
        self.storageKey = storageKey
        self.capacity = capacity
        self.defaults = defaults
    }

    /// Most recent first.
    var keys: [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    func contains(_ key: String) -> Bool {
        keys.contains(key)
    }

    /// Moves `key` to the front, whether or not it was already present, and
    /// drops whatever is past `capacity`. Returns the list as stored.
    @discardableResult
    func record(_ key: String) -> [String] {
        var updated = keys
        updated.removeAll { $0 == key }
        updated.insert(key, at: 0)
        let kept = Array(updated.prefix(capacity))
        defaults.set(kept, forKey: storageKey)
        return kept
    }
}

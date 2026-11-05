import Foundation

public struct SolvgramCacheMessageMetadata {
    public let deleted: Bool
    public let disappearing: Bool
    public let previousTexts: [String]
}


/// Synchronous in-memory reads, with ordered, coalesced persistence off the
/// Postbox/UI queues. One instance owns the archive in each process.
public final class SolvgramArchiveStorage {
    public static let shared = SolvgramArchiveStorage()
    private static let selfDestructingKey = "SolvgramSelfDestructingMessages"
    private static let storiesKey = "SolvgramAnonymouslyViewedStories"
    private static let orderKey = "SolvgramEditHistoryOrder"
    private static let storiesOrderKey = "SolvgramAnonymouslyViewedStoriesOrder"
    private static let maxMessages = 20_000
    private static let maxEdited = 5_000
    private var maxVersions: Int {
        let value = self.defaults.integer(forKey: "SolvgramCacheEditVersionLimit")
        return [10, 25, 50, 100].contains(value) ? value : 50
    }
    private static let maxHistoryBytes = 16 * 1024 * 1024

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let persistence = DispatchQueue(label: "app.solvgram.archive.persistence", qos: .utility)
    private var writeScheduled = false
    private var dirty: Set<Section> = []
    private enum Section { case deleted, disappearing, edits, stories }
    private var deleted: [String]
    private var deletedSet: Set<String>
    private var disappearing: [String]
    private var disappearingSet: Set<String>
    private var history: [String: [String]]
    private var order: [String]
    private var historyBytes: Int
    private var stories: [String: Int32]
    /// View order of `stories`, oldest first, so overflow evicts the oldest views.
    private var storiesOrder: [String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.deleted = Array((defaults.stringArray(forKey: SolvgramSettings.Key.deletedMessages) ?? []).suffix(Self.maxMessages))
        self.deletedSet = Set(self.deleted)
        self.disappearing = Array((defaults.stringArray(forKey: Self.selfDestructingKey) ?? []).suffix(Self.maxMessages))
        self.disappearingSet = Set(self.disappearing)
        self.history = defaults.dictionary(forKey: SolvgramSettings.Key.editHistory) as? [String: [String]] ?? [:]
        let history = self.history
        let savedOrder = defaults.stringArray(forKey: Self.orderKey) ?? []
        var seen = Set<String>()
        self.order = (savedOrder + history.keys.sorted()).filter { history[$0] != nil && seen.insert($0).inserted }
        self.historyBytes = 0
        self.stories = defaults.dictionary(forKey: Self.storiesKey) as? [String: Int32] ?? [:]
        // Older installs have no saved order: their entries count as oldest.
        let stories = self.stories
        var seenStories = Set<String>()
        let savedStoriesOrder = defaults.stringArray(forKey: Self.storiesOrderKey) ?? []
        let savedStoriesSet = Set(savedStoriesOrder)
        let unordered = stories.keys.filter { !savedStoriesSet.contains($0) }.sorted()
        self.storiesOrder = (unordered + savedStoriesOrder).filter { stories[$0] != nil && seenStories.insert($0).inserted }
        // Normalize old archives in memory, retaining the original text and
        // recent versions. The next mutation persists the bounded snapshot.
        for key in self.order {
            var texts = self.history[key] ?? []
            if texts.count > self.maxVersions {
                texts = [texts[0]] + texts.suffix(self.maxVersions - 1)
                self.history[key] = texts
            }
            self.historyBytes += texts.reduce(0) { $0 + $1.utf8.count }
        }
        self.trimHistory()
    }

    private func locked<T>(_ body: () -> T) -> T {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body()
    }

    public func isDeleted(_ key: String, legacyKey: String? = nil) -> Bool {
        return self.locked { self.deletedSet.contains(key) || legacyKey.map(self.deletedSet.contains) == true }
    }

    public func isDisappearing(_ key: String, legacyKey: String? = nil) -> Bool {
        return self.locked { self.disappearingSet.contains(key) || legacyKey.map(self.disappearingSet.contains) == true }
    }

    public func previousTexts(_ key: String, legacyKey: String? = nil) -> [String] {
        return self.locked { self.history[key] ?? legacyKey.flatMap { self.history[$0] } ?? [] }
    }

    public func markDeleted(_ keys: [String]) {
        self.locked {
            var changed = false
            for key in keys where self.deletedSet.insert(key).inserted {
                self.deleted.append(key)
                changed = true
            }
            guard changed else { return }
            if self.deleted.count > Self.maxMessages {
                let count = self.deleted.count - Self.maxMessages
                self.deletedSet.subtract(self.deleted.prefix(count))
                self.deleted.removeFirst(count)
            }
            self.schedule(.deleted)
        }
    }

    public func markDisappearing(_ key: String) {
        self.locked {
            guard self.disappearingSet.insert(key).inserted else { return }
            self.disappearing.append(key)
            if self.disappearing.count > Self.maxMessages {
                self.disappearingSet.remove(self.disappearing.removeFirst())
            }
            self.schedule(.disappearing)
        }
    }

    public func unmarkDisappearing(_ key: String, legacyKey: String? = nil) {
        self.locked {
            var changed = self.disappearingSet.remove(key) != nil
            if let legacyKey { changed = self.disappearingSet.remove(legacyKey) != nil || changed }
            guard changed else { return }
            self.disappearing.removeAll { !self.disappearingSet.contains($0) }
            self.schedule(.disappearing)
        }
    }

    /// Promote a legacy-keyed history under the new key exactly once, so an edit
    /// never leaves the same versions stored under both keys (which also drifted
    /// `historyBytes`). The content is unchanged, so its bytes stay accounted for;
    /// the order slot is reused in place. Must be called under `locked`.
    private func migrateLegacyHistory(_ key: String, _ legacyKey: String?) {
        guard self.history[key] == nil, let legacyKey, let texts = self.history[legacyKey] else { return }
        self.history[key] = texts
        self.history.removeValue(forKey: legacyKey)
        if let index = self.order.firstIndex(of: legacyKey) {
            self.order[index] = key
        } else {
            self.order.append(key)
        }
    }

    public func recordEdit(_ key: String, previousText: String, legacyKey: String? = nil) {
        guard !previousText.isEmpty else { return }
        self.locked {
            self.migrateLegacyHistory(key, legacyKey)
            let texts = self.history[key] ?? []
            guard texts.last != previousText else { return }
            if self.history[key] == nil {
                self.order.append(key)
            }
            // Keep only the original (first-sent) text and the most recent previous
            // version; the split shows the original, and no multi-version view exists.
            let kept = texts.first.map { [$0, previousText] } ?? [previousText]
            self.historyBytes += kept.reduce(0) { $0 + $1.utf8.count } - texts.reduce(0) { $0 + $1.utf8.count }
            self.history[key] = kept
            self.trimHistory()
            self.schedule(.edits)
        }
    }

    /// Includes legacy keys so existing on-device saves can be managed too.
    /// The engine validates their message IDs against the active account.
    public var editHistoryLimit: Int { self.locked { self.maxVersions } }

    public func setEditHistoryLimit(_ value: Int) {
        guard [10, 25, 50, 100].contains(value) else { return }
        self.locked {
            self.defaults.set(value, forKey: "SolvgramCacheEditVersionLimit")
            for key in self.order {
                guard let texts = self.history[key], texts.count > value else { continue }
                let kept = [texts[0]] + texts.suffix(value - 1)
                self.historyBytes -= texts.reduce(0) { $0 + $1.utf8.count } - kept.reduce(0) { $0 + $1.utf8.count }
                self.history[key] = kept
            }
            self.schedule(.edits)
        }
    }

    public func messageMetadata() -> [String: SolvgramCacheMessageMetadata] {
        self.locked {
            var result: [String: SolvgramCacheMessageMetadata] = [:]
            for key in self.deletedSet.union(self.disappearingSet).union(self.history.keys) {
                result[key] = SolvgramCacheMessageMetadata(deleted: self.deletedSet.contains(key), disappearing: self.disappearingSet.contains(key), previousTexts: self.history[key] ?? [])
            }
            return result
        }
    }

    public func removeEditHistory(_ keys: [String]) {
        self.locked {
            let keys = Set(keys)
            for key in keys {
                if let texts = self.history.removeValue(forKey: key) { self.historyBytes -= texts.reduce(0) { $0 + $1.utf8.count } }
            }
            self.order.removeAll { keys.contains($0) }
            self.schedule(.edits)
        }
    }

    public func removeMessageMetadata(_ keys: [String]) {
        self.locked {
            let keys = Set(keys)
            self.deletedSet.subtract(keys)
            self.deleted.removeAll { keys.contains($0) }
            self.disappearingSet.subtract(keys)
            self.disappearing.removeAll { keys.contains($0) }
            for key in keys {
                if let texts = self.history.removeValue(forKey: key) {
                    self.historyBytes -= texts.reduce(0) { $0 + $1.utf8.count }
                }
            }
            self.order.removeAll { keys.contains($0) }
            self.schedule(.deleted)
            self.schedule(.disappearing)
            self.schedule(.edits)
        }
    }

    /// Merge a server history without duplicating an overlapping local sequence.
    /// An empty former text is meaningful (a media caption can be added later).
    public func mergePreviousTexts(_ key: String, texts incoming: [String], legacyKey: String? = nil, incomingIsNewer: Bool = true) {
        guard !incoming.isEmpty else { return }
        self.locked {
            self.migrateLegacyHistory(key, legacyKey)
            let previous = self.history[key] ?? []
            let merged = solvgramMergeHistory(previous, incoming, limit: self.maxVersions, incomingIsNewer: incomingIsNewer).map { $0.text }
            guard merged != previous else { return }
            if self.history[key] == nil {
                self.order.append(key)
            } else {
                self.historyBytes -= previous.reduce(0) { $0 + $1.utf8.count }
            }
            self.history[key] = merged
            self.historyBytes += merged.reduce(0) { $0 + $1.utf8.count }
            self.trimHistory()
            self.schedule(.edits)
        }
    }

    private func trimHistory() {
        while self.order.count > Self.maxEdited || self.historyBytes > Self.maxHistoryBytes {
            guard !self.order.isEmpty else { break }
            let texts = self.history.removeValue(forKey: self.order.removeFirst()) ?? []
            self.historyBytes -= texts.reduce(0) { $0 + $1.utf8.count }
        }
    }

    public func storiesViewedAnonymously(_ key: String, legacyKey: String? = nil) -> Bool {
        return self.locked { self.stories[key] != nil || legacyKey.flatMap { self.stories[$0] } != nil }
    }

    public func setStoriesViewedAnonymously(_ key: String, maxId: Int32, anonymously: Bool, legacyKey: String? = nil) {
        let changed: Bool = self.locked {
            if anonymously {
                guard (self.stories[key] ?? 0) < maxId else { return false }
                self.stories[key] = maxId
                // Most recently viewed goes last; overflow evicts the oldest views.
                self.storiesOrder.removeAll { $0 == key }
                self.storiesOrder.append(key)
                if self.storiesOrder.count > Self.maxMessages {
                    let overflow = self.storiesOrder.count - Self.maxMessages
                    for old in self.storiesOrder.prefix(overflow) {
                        self.stories.removeValue(forKey: old)
                    }
                    self.storiesOrder.removeFirst(overflow)
                }
            } else {
                var removed = false
                for candidate in [key, legacyKey].compactMap({ $0 }) {
                    // An older ordinary view must not erase a newer anonymous view.
                    if let storedId = self.stories[candidate], maxId >= storedId {
                        self.stories.removeValue(forKey: candidate)
                        self.storiesOrder.removeAll { $0 == candidate }
                        removed = true
                    }
                }
                guard removed else { return false }
            }
            self.schedule(.stories)
            return true
        }
        if changed {
            // Never deliver observers under the archive lock. UI reads the in-memory value immediately.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("SolvgramAnonymousStoryViewsDidChange"), object: nil, userInfo: ["key": key])
            }
        }
    }

    /// Anonymous story views of one account (and unscoped ones from older builds): their count and
    /// approximate stored size.
    public func storyViewStatistics(accountPeerId: Int64) -> (count: Int, bytes: Int64) {
        return self.locked {
            let keys = self.stories.keys.filter { Self.storyKey($0, belongsTo: accountPeerId, peerId: nil) }
            return (keys.count, Int64(keys.reduce(0) { $0 + $1.utf8.count + 8 }))
        }
    }

    /// Forget anonymous story views of one account, all or of one peer. The gray rings go away.
    public func removeStoryViews(accountPeerId: Int64, peerId: Int64? = nil) {
        let removed: [String] = self.locked {
            let keys = self.stories.keys.filter { Self.storyKey($0, belongsTo: accountPeerId, peerId: peerId) }
            guard !keys.isEmpty else { return [] }
            for key in keys { self.stories.removeValue(forKey: key) }
            let set = Set(keys)
            self.storiesOrder.removeAll { set.contains($0) }
            self.schedule(.stories)
            return keys
        }
        guard !removed.isEmpty else { return }
        DispatchQueue.main.async {
            for key in removed {
                NotificationCenter.default.post(name: Notification.Name("SolvgramAnonymousStoryViewsDidChange"), object: nil, userInfo: ["key": key])
            }
        }
    }

    /// "account:peer", or a bare "peer" written by builds that stored no account.
    private static func storyKey(_ key: String, belongsTo accountPeerId: Int64, peerId: Int64?) -> Bool {
        let parts = key.split(separator: ":")
        if parts.count == 2 {
            guard Int64(parts[0]) == accountPeerId else { return false }
            return peerId.map { Int64(parts[1]) == $0 } ?? true
        }
        return parts.count == 1 && (peerId.map { Int64(parts[0]) == $0 } ?? true)
    }

    /// Called under lock. A single serial writer prevents an older snapshot from
    /// overwriting a newer mutation. Repeated no-op updates never schedule a write.
    private func schedule(_ section: Section) {
        self.dirty.insert(section)
        guard !self.writeScheduled else { return }
        self.writeScheduled = true
        self.persistence.async {
            let values: [String: Any] = self.locked {
                var values: [String: Any] = [:]
                for section in self.dirty {
                    switch section {
                    case .deleted: values[SolvgramSettings.Key.deletedMessages] = self.deleted
                    case .disappearing: values[Self.selfDestructingKey] = self.disappearing
                    case .edits:
                        values[SolvgramSettings.Key.editHistory] = self.history
                        values[Self.orderKey] = self.order
                    case .stories:
                        values[Self.storiesKey] = self.stories
                        values[Self.storiesOrderKey] = self.storiesOrder
                    }
                }
                self.dirty.removeAll()
                self.writeScheduled = false
                return values
            }
            for (key, value) in values { self.defaults.set(value, forKey: key) }
        }
    }

    /// Drain pending writes before backgrounding, termination or restarting.
    public func flush() { self.persistence.sync {} }
}

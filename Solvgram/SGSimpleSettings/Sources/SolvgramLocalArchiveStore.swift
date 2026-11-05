import Foundation

public enum SolvgramCachePreferences {
    public static var editHistoryLimit: Int {
        let value = UserDefaults.standard.integer(forKey: "SolvgramCacheEditVersionLimit")
        return [10, 25, 50, 100].contains(value) ? value : 50
    }
    public static var downloadMedia: Bool {
        get { UserDefaults.standard.object(forKey: "SolvgramCacheDownloadMedia") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "SolvgramCacheDownloadMedia") }
    }
}

public enum SolvgramCacheCategory: String, Codable, CaseIterable, Hashable {
    case deleted, edits, disappearing, stories, media
    /// The categories kept with messages; stories are anonymous story views.
    public static let messageCategories: Set<SolvgramCacheCategory> = [.deleted, .edits, .disappearing, .media]
}


public struct SolvgramCacheCategoryStatistics {
    public var count: Int
    public var bytes: Int64
    public init(count: Int = 0, bytes: Int64 = 0) { self.count = count; self.bytes = bytes }
}

public struct SolvgramDeviceCacheStatistics {
    public var categories: [SolvgramCacheCategory: SolvgramCacheCategoryStatistics]
    public var totalBytes: Int64
    public init(categories: [SolvgramCacheCategory: SolvgramCacheCategoryStatistics] = [:], totalBytes: Int64 = 0) {
        self.categories = categories; self.totalBytes = totalBytes
    }
}

public struct SolvgramLocalArchiveAttachment: Codable, Equatable {
    public var id: String
    public var name: String
    public var kind: String
    public var size: Int64
    public var relativePath: String?

    public init(id: String, name: String, kind: String, size: Int64, relativePath: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.size = size; self.relativePath = relativePath
    }
}

public struct SolvgramLocalArchiveItem: Codable, Equatable {
    public var chatId: String
    public var messageId: Int32
    public var chatTitle: String
    public var author: String
    public var timestamp: Int32
    public var updatedAt: Date
    public var text: String
    public var previousTexts: [String]
    public var previousTextDates: [Double]?
    public var deleted: Bool
    public var disappearing: Bool
    public var attachments: [SolvgramLocalArchiveAttachment]
    public var messageTl: Data
    public var id: String { "\(self.chatId)_\(self.messageId)" }

    public init(chatId: String, messageId: Int32, chatTitle: String, author: String, timestamp: Int32, updatedAt: Date, text: String, previousTexts: [String], deleted: Bool, disappearing: Bool, attachments: [SolvgramLocalArchiveAttachment] = [], messageTl: Data = Data(), previousTextDates: [Double]? = nil) {
        self.chatId = chatId; self.messageId = messageId; self.chatTitle = chatTitle; self.author = author
        self.timestamp = timestamp; self.updatedAt = updatedAt; self.text = text; self.previousTexts = previousTexts
        self.deleted = deleted; self.disappearing = disappearing; self.attachments = attachments; self.messageTl = messageTl; self.previousTextDates = previousTextDates
    }
}

/// Permanent, account-scoped Application Support files. MediaBox/cache eviction
/// cannot remove these copies. A page is acknowledged only after these writes.
public final class SolvgramLocalArchiveStore {
    private static let registryLock = NSLock()
    private static var registry: [String: SolvgramLocalArchiveStore] = [:]
    public static func shared(accountId: String) -> SolvgramLocalArchiveStore {
        self.registryLock.lock(); defer { self.registryLock.unlock() }
        if let store = self.registry[accountId] { return store }
        let store = SolvgramLocalArchiveStore(accountId: accountId)
        self.registry[accountId] = store
        return store
    }

    private let root: URL
    private let lock = NSLock()
    private let fm = FileManager.default
    private var resourceIndex: [String: SolvgramLocalArchiveAttachment]?
    private struct ClearState: Codable {
        var date: Date
        var pending: Bool
        // nil is a full clear, including jobs created by older versions.
        var categories: [SolvgramCacheCategory]?
        var previousFullDate: Date?
        var cutoffs: [String: Date]?
    }

    public init(accountId: String, baseDirectory: URL? = nil) {
        precondition(Int64(accountId) != nil)
        let base = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SolvgramLocalArchive", isDirectory: true)
        self.root = base.appendingPathComponent(accountId, isDirectory: true)
    }

    private func prepare() throws {
        try self.fm.createDirectory(at: self.root.appendingPathComponent("records"), withIntermediateDirectories: true)
        try self.fm.createDirectory(at: self.root.appendingPathComponent("media"), withIntermediateDirectories: true)
        #if os(iOS)
        for url in [self.root, self.root.appendingPathComponent("records"), self.root.appendingPathComponent("media")] {
            try self.fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        }
        #endif
    }

    private func manifest(_ id: String) throws -> URL {
        let parts = id.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2, Int64(parts[0]) != nil, Int32(parts[1]) != nil else { throw CocoaError(.fileReadInvalidFileName) }
        return self.root.appendingPathComponent("records").appendingPathComponent(id + ".json")
    }

    private func mediaURL(_ path: String) -> URL? {
        guard path.hasPrefix("media/"), !path.contains(".."), !path.contains("\\") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "media" else { return nil }
        let directory = self.root.appendingPathComponent("media", isDirectory: true)
        guard let attributes = try? self.fm.attributesOfItem(atPath: directory.path),
              attributes[.type] as? FileAttributeType == .typeDirectory else { return nil }
        let url = directory.appendingPathComponent(String(parts[1]))
        // Both new and existing files are direct children of our own media
        // directory. Never follow a manifest path or a symbolic link elsewhere.
        if let attributes = try? self.fm.attributesOfItem(atPath: url.path),
           attributes[.type] as? FileAttributeType != .typeRegular { return nil }
        return url
    }

    private func read(_ id: String) throws -> SolvgramLocalArchiveItem? {
        let url = try self.manifest(id)
        guard self.fm.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(SolvgramLocalArchiveItem.self, from: Data(contentsOf: url))
    }

    public func items() throws -> [SolvgramLocalArchiveItem] {
        self.lock.lock(); defer { self.lock.unlock() }
        // Tolerate a single corrupt/partial manifest rather than hiding the whole
        // archive; directory-level IO errors still propagate (they are outside the
        // per-record loop).
        return try self.readItems(allowCorruptRecords: true)
    }

    private func readItems(allowCorruptRecords: Bool = false) throws -> [SolvgramLocalArchiveItem] {
        let folder = self.root.appendingPathComponent("records")
        guard self.fm.fileExists(atPath: folder.path) else { self.resourceIndex = [:]; return [] }
        let urls = try self.fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var items: [SolvgramLocalArchiveItem] = []
        for url in urls where url.pathExtension == "json" {
            do {
                var item = try JSONDecoder().decode(SolvgramLocalArchiveItem.self, from: Data(contentsOf: url))
                let limit = SolvgramCachePreferences.editHistoryLimit
                if item.previousTexts.count > limit {
                    let indices = [0] + Array(item.previousTexts.indices.suffix(limit - 1))
                    item.previousTexts = indices.map { item.previousTexts[$0] }
                    item.previousTextDates = item.previousTextDates.map { dates in indices.compactMap { $0 < dates.count ? dates[$0] : nil } }
                    try JSONEncoder().encode(item).write(to: url, options: .atomic)
                }
                items.append(item)
            } catch { if !allowCorruptRecords { throw error } }
        }
        items.sort { a, b in a.updatedAt == b.updatedAt ? a.id < b.id : a.updatedAt > b.updatedAt }
        var index: [String: SolvgramLocalArchiveAttachment] = [:]
        for item in items {
            for file in item.attachments where file.relativePath != nil { index[file.id] = file }
        }
        self.resourceIndex = index
        return items
    }

    public func fileURL(for attachment: SolvgramLocalArchiveAttachment) -> URL? {
        self.lock.lock(); defer { self.lock.unlock() }
        guard (try? self.clearState()?.pending) != true else { return nil }
        guard let path = attachment.relativePath, let url = self.mediaURL(path),
              let size = (try? self.fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
              size.int64Value == attachment.size else { return nil }
        return url
    }

    public func fileURL(resourceId: String) -> URL? {
        self.lock.lock(); defer { self.lock.unlock() }
        guard (try? self.clearState()?.pending) != true else { return nil }
        if self.resourceIndex == nil { _ = try? self.readItems() }
        guard let file = self.resourceIndex?[resourceId], let path = file.relativePath,
              let url = self.mediaURL(path),
              let size = (try? self.fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
              size.int64Value == file.size else { return nil }
        return url
    }

    private func clearState() throws -> ClearState? {
        let url = self.root.appendingPathComponent("clear.json")
        guard self.fm.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ClearState.self, from: Data(contentsOf: url))
    }

    public func clearDate() throws -> Date? {
        self.lock.lock(); defer { self.lock.unlock() }
        guard let state = try self.clearState() else { return nil }
        return state.categories == nil ? state.date : state.previousFullDate
    }

    public func clearCutoffs() throws -> [SolvgramCacheCategory: Date] {
        self.lock.lock(); defer { self.lock.unlock() }
        guard let state = try self.clearState() else { return [:] }
        var result: [SolvgramCacheCategory: Date] = [:]
        if let full = state.categories == nil ? state.date : state.previousFullDate {
            for category in SolvgramCacheCategory.allCases { result[category] = full }
        }
        for (key, date) in state.cutoffs ?? [:] {
            if let category = SolvgramCacheCategory(rawValue: key) { result[category] = max(result[category] ?? .distantPast, date) }
        }
        return result
    }

    public func pendingClearDate() throws -> Date? {
        self.lock.lock(); defer { self.lock.unlock() }
        return try self.clearState()?.date
    }

    public func pendingClearCategories() throws -> Set<SolvgramCacheCategory> {
        self.lock.lock(); defer { self.lock.unlock() }
        return Set(try self.clearState()?.categories ?? SolvgramCacheCategory.allCases)
    }

    public func hasPendingClear() throws -> Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        return try self.clearState()?.pending ?? false
    }

    public func beginClear(categories: Set<SolvgramCacheCategory> = Set(SolvgramCacheCategory.allCases)) throws -> [SolvgramLocalArchiveItem] {
        self.lock.lock(); defer { self.lock.unlock() }
        try self.prepare()
        let full = categories.isSuperset(of: SolvgramCacheCategory.messageCategories)
        let items = try self.readItems(allowCorruptRecords: full)
        let previous: ClearState?
        if full { previous = try? self.clearState() } else { previous = try self.clearState() }
        guard !categories.isEmpty else { return items }
        let date = Date()
        var cutoffs = previous?.cutoffs ?? [:]
        for category in categories { cutoffs[category.rawValue] = date }
        let previousFull = previous.map { $0.categories == nil ? $0.date : $0.previousFullDate } ?? nil
        let state = previous?.pending == true ? previous! : ClearState(date: date, pending: true,
            categories: full ? nil : categories.sorted { $0.rawValue < $1.rawValue },
            previousFullDate: previousFull, cutoffs: full ? nil : cutoffs)
        try JSONEncoder().encode(state).write(to: self.root.appendingPathComponent("clear.json"), options: .atomic)
        return items
    }

    public func finishClear() throws {
        self.lock.lock(); defer { self.lock.unlock() }
        guard var state = try self.clearState(), state.pending else { return }
        if let categories = state.categories {
            let selected = Set(categories)
            let items = try self.readItems()
            for var item in items {
                let remove = selected.contains(.disappearing) && item.disappearing || selected.contains(.deleted) && item.deleted && !item.disappearing
                if remove { try self.fm.removeItem(at: self.manifest(item.id)); continue }
                if selected.contains(.edits) { item.previousTexts = []; item.previousTextDates = [] }
                if selected.contains(.media) && !item.disappearing { item.attachments = [] }
                // A plain edited message with no history or files needs no archive manifest.
                if !item.deleted && !item.disappearing && item.previousTexts.isEmpty && item.attachments.isEmpty {
                    try self.fm.removeItem(at: self.manifest(item.id))
                } else { try JSONEncoder().encode(item).write(to: self.manifest(item.id), options: .atomic) }
            }
            self.resourceIndex = nil
            let retained = Set(try self.readItems().flatMap { $0.attachments.compactMap { $0.relativePath } })
            let folder = self.root.appendingPathComponent("media")
            if self.fm.fileExists(atPath: folder.path) {
                for url in try self.fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                    if !retained.contains("media/" + url.lastPathComponent) { try self.fm.removeItem(at: url) }
                }
            }
        } else {
            for name in ["media", "records"] {
                let url = self.root.appendingPathComponent(name)
                if self.fm.fileExists(atPath: url.path) { try self.fm.removeItem(at: url) }
            }
        }
        state.pending = false
        try JSONEncoder().encode(state).write(to: self.root.appendingPathComponent("clear.json"), options: .atomic)
        self.resourceIndex = nil
    }

    public func missingAttachmentIds(in items: [SolvgramLocalArchiveItem]) throws -> Set<String> {
        self.lock.lock(); defer { self.lock.unlock() }
        var result = Set<String>()
        for item in items {
            let saved = try self.read(item.id)
            for attachment in item.attachments {
                let old = saved?.attachments.first(where: { $0.id == attachment.id })
                let url = old?.relativePath.flatMap(self.mediaURL)
                let size = url.flatMap { (try? self.fm.attributesOfItem(atPath: $0.path)[.size]) as? NSNumber }
                if size?.int64Value != attachment.size { result.insert(attachment.id) }
            }
        }
        return result
    }

    /// Remove only files no longer referenced by another saved message.
    public func removeItems(ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        self.lock.lock(); defer { self.lock.unlock() }
        let items = try self.readItems()
        let removed = items.filter { ids.contains($0.id) }
        let retainedPaths = Set(items.filter { !ids.contains($0.id) }.flatMap { $0.attachments.compactMap { $0.relativePath } })
        for item in removed {
            try self.fm.removeItem(at: self.manifest(item.id))
        }
        self.resourceIndex = nil
        for path in Set(removed.flatMap { $0.attachments.compactMap { $0.relativePath } }).subtracting(retainedPaths) {
            if let url = self.mediaURL(path), self.fm.fileExists(atPath: url.path) { try self.fm.removeItem(at: url) }
        }
    }

    public func save(_ items: [SolvgramLocalArchiveItem], assets: [String: URL]) throws {
        self.lock.lock(); defer { self.lock.unlock() }
        guard try self.clearState()?.pending != true else { throw CocoaError(.fileWriteUnknown) }
        try self.prepare()
        if self.resourceIndex == nil { _ = try self.readItems() }
        let state = try self.clearState()
        let cutoff = state.map { $0.categories == nil ? $0.date : $0.previousFullDate } ?? nil
        for incoming in items {
            if let cutoff, incoming.updatedAt <= cutoff { continue }
            let previous = try self.read(incoming.id)
            var item = incoming
            if let previous {
                if previous.updatedAt > incoming.updatedAt { item = previous }
                item.deleted = previous.deleted || incoming.deleted
                item.disappearing = previous.disappearing || incoming.disappearing
                let incomingIsNewer = previous.updatedAt <= incoming.updatedAt
                let versions = solvgramMergeHistory(previous.previousTexts, incoming.previousTexts, limit: SolvgramCachePreferences.editHistoryLimit, incomingIsNewer: incomingIsNewer)
                item.previousTexts = versions.map { $0.text }
                item.previousTextDates = previous.previousTextDates == nil && incoming.previousTextDates == nil ? nil : versions.map { version in
                    let old = version.previousIndex.flatMap { index in previous.previousTextDates.flatMap { index < $0.count ? $0[index] : nil } }
                    let new = version.incomingIndex.flatMap { index in incoming.previousTextDates.flatMap { index < $0.count ? $0[index] : nil } }
                    let knownOld = old.flatMap { $0 > 0 ? $0 : nil }
                    let knownNew = new.flatMap { $0 > 0 ? $0 : nil }
                    return (incomingIsNewer ? knownNew ?? knownOld : knownOld ?? knownNew) ?? 0
                }
                item.attachments = previous.attachments
            }
            var created: [URL] = []
            do {
                for var attachment in incoming.attachments {
                    let old = item.attachments.first(where: { $0.id == attachment.id && $0.relativePath != nil }) ?? self.resourceIndex?[attachment.id]
                    if let path = old?.relativePath, let url = self.mediaURL(path),
                       let size = (try? self.fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
                       size.int64Value == attachment.size {
                        attachment.relativePath = path
                    } else if let source = assets[attachment.id] {
                        let size = try self.fm.attributesOfItem(atPath: source.path)[.size] as? NSNumber
                        guard size?.int64Value == attachment.size else { throw CocoaError(.fileReadCorruptFile) }
                        let ext = URL(fileURLWithPath: attachment.name).pathExtension.lowercased()
                        let safeExtension = !ext.isEmpty && ext.count <= 12 && ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) ? "." + ext : ""
                        let path = "media/" + UUID().uuidString + safeExtension
                        guard let destination = self.mediaURL(path) else { throw CocoaError(.fileWriteInvalidFileName) }
                        try self.fm.copyItem(at: source, to: destination)
                        created.append(destination)
                        #if os(iOS)
                        try self.fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
                        #endif
                        attachment.relativePath = path
                    } else {
                        // Do not acknowledge a file that the server says is available
                        // until its complete, durable local copy has been written.
                        throw CocoaError(.fileNoSuchFile)
                    }
                    if let index = item.attachments.firstIndex(where: { $0.id == attachment.id }) {
                        item.attachments[index] = attachment
                    } else { item.attachments.append(attachment) }
                }
                let limit = SolvgramCachePreferences.editHistoryLimit
                if item.previousTexts.count > limit {
                    let indices = [0] + Array(item.previousTexts.indices.suffix(limit - 1))
                    item.previousTexts = indices.map { item.previousTexts[$0] }
                    item.previousTextDates = item.previousTextDates.map { dates in indices.compactMap { $0 < dates.count ? dates[$0] : nil } }
                }
                try JSONEncoder().encode(item).write(to: self.manifest(item.id), options: .atomic)
                if self.resourceIndex != nil {
                    for file in item.attachments where file.relativePath != nil { self.resourceIndex?[file.id] = file }
                }
            } catch {
                for url in created { try? self.fm.removeItem(at: url) }
                throw error
            }
        }
    }

    public func statistics() throws -> (messages: Int, bytes: Int64) {
        self.lock.lock(); defer { self.lock.unlock() }
        let items = try self.readItems()
        var bytes: Int64 = 0
        for name in ["records", "media"] {
            let folder = self.root.appendingPathComponent(name)
            if let enumerator = self.fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
                for case let url as URL in enumerator {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
                }
            }
        }
        return (items.count, bytes)
    }

}

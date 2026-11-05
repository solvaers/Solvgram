import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import SGSimpleSettings

// MARK: Solvgram — account-scoped metadata for kept messages and edit history.
// Old builds stored no account identifier. Their records remain a compatibility
// fallback; all new writes include the account, so new histories cannot mix.
public final class SolvgramMessageArchive {
    public static let shared = SolvgramMessageArchive()
    private let storage = SolvgramArchiveStorage.shared

    private init() {
        let repairKey = "SolvgramSliderRepair1"
        if !UserDefaults.standard.bool(forKey: repairKey) {
            UserDefaults.standard.set(true, forKey: repairKey)
            let settings = SGSimpleSettings.shared
            if settings.accountColorsSaturation <= 1 { settings.accountColorsSaturation = 100 }
            if settings.outgoingPhotoQuality <= 1 { settings.outgoingPhotoQuality = 70 }
            if settings.stickerSize <= 1 { settings.stickerSize = 100 }
        }
    }

    private static func legacyKey(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64()):\(id.namespace):\(id.id)"
    }

    private static func key(_ id: MessageId, accountPeerId: PeerId) -> String {
        return "\(accountPeerId.toInt64()):\(self.legacyKey(id))"
    }

    public func isDeleted(_ id: MessageId, accountPeerId: PeerId) -> Bool {
        return self.storage.isDeleted(Self.key(id, accountPeerId: accountPeerId), legacyKey: Self.legacyKey(id))
    }

    /// The edits switches control display as well as capture: when saving edits is off
    /// for this chat the edited-message split is hidden, while the cached versions are kept.
    public func showsEditSplit(_ message: Message) -> Bool {
        return SolvgramSettings.captures(.edits, peerId: message.id.peerId.toInt64(), chat: solvgramChatKind(message.peers[message.id.peerId], peerId: message.id.peerId))
    }

    /// A kept deleted message is marked (the dashed outline) only while saving deleted
    /// messages is on for its chat. Off hides the mark; the saved message stays.
    public func displaysDeleted(_ message: Message, accountPeerId: PeerId) -> Bool {
        guard self.isDeleted(message.id, accountPeerId: accountPeerId) else { return false }
        return SolvgramSettings.captures(.deleted, peerId: message.id.peerId.toInt64(), chat: solvgramChatKind(message.peers[message.id.peerId], peerId: message.id.peerId))
    }

    public func isSelfDestructing(_ id: MessageId, accountPeerId: PeerId) -> Bool {
        return self.storage.isDisappearing(Self.key(id, accountPeerId: accountPeerId), legacyKey: Self.legacyKey(id))
    }

    public func previousTexts(_ id: MessageId, accountPeerId: PeerId) -> [String] {
        return self.storage.previousTexts(Self.key(id, accountPeerId: accountPeerId), legacyKey: Self.legacyKey(id))
    }

    func markDeleted(_ ids: [MessageId], accountPeerId: PeerId) {
        self.storage.markDeleted(ids.map { Self.key($0, accountPeerId: accountPeerId) })
    }

    func markSelfDestructing(_ id: MessageId, accountPeerId: PeerId) {
        guard Thread.current.threadDictionary["SolvgramServerImportAccount"] as? Int64 != accountPeerId.toInt64() else { return }
        self.storage.markDisappearing(Self.key(id, accountPeerId: accountPeerId))
    }

    func unmarkSelfDestructing(_ id: MessageId, accountPeerId: PeerId) {
        self.storage.unmarkDisappearing(Self.key(id, accountPeerId: accountPeerId), legacyKey: Self.legacyKey(id))
    }

    public func storiesViewedAnonymously(peerId: PeerId, accountPeerId: PeerId) -> Bool {
        return self.storage.storiesViewedAnonymously("\(accountPeerId.toInt64()):\(peerId.toInt64())", legacyKey: "\(peerId.toInt64())")
    }

    func setStoriesViewedAnonymously(peerId: PeerId, accountPeerId: PeerId, maxId: Int32, anonymously: Bool) {
        self.storage.setStoriesViewedAnonymously("\(accountPeerId.toInt64()):\(peerId.toInt64())", maxId: maxId, anonymously: anonymously, legacyKey: "\(peerId.toInt64())")
    }

    func recordEdit(_ id: MessageId, accountPeerId: PeerId, previousText: String) {
        guard Thread.current.threadDictionary["SolvgramServerImportAccount"] as? Int64 != accountPeerId.toInt64() else { return }
        self.storage.recordEdit(Self.key(id, accountPeerId: accountPeerId), previousText: previousText, legacyKey: Self.legacyKey(id))
    }

    /// Postbox invokes the text-change hook synchronously. A server replacement
    /// already carries its full history, so it must not append the stale local text again.
    func applyingServerUpdate<T>(accountPeerId: PeerId, _ body: () -> T) -> T {
        let dictionary = Thread.current.threadDictionary
        let old = dictionary["SolvgramServerImportAccount"]
        dictionary["SolvgramServerImportAccount"] = accountPeerId.toInt64()
        defer { dictionary["SolvgramServerImportAccount"] = old }
        return body()
    }

    func mergeServerHistory(_ id: MessageId, accountPeerId: PeerId, texts: [String], incomingIsNewer: Bool = true) {
        self.storage.mergePreviousTexts(Self.key(id, accountPeerId: accountPeerId), texts: texts, legacyKey: Self.legacyKey(id), incomingIsNewer: incomingIsNewer)
    }

    func clearServerMetadata(_ ids: [MessageId], accountPeerId: PeerId) {
        self.storage.removeMessageMetadata(ids.flatMap { [Self.key($0, accountPeerId: accountPeerId), Self.legacyKey($0)] })
        self.storage.flush()
    }

    public func flush() { self.storage.flush() }
}

/// The type of a chat for the saving switches: nil when a channel's peer is not known yet.
public func solvgramChatKind(_ peer: Peer?, peerId: PeerId) -> SolvgramSettings.ChatKind? {
    switch peerId.namespace {
    case Namespaces.Peer.CloudUser, Namespaces.Peer.SecretChat:
        return .privateChats
    case Namespaces.Peer.CloudGroup:
        return .groups
    case Namespaces.Peer.CloudChannel:
        guard let channel = peer as? TelegramChannel else { return nil }
        if case .broadcast = channel.info { return .channels }
        return .groups
    default:
        return nil
    }
}

// Stored in the account's Postbox, in the same transaction as the explicit
// deletion. A replay, cache clear or app restart must never undo user intent.
private func solvgramManualDeletionKey(_ id: MessageId) -> ValueBoxKey {
    return ValueBoxKey("solvgram.archive.manual-deletion.v1.\(id.peerId.toInt64()):\(id.namespace):\(id.id)")
}

private struct SolvgramManualDeletion: Codable {
    let deleted: Bool
}

private struct SolvgramManualHistoryClear: Codable {
    let timestamp: Int32
    let maxId: Int32
}

private struct SolvgramManualDateRange: Codable {
    let min: Int32
    let max: Int32
}

private struct SolvgramManualDateRanges: Codable {
    let ranges: [SolvgramManualDateRange]
}

private func solvgramManualHistoryKey(peerId: PeerId, threadId: Int64?, authorId: PeerId? = nil) -> ValueBoxKey {
    let scope = authorId.map { "author:\($0.toInt64())" } ?? (threadId.map(String.init) ?? "all")
    return ValueBoxKey("solvgram.archive.history-clear.v1.\(peerId.toInt64()):\(scope)")
}

private func solvgramManualDateRangesKey(peerId: PeerId, threadId: Int64?) -> ValueBoxKey {
    return ValueBoxKey("solvgram.archive.date-clear.v1.\(peerId.toInt64()):\(threadId.map(String.init) ?? "all")")
}

func solvgramRecordManualDateClear(transaction: Transaction, peerId: PeerId, threadId: Int64?, minTimestamp: Int32, maxTimestamp: Int32) {
    guard minTimestamp <= maxTimestamp else { return }
    let key = solvgramManualDateRangesKey(peerId: peerId, threadId: threadId)
    var ranges = transaction.getPreferencesEntry(key: key)?.get(SolvgramManualDateRanges.self)?.ranges ?? []
    ranges.append(SolvgramManualDateRange(min: minTimestamp, max: maxTimestamp))
    ranges.sort { $0.min < $1.min }
    var merged: [SolvgramManualDateRange] = []
    for range in ranges {
        if let last = merged.last, Int64(range.min) <= Int64(last.max) + 1 {
            merged[merged.count - 1] = SolvgramManualDateRange(min: last.min, max: max(last.max, range.max))
        } else { merged.append(range) }
    }
    transaction.setPreferencesEntry(key: key, value: PreferencesEntry(SolvgramManualDateRanges(ranges: merged)))
}

func solvgramRecordManualHistoryClear(transaction: Transaction, peerId: PeerId, threadId: Int64?, authorId: PeerId? = nil) {
    guard [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel].contains(peerId.namespace) else { return }
    let key = solvgramManualHistoryKey(peerId: peerId, threadId: threadId, authorId: authorId)
    let previous = transaction.getPreferencesEntry(key: key)?.get(SolvgramManualHistoryClear.self)
    let maxId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud)?.id ?? 0
    transaction.setPreferencesEntry(key: key, value: PreferencesEntry(SolvgramManualHistoryClear(
        timestamp: max(previous?.timestamp ?? 0, Int32(clamping: Int64(Date().timeIntervalSince1970))),
        maxId: max(previous?.maxId ?? 0, maxId))))
}

private func solvgramWasManuallyDeleted(transaction: Transaction, id: MessageId, timestamp: Int32? = nil, threadId: Int64? = nil, authorId: PeerId? = nil) -> Bool {
    if transaction.getPreferencesEntry(key: solvgramManualDeletionKey(id)) != nil { return true }
    let current = timestamp == nil ? transaction.getMessage(id) : nil
    let timestamp = timestamp ?? current?.timestamp
    let threadId = threadId ?? current?.threadId
    let scopes: [Int64?] = threadId.map { [nil, $0] } ?? [nil]
    for scope in scopes {
        if let timestamp, let ranges = transaction.getPreferencesEntry(key: solvgramManualDateRangesKey(peerId: id.peerId, threadId: scope))?.get(SolvgramManualDateRanges.self),
           ranges.ranges.contains(where: { $0.min <= timestamp && timestamp <= $0.max }) { return true }
    }
    var historyKeys = scopes.map { solvgramManualHistoryKey(peerId: id.peerId, threadId: $0) }
    if let authorId = authorId ?? current?.author?.id { historyKeys.append(solvgramManualHistoryKey(peerId: id.peerId, threadId: nil, authorId: authorId)) }
    for key in historyKeys {
        if let clear = transaction.getPreferencesEntry(key: key)?.get(SolvgramManualHistoryClear.self),
           id.id <= clear.maxId || (timestamp.map { $0 < clear.timestamp } ?? false) { return true }
    }
    return false
}

private func solvgramArchiveItemId(_ id: MessageId) -> String {
    let peer = id.peerId.id._internalGetInt64Value()
    let remote: Int64
    if id.peerId.namespace == Namespaces.Peer.CloudChannel { remote = -1_000_000_000_000 - peer }
    else if id.peerId.namespace == Namespaces.Peer.CloudGroup { remote = -peer }
    else { remote = peer }
    return "\(remote)_\(id.id)"
}

func solvgramRecordManualDeletion(transaction: Transaction, ids: [MessageId], accountPeerId: PeerId) {
    let ids = ids.filter { $0.namespace == Namespaces.Message.Cloud }
    guard !ids.isEmpty else { return }
    for id in ids {
        transaction.setPreferencesEntry(key: solvgramManualDeletionKey(id), value: PreferencesEntry(SolvgramManualDeletion(deleted: true)))
    }
    SolvgramMessageArchive.shared.clearServerMetadata(ids, accountPeerId: accountPeerId)
    // The database exclusion remains authoritative even if file cleanup fails.
    try? SolvgramLocalArchiveStore.shared(accountId: String(accountPeerId.id._internalGetInt64Value())).removeItems(ids: Set(ids.map(solvgramArchiveItemId)))
}

private func solvgramParseServerMessage(_ data: Data, accountPeerId: PeerId) -> StoreMessage? {
    guard let apiMessage = Api.parse(Buffer(data: data)) as? Api.Message else { return nil }
    var isForum = false
    if case let .message(data) = apiMessage, case let .messageReplyHeader(reply)? = data.replyTo {
        isForum = (reply.flags & (1 << 3)) != 0
    }
    return SolvgramMessageArchive.shared.applyingServerUpdate(accountPeerId: accountPeerId) {
        StoreMessage(apiMessage: apiMessage, accountPeerId: accountPeerId, peerIsForum: isForum)
    }
}

private func solvgramServerMessage(_ entry: SolvgramServerArchiveEntry, accountPeerId: PeerId) -> StoreMessage? {
    guard let message = solvgramParseServerMessage(entry.messageTl, accountPeerId: accountPeerId),
          case let .Id(id) = message.id, id.id == entry.messageId,
          let remoteChat = Int64(entry.chatId), remoteChat != Int64.min else { return nil }
    let expected: PeerId
    if remoteChat <= -1_000_000_000_000 {
        expected = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(-remoteChat - 1_000_000_000_000))
    } else if remoteChat < 0 {
        expected = PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(-remoteChat))
    } else {
        expected = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(remoteChat))
    }
    guard id.peerId == expected else { return nil }
    return message.withUpdatedAttributes(message.attributes.filter { !($0 is AutoclearTimeoutMessageAttribute) && !($0 is AutoremoveTimeoutMessageAttribute) })
}

private func solvgramServerMediaResource(_ message: StoreMessage) -> MediaResource? {
    for media in message.media {
        if let file = media as? TelegramMediaFile { return file.resource }
        if let image = media as? TelegramMediaImage {
            return image.representations.max(by: { $0.dimensions.width * $0.dimensions.height < $1.dimensions.width * $1.dimensions.height })?.resource
        }
    }
    return nil
}

public extension SolvgramServerArchiveEntry {
    var isAutoDeletingMessage: Bool {
        guard let api = Api.parse(Buffer(data: self.messageTl)) as? Api.Message, case let .message(data) = api else { return false }
        return data.ttlPeriod != nil
    }

    func retained(afterCacheClear cutoffs: [SolvgramCacheCategory: Date]) -> SolvgramServerArchiveEntry? {
        let observed = self.observedAt ?? 0
        if self.disappearing, let date = cutoffs[.disappearing], observed <= date.timeIntervalSince1970 { return nil }
        if self.deleted && !self.disappearing, let date = cutoffs[.deleted], observed <= date.timeIntervalSince1970 { return nil }
        if !self.deleted && !self.disappearing, let date = cutoffs[.edits], observed <= date.timeIntervalSince1970 { return nil }
        let keepHistory = self.previousTexts.indices.filter { index in
            guard let cutoff = cutoffs[.edits] else { return true }
            guard let dates = self.previousTextDates, index < dates.count else { return false }
            return dates[index] > cutoff.timeIntervalSince1970
        }
        let keepMedia = self.disappearing || cutoffs[.media].map { observed > $0.timeIntervalSince1970 } != false
        return SolvgramServerArchiveEntry(sequence: self.sequence, chatId: self.chatId, messageId: self.messageId,
            deleted: self.deleted, disappearing: self.disappearing, messageTl: self.messageTl,
            previousTexts: keepHistory.map { self.previousTexts[$0] }, mediaRevision: keepMedia ? self.mediaRevision : nil,
            mediaSize: keepMedia ? self.mediaSize : nil, observedAt: self.observedAt,
            previousTextDates: self.previousTextDates.map { dates in keepHistory.compactMap { $0 < dates.count ? dates[$0] : nil } })
    }
}

private struct SolvgramCacheMessage {
    var deleted = false
    var disappearing = false
    var previousTexts: [String] = []
    var metadataKeys: [String] = []
    var items: [SolvgramLocalArchiveItem] = []
}

private func solvgramCacheId(_ item: SolvgramLocalArchiveItem) -> MessageId? {
    guard let remote = Int64(item.chatId), remote != Int64.min else { return nil }
    let peer: PeerId
    if remote <= -1_000_000_000_000 { peer = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(-remote - 1_000_000_000_000)) }
    else if remote < 0 { peer = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(-remote)) }
    else { peer = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(remote)) }
    return MessageId(peerId: peer, namespace: Namespaces.Message.Cloud, id: item.messageId)
}

private func solvgramCacheMessages(transaction: Transaction, accountPeerId: PeerId, items: [SolvgramLocalArchiveItem]) -> [MessageId: SolvgramCacheMessage] {
    var result: [MessageId: SolvgramCacheMessage] = [:]
    for (key, value) in SolvgramArchiveStorage.shared.messageMetadata() {
        var parts = key.split(separator: ":")
        if parts.count == 4 {
            guard Int64(parts.removeFirst()) == accountPeerId.toInt64() else { continue }
        }
        guard parts.count == 3, let peer = Int64(parts[0]), let namespace = Int32(parts[1]), namespace == Namespaces.Message.Cloud, let mid = Int32(parts[2]) else { continue }
        let id = MessageId(peerId: PeerId(peer), namespace: namespace, id: mid)
        // An unscoped legacy key is managed only when its message exists here.
        if key.split(separator: ":").count == 3 && transaction.getMessage(id) == nil { continue }
        var record = result[id] ?? SolvgramCacheMessage()
        record.deleted = record.deleted || value.deleted
        record.disappearing = record.disappearing || value.disappearing
        record.metadataKeys.append(key)
        record.previousTexts = SolvgramMessageArchive.shared.previousTexts(id, accountPeerId: accountPeerId)
        result[id] = record
    }
    for item in items {
        guard let id = solvgramCacheId(item) else { continue }
        var record = result[id] ?? SolvgramCacheMessage()
        record.deleted = record.deleted || item.deleted
        record.disappearing = record.disappearing || item.disappearing
        if record.previousTexts.isEmpty { record.previousTexts = item.previousTexts }
        record.items.append(item)
        result[id] = record
    }
    return result
}

private func solvgramCacheResources(transaction: Transaction, id: MessageId, record: SolvgramCacheMessage) -> Set<MediaResourceId> {
    var resources: [MediaResourceId] = record.items.flatMap { $0.attachments.map { MediaResourceId($0.id) } }
    if let message = transaction.getMessage(id) { addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resources) }
    return Set(resources)
}

private struct SolvgramCacheClearReceipt: Codable {
    let date: Double
    let resources: [String]
}

public extension TelegramEngine.Messages {
    func solvgramServerArchiveAllowedEntries(_ entries: [SolvgramServerArchiveEntry]) -> Signal<[SolvgramServerArchiveEntry], NoError> {
        let account = self.account
        return account.postbox.transaction { transaction in
            entries.filter { entry in
                guard let message = solvgramServerMessage(entry, accountPeerId: account.peerId), case let .Id(id) = message.id else { return true }
                return !solvgramWasManuallyDeleted(transaction: transaction, id: id, timestamp: message.timestamp, threadId: message.threadId, authorId: message.authorId)
            }
        }
    }

    /// Serialize the final cache write with interactive deletion. Filtering only
    /// when fetching a page leaves a race while its media is downloading.
    func solvgramSaveServerArchiveCache(_ items: [SolvgramLocalArchiveItem], assets: [String: URL]) -> Signal<Bool, NoError> {
        let account = self.account
        return account.postbox.transaction { transaction in
            let store = SolvgramLocalArchiveStore.shared(accountId: String(account.peerId.id._internalGetInt64Value()))
            guard let cutoffs = try? store.clearCutoffs() else { return false }
            let allowed = items.compactMap { item -> SolvgramLocalArchiveItem? in
                guard let message = solvgramParseServerMessage(item.messageTl, accountPeerId: account.peerId),
                      case let .Id(id) = message.id else { return nil }
                guard !solvgramWasManuallyDeleted(transaction: transaction, id: id, timestamp: message.timestamp, threadId: message.threadId, authorId: message.authorId) else { return nil }
                let entry = SolvgramServerArchiveEntry(sequence: 0, chatId: item.chatId, messageId: item.messageId, deleted: item.deleted, disappearing: item.disappearing,
                    messageTl: item.messageTl, previousTexts: item.previousTexts, mediaRevision: nil, mediaSize: nil,
                    observedAt: item.updatedAt.timeIntervalSince1970, previousTextDates: item.previousTextDates)
                guard let kept = entry.retained(afterCacheClear: cutoffs) else { return nil }
                var item = item
                item.previousTexts = kept.previousTexts
                item.previousTextDates = kept.previousTextDates
                if !item.disappearing, let date = cutoffs[.media], item.updatedAt <= date { item.attachments = [] }
                return item
            }
            do {
                try SolvgramLocalArchiveStore.shared(accountId: String(account.peerId.id._internalGetInt64Value())).save(allowed, assets: assets)
                return true
            } catch { return false }
        }
    }

    func solvgramServerArchiveCacheItems(_ entries: [SolvgramServerArchiveEntry]) -> Signal<[SolvgramLocalArchiveItem]?, NoError> {
        let account = self.account
        return account.postbox.transaction { transaction -> [SolvgramLocalArchiveItem]? in
            guard let cutoffs = try? SolvgramLocalArchiveStore.shared(accountId: String(account.peerId.id._internalGetInt64Value())).clearCutoffs() else { return nil }
            var items: [SolvgramLocalArchiveItem] = []
            for original in entries {
                guard let entry = original.retained(afterCacheClear: cutoffs) else { continue }
                guard let message = solvgramServerMessage(entry, accountPeerId: account.peerId), case let .Id(id) = message.id else { return nil }
                if solvgramWasManuallyDeleted(transaction: transaction, id: id, timestamp: message.timestamp, threadId: message.threadId, authorId: message.authorId) { continue }
                var attachments: [SolvgramLocalArchiveAttachment] = []
                if let resource = solvgramServerMediaResource(message), entry.mediaRevision != nil, let size = entry.mediaSize {
                    var name = "photo.jpg"
                    var kind = "photo"
                    if let file = message.media.compactMap({ $0 as? TelegramMediaFile }).first {
                        name = file.fileName ?? (file.isVideo ? "video.mp4" : file.isVoice ? "voice.ogg" : "file")
                        kind = file.isVideo ? "video" : file.isVoice || file.isMusic ? "audio" : "file"
                    }
                    attachments.append(SolvgramLocalArchiveAttachment(id: resource.id.stringRepresentation, name: name, kind: kind, size: size))
                }
                items.append(SolvgramLocalArchiveItem(chatId: entry.chatId, messageId: entry.messageId,
                    chatTitle: transaction.getPeer(id.peerId)?.debugDisplayTitle ?? entry.chatId,
                    author: message.authorId.flatMap { transaction.getPeer($0)?.debugDisplayTitle } ?? "",
                    timestamp: message.timestamp, updatedAt: Date(timeIntervalSince1970: entry.observedAt ?? Double(message.timestamp)),
                    text: message.text, previousTexts: entry.previousTexts, deleted: entry.deleted,
                    disappearing: entry.disappearing, attachments: attachments, messageTl: entry.messageTl, previousTextDates: entry.previousTextDates))
            }
            return items
        }
    }

    func solvgramServerArchiveCachedMedia(_ entries: [SolvgramServerArchiveEntry]) -> Signal<[Int64: String], NoError> {
        var files: [Int64: String] = [:]
        let store = SolvgramLocalArchiveStore.shared(accountId: String(self.account.peerId.id._internalGetInt64Value()))
        for entry in entries {
            guard let revision = entry.mediaRevision, let message = solvgramServerMessage(entry, accountPeerId: self.account.peerId),
                  let resource = solvgramServerMediaResource(message) else { continue }
            if let path = self.account.postbox.mediaBox.completedResourcePath(resource),
               let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber,
               size.int64Value == entry.mediaSize {
                files[revision] = path
            } else if let url = store.fileURL(resourceId: resource.id.stringRepresentation) {
                files[revision] = url.path
            }
        }
        return .single(files)
    }

    func solvgramDeviceCacheStatistics() -> Signal<SolvgramDeviceCacheStatistics?, NoError> {
        let account = self.account
        let store = SolvgramLocalArchiveStore.shared(accountId: String(account.peerId.id._internalGetInt64Value()))
        return account.postbox.transaction { transaction -> SolvgramDeviceCacheStatistics? in
            guard let items = try? store.items() else { return nil }
            var stats = Dictionary(uniqueKeysWithValues: SolvgramCacheCategory.allCases.map { ($0, SolvgramCacheCategoryStatistics()) })
            var countedPaths = Set<String>()
            var totalBytes: Int64 = 0
            let records = solvgramCacheMessages(transaction: transaction, accountPeerId: account.peerId, items: items).sorted { lhs, rhs in
                if lhs.value.disappearing != rhs.value.disappearing { return lhs.value.disappearing }
                return lhs.key.peerId == rhs.key.peerId ? lhs.key.id < rhs.key.id : lhs.key.peerId < rhs.key.peerId
            }
            for (id, record) in records {
                let text = transaction.getMessage(id)?.text ?? record.items.first?.text ?? ""
                let textBytes = Int64(text.utf8.count)
                if record.disappearing { stats[.disappearing]!.count += 1; stats[.disappearing]!.bytes += textBytes; totalBytes += textBytes }
                else if record.deleted { stats[.deleted]!.count += 1; stats[.deleted]!.bytes += textBytes; totalBytes += textBytes }
                let historyBytes = Int64(record.previousTexts.reduce(0) { $0 + $1.utf8.count })
                stats[.edits]!.count += record.previousTexts.count
                stats[.edits]!.bytes += historyBytes
                totalBytes += historyBytes
                let category: SolvgramCacheCategory = record.disappearing ? .disappearing : .media
                var paths: [String] = solvgramCacheResources(transaction: transaction, id: id, record: record).compactMap { account.postbox.mediaBox.completedResourcePath(id: $0) }
                paths += record.items.flatMap { $0.attachments.compactMap { store.fileURL(for: $0)?.path } }
                for path in paths where countedPaths.insert(path).inserted {
                    let size = ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0
                    stats[category]!.bytes += size
                    if category == .media { stats[category]!.count += 1 }
                    totalBytes += size
                }
            }
            let stories = SolvgramArchiveStorage.shared.storyViewStatistics(accountPeerId: account.peerId.toInt64())
            stats[.stories] = SolvgramCacheCategoryStatistics(count: stories.count, bytes: stories.bytes)
            totalBytes += stories.bytes
            return SolvgramDeviceCacheStatistics(categories: stats, totalBytes: totalBytes)
        }
    }

    /// Really removes kept data from the app: kept deleted and disappearing messages leave the
    /// message database (and are recorded as deleted so nothing brings them back), edit history and
    /// Solvgram's marks are dropped, and their files are removed. `peerId` limits it to one chat.
    func solvgramClearServerArchive(_ items: [SolvgramLocalArchiveItem], categories: Set<SolvgramCacheCategory> = Set(SolvgramCacheCategory.allCases), clearDate: Date? = nil, peerId: PeerId? = nil) -> Signal<Bool, NoError> {
        let account = self.account
        return account.postbox.transaction { transaction -> [MediaResourceId] in
            let receiptKey = ValueBoxKey("solvgram.cache.clear-receipt.v1")
            if let clearDate, let receipt = transaction.getPreferencesEntry(key: receiptKey)?.get(SolvgramCacheClearReceipt.self), receipt.date == clearDate.timeIntervalSince1970 {
                return receipt.resources.map(MediaResourceId.init)
            }
            var records = solvgramCacheMessages(transaction: transaction, accountPeerId: account.peerId, items: items)
            if let peerId { records = records.filter { $0.key.peerId == peerId } }
            var removeIds: [MessageId] = []
            var clearHistoryKeys: [String] = []
            var resources = Set<MediaResourceId>()
            var protected = Set<MediaResourceId>()
            for (id, record) in records {
                let remove = record.disappearing ? categories.contains(.disappearing) : record.deleted && categories.contains(.deleted)
                let removeMedia = remove || categories.contains(.media) && !record.disappearing
                if removeMedia { resources.formUnion(solvgramCacheResources(transaction: transaction, id: id, record: record)) }
                else { protected.formUnion(solvgramCacheResources(transaction: transaction, id: id, record: record)) }
                if remove { removeIds.append(id) }
                else if categories.contains(.edits) { clearHistoryKeys.append(contentsOf: record.metadataKeys) }
            }
            // Removing a kept message is explicit local deletion. A later expiry
            // or download-completion event must not resurrect this same message.
            for id in removeIds {
                transaction.setPreferencesEntry(key: solvgramManualDeletionKey(id), value: PreferencesEntry(SolvgramManualDeletion(deleted: true)))
            }
            SolvgramMessageArchive.shared.clearServerMetadata(removeIds, accountPeerId: account.peerId)
            SolvgramArchiveStorage.shared.removeEditHistory(clearHistoryKeys)
            SolvgramArchiveStorage.shared.flush()
            _internal_deleteMessages(transaction: transaction, mediaBox: account.postbox.mediaBox, ids: removeIds, deleteMedia: false)
            let removed = Set(removeIds)
            for id in records.keys where !removed.contains(id) { solvgramTouchMessage(transaction: transaction, id: id) }
            resources.subtract(protected)
            if let clearDate { transaction.setPreferencesEntry(key: receiptKey, value: PreferencesEntry(SolvgramCacheClearReceipt(date: clearDate.timeIntervalSince1970, resources: resources.map { $0.stringRepresentation }))) }
            return Array(resources)
        }
        |> mapToSignal { resources in
            Signal<Bool, NoError> { subscriber in
                account.postbox.mediaBox.removeCachedResources(resources, force: true, notify: true)
                    .start(completed: { subscriber.putNext(true); subscriber.putCompletion() })
            }
        }
    }

    /// Clear kept data of one chat. Its server-archive copies on this device go too.
    func solvgramClearChatCache(peerId: PeerId, categories: Set<SolvgramCacheCategory>) -> Signal<Bool, NoError> {
        let account = self.account
        let store = SolvgramLocalArchiveStore.shared(accountId: String(account.peerId.id._internalGetInt64Value()))
        if categories.contains(.stories) {
            SolvgramArchiveStorage.shared.removeStoryViews(accountPeerId: account.peerId.toInt64(), peerId: peerId.toInt64())
        }
        let messageCategories = categories.intersection(SolvgramCacheCategory.messageCategories)
        guard !messageCategories.isEmpty else { return .single(true) }
        guard let all = try? store.items() else { return .single(false) }
        let items = all.filter { solvgramCacheId($0)?.peerId == peerId }
        return self.solvgramClearServerArchive(items, categories: messageCategories, peerId: peerId)
        |> map { _ -> Bool in
            let removed = items.filter { item in
                item.disappearing ? messageCategories.contains(.disappearing) : item.deleted && messageCategories.contains(.deleted)
            }
            do {
                try store.removeItems(ids: Set(removed.map { $0.id }))
                return true
            } catch { return false }
        }
    }

    /// The most recent chats of the main list, newest first, for picking a chat in the menu.
    func solvgramRecentChatPeers(count: Int = 100) -> Signal<[EnginePeer], NoError> {
        return self.account.viewTracker.tailChatListView(groupId: .root, count: count)
        |> take(1)
        |> map { view, _ -> [EnginePeer] in
            var result: [EnginePeer] = []
            for entry in view.entries.reversed() {
                if case let .MessageEntry(data) = entry, let peer = data.renderedPeer.chatMainPeer {
                    result.append(EnginePeer(peer))
                }
            }
            return result
        }
    }

    func solvgramServerArchiveMissingMedia(_ entries: [SolvgramServerArchiveEntry]) -> Signal<[Int64], NoError> {
        let account = self.account
        return .single(entries.compactMap { entry in
            guard let revision = entry.mediaRevision,
                  let message = solvgramServerMessage(entry, accountPeerId: account.peerId),
                  let resource = solvgramServerMediaResource(message),
                  account.postbox.mediaBox.completedResourcePath(resource) == nil else { return nil }
            return revision
        })
    }

    /// Restore missing messages and expired media in one transaction. A saved
    /// edit replaces existing text only when its edit date is newer and it was deleted.
    func solvgramImportServerArchive(entries: [SolvgramServerArchiveEntry], peers: [Data], mediaFiles: [Int64: String]) -> Signal<Int?, NoError> {
        let account = self.account
        guard let cutoffs = try? SolvgramLocalArchiveStore.shared(accountId: String(account.peerId.id._internalGetInt64Value())).clearCutoffs() else { return .single(nil) }
        var parsed: [(SolvgramServerArchiveEntry, StoreMessage)] = []
        for original in entries {
            guard let entry = original.retained(afterCacheClear: cutoffs) else { continue }
            guard let message = solvgramServerMessage(entry, accountPeerId: account.peerId) else { return .single(nil) }
            if let revision = entry.mediaRevision, let path = mediaFiles[revision], let resource = solvgramServerMediaResource(message) {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return .single(nil) }
                let currentSize = account.postbox.mediaBox.completedResourcePath(resource).flatMap {
                    (try? FileManager.default.attributesOfItem(atPath: $0)[.size]) as? NSNumber
                }?.int64Value
                if currentSize != Int64(data.count) {
                    account.postbox.mediaBox.storeResourceData(resource.id, data: data, synchronous: true)
                }
                guard let storedPath = account.postbox.mediaBox.completedResourcePath(resource),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: storedPath),
                      (attributes[.size] as? NSNumber)?.int64Value == Int64(data.count) else { return .single(nil) }
            }
            parsed.append((entry, message))
        }
        let users = peers.compactMap { Api.parse(Buffer(data: $0)) as? Api.User }
        let chats = peers.compactMap { Api.parse(Buffer(data: $0)) as? Api.Chat }
        return account.postbox.transaction { transaction -> Int? in
            updatePeers(transaction: transaction, accountPeerId: account.peerId, peers: AccumulatedPeers(transaction: transaction, chats: chats, users: users))
            let archive = SolvgramMessageArchive.shared
            guard let cutoffs = try? SolvgramLocalArchiveStore.shared(accountId: String(account.peerId.id._internalGetInt64Value())).clearCutoffs() else { return nil }
            var restored = 0
            for (original, message) in parsed {
                guard let entry = original.retained(afterCacheClear: cutoffs) else { continue }
                guard case let .Id(id) = message.id else { return nil }
                if solvgramWasManuallyDeleted(transaction: transaction, id: id, timestamp: message.timestamp, threadId: message.threadId, authorId: message.authorId) { continue }
                let current = transaction.getMessage(id)
                let serverEditDate = message.attributes.compactMap { ($0 as? EditedMessageAttribute)?.date }.max() ?? 0
                let currentEditDate = current?.attributes.compactMap { ($0 as? EditedMessageAttribute)?.date }.max() ?? 0
                archive.mergeServerHistory(id, accountPeerId: account.peerId, texts: entry.previousTexts, incomingIsNewer: serverEditDate >= currentEditDate)
                if entry.deleted { archive.markDeleted([id], accountPeerId: account.peerId) }
                if entry.disappearing { archive.markSelfDestructing(id, accountPeerId: account.peerId) }
                if let current {
                    let restoreExpired = entry.disappearing && current.media.contains(where: { $0 is TelegramMediaExpiredContent }) && solvgramServerMediaResource(message) != nil
                    if restoreExpired || (entry.deleted && serverEditDate > currentEditDate) {
                        archive.applyingServerUpdate(accountPeerId: account.peerId) {
                            transaction.updateMessage(id, update: { _ in .update(message) })
                        }
                        restored += 1
                    } else {
                        solvgramTouchMessage(transaction: transaction, id: id)
                    }
                } else {
                    _ = transaction.addMessages([message], location: .Random)
                    updatePeerChatInclusionWithMinTimestamp(transaction: transaction, id: id.peerId, minTimestamp: message.timestamp, forceRootGroupIfNotExists: true)
                    restored += 1
                }
            }
            archive.flush()
            return restored
        }
    }
}

/// Re-stores a message unchanged, so the chat redraws it with its new Solvgram mark.
func solvgramTouchMessage(transaction: Transaction, id: MessageId) {
    transaction.updateMessage(id, update: { currentMessage in
        var storeForwardInfo: StoreMessageForwardInfo?
        if let forwardInfo = currentMessage.forwardInfo {
            storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
        }
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: currentMessage.attributes, media: currentMessage.media))
    })
}

/// The messages of a server delete that the Solvgram menu keeps; they are marked, not deleted.
func solvgramMessagesKeptFromDeletion(transaction: Transaction, accountPeerId: PeerId, ids: [MessageId]) -> Set<MessageId> {
    let saveDeleted = SolvgramSettings.saveDeleted
    let keepSelfDestructing = SolvgramSettings.keepSelfDestructing || UserDefaults.standard.bool(forKey: "LeadAntiAutoDelete")
    guard saveDeleted || keepSelfDestructing else {
        return Set()
    }
    var kept = Set<MessageId>()
    for id in ids where id.namespace == Namespaces.Message.Cloud {
        guard !solvgramWasManuallyDeleted(transaction: transaction, id: id), transaction.getMessage(id) != nil else {
            continue
        }
        let savesHere = saveDeleted && SolvgramSettings.captures(.deleted, peerId: id.peerId.toInt64(), chat: solvgramChatKind(transaction.getPeer(id.peerId), peerId: id.peerId))
        if savesHere || SolvgramMessageArchive.shared.isSelfDestructing(id, accountPeerId: accountPeerId) {
            kept.insert(id)
        }
    }
    if !kept.isEmpty {
        SolvgramMessageArchive.shared.markDeleted(Array(kept), accountPeerId: accountPeerId)
        for id in kept {
            solvgramTouchMessage(transaction: transaction, id: id)
        }
    }
    return kept
}

public extension TelegramEngine.Messages {
    /// Mark as Read for a disappearing photo or video Keep Disappearing Media kept: tells the server
    /// it was opened (past Solvgram's request filter, which otherwise keeps that from the server),
    /// so the sender sees it as viewed and it expires; then removes it here as it would have been.
    func solvgramMarkDisappearingMediaOpened(id: EngineMessage.Id) -> Signal<Bool, NoError> {
        let account = self.account
        return account.postbox.transaction { transaction -> Peer? in
            return transaction.getPeer(id.peerId)
        }
        |> mapToSignal { peer -> Signal<Bool, NoError> in
            guard let peer else {
                return .single(false)
            }
            let report: Signal<Bool, NoError>
            if id.peerId.namespace == Namespaces.Peer.CloudChannel {
                guard let inputChannel = apiInputChannel(peer) else {
                    return .single(false)
                }
                report = account.network.request(Api.functions.channels.readMessageContents(channel: inputChannel, id: [id.id]), solvgramBypassFilter: true)
                |> map { result -> Bool in
                    if case .boolTrue = result { return true }
                    return false
                }
                |> `catch` { _ -> Signal<Bool, NoError> in return .single(false) }
            } else {
                report = account.network.request(Api.functions.messages.readMessageContents(id: [id.id]), solvgramBypassFilter: true)
                |> map { result -> Bool in
                    if case let .affectedMessages(data) = result {
                        account.stateManager.addUpdateGroups([.updatePts(pts: data.pts, ptsCount: data.ptsCount)])
                    }
                    return true
                }
                |> `catch` { _ -> Signal<Bool, NoError> in return .single(false) }
            }
            return report
            |> mapToSignal { success -> Signal<Bool, NoError> in
                guard success else {
                    return .single(false)
                }
                return account.postbox.transaction { transaction -> Bool in
                    SolvgramMessageArchive.shared.unmarkSelfDestructing(id, accountPeerId: account.peerId)
                    _internal_deleteMessages(transaction: transaction, mediaBox: account.postbox.mediaBox, ids: [id])
                    return true
                }
            }
        }
    }
}

public extension TelegramEngine.Messages {
    /// Read Now (the chat's Solvgram button): tells the server the chat is read up to its last
    /// message, past Ghost Mode, which otherwise keeps read receipts from it.
    func solvgramReadNow(peerId: EnginePeer.Id) -> Signal<Bool, NoError> {
        return _internal_solvgramReadNow(account: self.account, peerId: peerId)
    }
}

/// MARK: Solvgram — a peer id from its stored value (PeerId.toInt64), for Ghost Mode exceptions.
public func solvgramEnginePeerId(_ value: Int64) -> EnginePeer.Id {
    return PeerId(value)
}

/// Tells the server the chat is read up to its last message, past Ghost Mode (Read Now, Read on Action).
func _internal_solvgramReadNow(account: Account, peerId: PeerId) -> Signal<Bool, NoError> {
    return account.postbox.transaction { transaction -> (Peer?, MessageIndex?) in
        return (transaction.getPeer(peerId), transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud))
    }
    |> mapToSignal { peer, index -> Signal<Bool, NoError> in
        guard let peer, let index else {
            return .single(false)
        }
        if peerId.namespace == Namespaces.Peer.CloudChannel {
            guard let inputChannel = apiInputChannel(peer) else {
                return .single(false)
            }
            return account.network.request(Api.functions.channels.readHistory(channel: inputChannel, maxId: index.id.id), solvgramBypassFilter: true)
            |> map { result -> Bool in
                if case .boolTrue = result { return true }
                return false
            }
            |> `catch` { _ -> Signal<Bool, NoError> in return .single(false) }
        } else if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup {
            guard let inputPeer = apiInputPeer(peer) else {
                return .single(false)
            }
            return account.network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: index.id.id), solvgramBypassFilter: true)
            |> map { result -> Bool in
                if case let .affectedMessages(data) = result {
                    account.stateManager.addUpdateGroups([.updatePts(pts: data.pts, ptsCount: data.ptsCount)])
                }
                return true
            }
            |> `catch` { _ -> Signal<Bool, NoError> in return .single(false) }
        } else {
            return .single(false)
        }
    }
}

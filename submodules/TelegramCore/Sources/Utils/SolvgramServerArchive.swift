import Foundation
import Security
import SwiftSignalKit
import SGSimpleSettings

public struct SolvgramServerArchiveEntry: Decodable {
    public let sequence: Int64
    public let chatId: String
    public let messageId: Int32
    public let deleted: Bool
    public let disappearing: Bool
    public let messageTl: Data
    public let previousTexts: [String]
    public let mediaRevision: Int64?
    public let mediaSize: Int64?
    public let observedAt: Double?
    public let previousTextDates: [Double]?

    public func retained(after cutoff: Date) -> SolvgramServerArchiveEntry? {
        guard let observed = self.observedAt, observed > cutoff.timeIntervalSince1970 else { return nil }
        let indices = self.previousTexts.indices.filter { index in
            guard let dates = self.previousTextDates, index < dates.count else { return false }
            return dates[index] > cutoff.timeIntervalSince1970
        }
        return SolvgramServerArchiveEntry(sequence: self.sequence, chatId: self.chatId, messageId: self.messageId,
            deleted: self.deleted, disappearing: self.disappearing, messageTl: self.messageTl,
            previousTexts: indices.map { self.previousTexts[$0] }, mediaRevision: self.mediaRevision,
            mediaSize: self.mediaSize, observedAt: self.observedAt,
            previousTextDates: indices.map { self.previousTextDates![$0] })
    }
}

struct SolvgramServerArchivePage: Decodable {
    let accountId: String
    let cursor: Int64
    let hasMore: Bool
    let entries: [SolvgramServerArchiveEntry]
    let peersTl: [Data]
}

public struct SolvgramServerArchiveState: Equatable {
    public var connected = false
    public var busy = false
    public var lastSync: Date?
    public var restored = 0
    public var error: String?
    public var serverOnline: Bool?
    public var endpoint = SolvgramServerArchive.defaultEndpoint
    public var cacheCount = 0
    public var cacheBytes: Int64 = 0
    public var clearing = false
}

public struct SolvgramLocatorProfile: Decodable {
    public let id: String
    public let reference: String
    public let peerId: String?
    public let title: String
    public let enabled: Int
    public let checkedAt: Double?
    public let error: String?
}

public struct SolvgramLocatorState: Decodable {
    public let accountId: String
    public let online: Bool
    public let profiles: [SolvgramLocatorProfile]
}

private struct SolvgramArchiveCredentials: Codable {
    let accountId: String
    let endpoint: String
    let token: String
}

private enum SolvgramArchiveError: Error {
    case http(Int), invalidResponse, keychain, invalidEndpoint, localArchive
}

private final class SolvgramArchiveSignalWait<Value> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    let disposable = MetaDisposable()

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        self.lock.lock()
        if let result = self.result {
            self.lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func finish(_ result: Result<Value, Error>) {
        self.lock.lock()
        guard self.result == nil else { self.lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        self.lock.unlock()
        continuation?.resume(with: result)
        self.disposable.dispose()
    }
}

private func solvgramArchiveAwait<Value>(_ signal: Signal<Value, NoError>) async throws -> Value {
    let wait = SolvgramArchiveSignalWait<Value>()
    return try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { continuation in
            wait.install(continuation)
            wait.disposable.set(signal.start(next: { wait.finish(.success($0)) }))
        }
    }, onCancel: { wait.finish(.failure(CancellationError())) })
}

/// Refuse redirects so a device token can never be forwarded to a different origin.
private final class SolvgramArchiveSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Owned by one account context. Networking runs only while the main app is active;
/// the server continues collecting independently. All public controls run on main.
public final class SolvgramServerArchive {
    /// No built-in server: a self-hosted endpoint is entered by the user.
    public static let defaultEndpoint = ""
    /// Server work is frozen: no pairing, sync, timer or locator requests are made.
    /// Local capture of deleted, edited and disappearing messages does not depend on this.
    public static let serverFeaturesEnabled = false
    private let engine: TelegramEngine
    private let accountId: String
    private let key: String
    private let statePromise = ValuePromise<SolvgramServerArchiveState>(SolvgramServerArchiveState(), ignoreRepeated: true)
    private var value = SolvgramServerArchiveState()
    private var credentials: SolvgramArchiveCredentials?
    private var foreground = false
    private var stopped = false
    private var timer: DispatchSourceTimer?
    private var foregroundDisposable: Disposable?
    private var operation: Task<Void, Never>?
    private let session: URLSession
    private let cache: SolvgramLocalArchiveStore
    private var cacheGeneration = 0

    public var state: Signal<SolvgramServerArchiveState, NoError> { self.statePromise.get() }
    public var currentState: SolvgramServerArchiveState { self.value }

    /// Reuses this account's paired server and Keychain token. Profile monitoring
    /// runs on the server; this call only reads or updates its explicit watch list.
    @MainActor public func locatorControl(_ body: [String: String]? = nil) async throws -> SolvgramLocatorState {
        guard Self.serverFeaturesEnabled, let credentials = self.credentials, !self.stopped else { throw SolvgramArchiveError.http(401) }
        let data = try await self.request(endpoint: credentials.endpoint, path: "/v1/locator", credentials: credentials, body: body)
        let state = try Self.decoder().decode(SolvgramLocatorState.self, from: data)
        guard state.accountId == self.accountId, self.credentials?.token == credentials.token else { throw SolvgramArchiveError.invalidResponse }
        return state
    }

    public init(account: Account, active: Signal<Bool, NoError>) {
        self.engine = TelegramEngine(account: account)
        self.accountId = String(account.peerId.id._internalGetInt64Value())
        self.key = "SolvgramServerArchive.\(self.accountId)"
        self.cache = SolvgramLocalArchiveStore.shared(accountId: self.accountId)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: configuration, delegate: SolvgramArchiveSessionDelegate(), delegateQueue: nil)
        if let data = Self.readKeychain(account: self.accountId),
           let credentials = try? JSONDecoder().decode(SolvgramArchiveCredentials.self, from: data), credentials.accountId == self.accountId {
            self.credentials = credentials
            self.value.connected = true
            self.value.endpoint = credentials.endpoint
        }
        self.value.lastSync = UserDefaults.standard.object(forKey: self.key + ".lastSync") as? Date
        self.statePromise.set(self.value)
        self.foregroundDisposable = (active |> deliverOnMainQueue).start(next: { [weak self] active in
            guard let self, !self.stopped else { return }
            self.foreground = active
            if active {
                // SolvgramDeviceCache owns clearing and resumes an interrupted clear itself.
                if Self.serverFeaturesEnabled { self.syncNow() }
            }
        })
        if Self.serverFeaturesEnabled {
            self.startSyncTimer()
        }
        self.refreshCacheStats()
    }

    private func startSyncTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            guard let self, self.foreground else { return }
            self.syncNow()
        }
        timer.resume()
        self.timer = timer
    }

    deinit { self.stop() }

    public func stop() {
        self.stopped = true
        self.operation?.cancel()
        self.timer?.cancel()
        self.foregroundDisposable?.dispose()
        self.session.invalidateAndCancel()
    }

    private func publish() { self.statePromise.set(self.value) }

    public func refreshCacheStats() {
        let cache = self.cache
        let generation = self.cacheGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try cache.statistics() }
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.cacheGeneration == generation else { return }
                if case let .success(stats) = result {
                    self.value.cacheCount = stats.messages
                    self.value.cacheBytes = stats.bytes
                } else { self.value.error = "localArchive" }
                self.publish()
            }
        }
    }

    private func entriesAfterClear(_ entries: [SolvgramServerArchiveEntry]) throws -> [SolvgramServerArchiveEntry] {
        let cutoffs = try self.cache.clearCutoffs()
        return entries.compactMap { original in
            guard (!original.disappearing || (original.isAutoDeletingMessage ? UserDefaults.standard.bool(forKey: "LeadAntiAutoDelete") : SolvgramSettings.keepSelfDestructing)),
                  (!original.deleted || original.disappearing || SolvgramSettings.saveDeleted),
                  (original.deleted || original.disappearing || SolvgramSettings.saveEdits),
                  let entry = original.retained(afterCacheClear: cutoffs) else { return nil }
            let media = entry.disappearing || SolvgramCachePreferences.downloadMedia
            return SolvgramServerArchiveEntry(sequence: entry.sequence, chatId: entry.chatId, messageId: entry.messageId,
                deleted: entry.deleted, disappearing: entry.disappearing, messageTl: entry.messageTl,
                previousTexts: SolvgramSettings.saveEdits ? entry.previousTexts : [],
                mediaRevision: media ? entry.mediaRevision : nil, mediaSize: media ? entry.mediaSize : nil,
                observedAt: entry.observedAt, previousTextDates: SolvgramSettings.saveEdits ? entry.previousTextDates : [])
        }
    }

    public func connect(endpoint: String, code: String) {
        guard Self.serverFeaturesEnabled, !self.value.busy, !self.stopped else { return }
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else {
            self.value.error = "invalidEndpoint"
            self.publish()
            return
        }
        let endpoint = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.value.busy = true
        self.value.error = nil
        self.publish()
        self.operation = Task { [weak self] in
            guard let self else { return }
            do {
                struct Pair: Decodable { let token: String; let accountId: String }
                let data = try await self.request(endpoint: endpoint, path: "/v1/pair", body: ["code": code, "account_id": self.accountId])
                let pair = try Self.decoder().decode(Pair.self, from: data)
                guard pair.accountId == self.accountId, pair.token.count >= 32 else { throw SolvgramArchiveError.invalidResponse }
                try Task.checkCancellation()
                let credentials = SolvgramArchiveCredentials(accountId: self.accountId, endpoint: endpoint, token: pair.token)
                try Self.writeKeychain(account: self.accountId, data: JSONEncoder().encode(credentials))
                await MainActor.run {
                    guard !Task.isCancelled, !self.stopped else { return }
                    self.credentials = credentials
                    self.value.connected = true
                    self.value.endpoint = endpoint
                    self.value.busy = false
                    self.operation = nil
                    UserDefaults.standard.removeObject(forKey: self.key + ".cursor")
                    for key in [SolvgramSettings.Key.saveDeleted, SolvgramSettings.Key.saveEdits, SolvgramSettings.Key.keepSelfDestructing] {
                        UserDefaults.standard.set(true, forKey: key)
                    }
                    self.publish()
                    self.syncNow()
                }
            } catch {
                await self.failed(error)
            }
        }
    }

    public func syncNow() {
        // Never sync over a device-cache clear in progress.
        if (try? self.cache.hasPendingClear()) == true { return }
        guard Self.serverFeaturesEnabled, let credentials = self.credentials, !self.value.busy, !self.stopped else { return }
        self.value.busy = true
        self.value.error = nil
        self.publish()
        self.operation = Task { [weak self] in
            guard let self else { return }
            do {
                struct ServerStatus: Decodable { let accountId: String; let connected: Bool }
                let statusData = try await self.request(endpoint: credentials.endpoint, path: "/v1/status", credentials: credentials)
                let serverStatus = try Self.decoder().decode(ServerStatus.self, from: statusData)
                guard serverStatus.accountId == self.accountId else { throw SolvgramArchiveError.invalidResponse }
                var cursor = UserDefaults.standard.bool(forKey: self.key + ".localArchiveV1") ? (UserDefaults.standard.object(forKey: self.key + ".cursor") as? NSNumber)?.int64Value ?? 0 : 0
                var count = 0
                while true {
                    try Task.checkCancellation()
                    let data = try await self.request(endpoint: credentials.endpoint, path: "/v1/changes?after=\(cursor)&limit=50", credentials: credentials)
                    let page = try Self.decoder().decode(SolvgramServerArchivePage.self, from: data)
                    guard page.accountId == self.accountId, !page.hasMore || page.cursor > cursor else { throw SolvgramArchiveError.invalidResponse }
                    let retainedEntries = try self.entriesAfterClear(page.entries)
                    let entries = try await solvgramArchiveAwait(self.engine.messages.solvgramServerArchiveAllowedEntries(retainedEntries))
                    var files = try await solvgramArchiveAwait(self.engine.messages.solvgramServerArchiveCachedMedia(entries))
                    let needed = Set(entries.compactMap { $0.mediaRevision }).filter { files[$0] == nil }
                    var temporaryFiles: [String] = []
                    do {
                        for revision in needed {
                            try Task.checkCancellation()
                            var request = self.makeRequest(endpoint: credentials.endpoint, path: "/v1/media/\(revision)", credentials: credentials)
                            request.timeoutInterval = 120
                            let (url, response) = try await self.session.download(for: request)
                            defer { try? FileManager.default.removeItem(at: url) }
                            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw SolvgramArchiveError.invalidResponse }
                            let expected = entries.first(where: { $0.mediaRevision == revision })?.mediaSize
                            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
                            guard size == expected else { throw SolvgramArchiveError.invalidResponse }
                            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("solvgram-archive-" + UUID().uuidString)
                            try FileManager.default.moveItem(at: url, to: temporary)
                            files[revision] = temporary.path
                            temporaryFiles.append(temporary.path)
                        }
                        try Task.checkCancellation()
                        let imported = try await solvgramArchiveAwait(self.engine.messages.solvgramImportServerArchive(entries: entries, peers: page.peersTl, mediaFiles: files))
                        guard let imported else { throw SolvgramArchiveError.invalidResponse }
                        guard let items = try await solvgramArchiveAwait(self.engine.messages.solvgramServerArchiveCacheItems(entries)) else { throw SolvgramArchiveError.invalidResponse }
                        var assets: [String: URL] = [:]
                        let revisions = Dictionary(entries.compactMap { entry in entry.mediaRevision.map { ("\(entry.chatId)_\(entry.messageId)", $0) } }, uniquingKeysWith: { _, last in last })
                        for item in items {
                            if let revision = revisions[item.id], let path = files[revision], let file = item.attachments.first {
                                assets[file.id] = URL(fileURLWithPath: path)
                            }
                        }
                        guard try await solvgramArchiveAwait(self.engine.messages.solvgramSaveServerArchiveCache(items, assets: assets)) else { throw SolvgramArchiveError.localArchive }
                        count += imported
                    } catch {
                        for path in temporaryFiles { try? FileManager.default.removeItem(atPath: path) }
                        throw error
                    }
                    for path in temporaryFiles { try? FileManager.default.removeItem(atPath: path) }
                    cursor = page.cursor
                    // Persist the cursor only after media and the message transaction succeeded.
                    UserDefaults.standard.set(NSNumber(value: cursor), forKey: self.key + ".cursor")
                    if !page.hasMore { break }
                }
                let restoredCount = count
                await MainActor.run {
                    guard !Task.isCancelled, !self.stopped else { return }
                    self.value.busy = false
                    self.value.restored += restoredCount
                    self.value.serverOnline = serverStatus.connected
                    self.value.error = serverStatus.connected ? nil : "collectorOffline"
                    self.value.lastSync = Date()
                    UserDefaults.standard.set(true, forKey: self.key + ".localArchiveV1")
                    UserDefaults.standard.set(self.value.lastSync, forKey: self.key + ".lastSync")
                    self.operation = nil
                    self.publish()
                    self.refreshCacheStats()
                }
            } catch {
                await self.failed(error)
            }
        }
    }

    public func disconnect() {
        self.operation?.cancel()
        let credentials = self.credentials
        self.credentials = nil
        Self.deleteKeychain(account: self.accountId)
        UserDefaults.standard.removeObject(forKey: self.key + ".cursor")
        self.value = SolvgramServerArchiveState()
        self.refreshCacheStats()
        self.publish()
        if let credentials {
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.request(endpoint: credentials.endpoint, path: "/v1/disconnect", credentials: credentials, body: [:])
            }
        }
    }

    @MainActor private func failed(_ error: Error) {
        guard !self.stopped, !Task.isCancelled, !(error is CancellationError) else { return }
        self.value.busy = false
        self.value.clearing = false
        self.operation = nil
        if case SolvgramArchiveError.http(403) = error {
            self.value.error = "invalidPairing"
        } else if case SolvgramArchiveError.http(401) = error {
            self.value.error = "unauthorized"
        } else if case SolvgramArchiveError.keychain = error {
            self.value.error = "keychain"
        } else if error is CocoaError {
            self.value.error = "localArchive"
        } else if case SolvgramArchiveError.localArchive = error {
            self.value.error = "localArchive"
        } else if case SolvgramArchiveError.invalidResponse = error {
            self.value.error = "archiveFormat"
        } else if error is DecodingError {
            self.value.error = "archiveFormat"
        } else {
            self.value.error = "connection"
        }
        self.publish()
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func makeRequest(endpoint: String, path: String, credentials: SolvgramArchiveCredentials?) -> URLRequest {
        var request = URLRequest(url: URL(string: endpoint + path)!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let credentials {
            request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
            request.setValue(self.accountId, forHTTPHeaderField: "X-Solvgram-Account")
        }
        return request
    }

    private func request(endpoint: String, path: String, credentials: SolvgramArchiveCredentials? = nil, body: [String: String]? = nil) async throws -> Data {
        var request = self.makeRequest(endpoint: endpoint, path: path, credentials: credentials)
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SolvgramArchiveError.invalidResponse }
        guard response.statusCode == 200 else { throw SolvgramArchiveError.http(response.statusCode) }
        return data
    }

    private static func query(account: String) -> [String: Any] {
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.solvgram.server-archive", kSecAttrAccount as String: account]
    }

    private static func readKeychain(account: String) -> Data? {
        var query = Self.query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func writeKeychain(account: String, data: Data) throws {
        let query = Self.query(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            for (key, value) in attributes { add[key] = value }
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw SolvgramArchiveError.keychain }
        } else if status != errSecSuccess { throw SolvgramArchiveError.keychain }
    }

    private static func deleteKeychain(account: String) { _ = SecItemDelete(Self.query(account: account) as CFDictionary) }
}

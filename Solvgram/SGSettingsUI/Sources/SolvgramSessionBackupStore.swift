import Foundation
import AccountContext
import TelegramCore
import SwiftSignalKit
import SGKeychainBackupManager

struct SolvgramSessionBackupSummary {
    let id: String
    let name: String
    let userId: Int64
    let date: Date
    let loggedIn: Bool
}

protocol SolvgramSessionBackupManaging: AnyObject {
    var sessions: [SolvgramSessionBackupSummary] { get }
    var busy: Bool { get }
    var didUpdate: (() -> Void)? { get set }
    var didFinish: ((String?, Error?) -> Void)? { get set }
    func start()
    func stop()
    func createBackup()
    func restoreBackups()
    func deleteBackup(id: String?)
    func removeFromApp(id: String)
}

// Keep the original Codable fields and Keychain service: existing backups stay readable.
private struct SolvgramSessionBackup: Codable {
    var name: String?
    var date: Date
    let accountRecord: AccountRecord<TelegramAccountManagerTypes.Attribute>

    var peerId: Int64 { SolvgramSessionBackupStore.peerId(accountRecord) }
}

final class SolvgramSessionBackupStore: SolvgramSessionBackupManaging {
    private let context: AccountContext
    private let io = DispatchQueue(label: "app.solvgram.session-backup", qos: .userInitiated)
    private var recordsDisposable: Disposable?
    private var operationDisposable: Disposable?
    private var records: [AccountRecord<TelegramAccountManagerTypes.Attribute>] = []
    private var backups: [SolvgramSessionBackup] = []
    private var running = false
    private(set) var busy = false
    var didUpdate: (() -> Void)?
    var didFinish: ((String?, Error?) -> Void)?

    init(context: AccountContext) { self.context = context }
    deinit { self.recordsDisposable?.dispose(); self.operationDisposable?.dispose() }

    static func peerId(_ record: AccountRecord<TelegramAccountManagerTypes.Attribute>) -> Int64 {
        for attribute in record.attributes {
            if case let .backupData(data) = attribute { return data.data?.peerId ?? 0 }
        }
        return 0
    }

    private static func loggedOut(_ record: AccountRecord<TelegramAccountManagerTypes.Attribute>) -> Bool {
        record.attributes.contains { if case .loggedOut = $0 { return true }; return false }
    }

    var sessions: [SolvgramSessionBackupSummary] {
        let loggedIn = Set(self.records.filter { !Self.loggedOut($0) }.map(Self.peerId))
        return self.backups.sorted { $0.date > $1.date }.map { backup in
            let userId = EnginePeer.Id(backup.peerId).id._internalGetInt64Value()
            return SolvgramSessionBackupSummary(id: String(backup.peerId), name: backup.name ?? String(userId), userId: userId, date: backup.date, loggedIn: loggedIn.contains(backup.peerId))
        }
    }

    func start() {
        guard !self.running else { return }
        self.running = true
        self.recordsDisposable = (self.context.sharedContext.accountManager.accountRecords() |> deliverOnMainQueue).start(next: { [weak self] view in
            self?.records = view.records
            self?.didUpdate?()
        })
        self.load()
    }

    func stop() {
        self.running = false
        self.recordsDisposable?.dispose()
        self.recordsDisposable = nil
    }

    private static func readBackups() throws -> [SolvgramSessionBackup] {
        try KeychainBackupManager.shared.getAllSessons().compactMap { try? JSONDecoder().decode(SolvgramSessionBackup.self, from: $0) }.filter { $0.peerId != 0 }
    }

    private func load() {
        self.io.async { [weak self] in
            do {
                let backups = try Self.readBackups()
                DispatchQueue.main.async { [weak self] in self?.backups = backups; self?.didUpdate?() }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.didFinish?(nil, error) }
            }
        }
    }

    private func begin() -> Bool {
        guard !self.busy else { return false }
        self.busy = true
        self.didUpdate?()
        return true
    }

    private func finish(_ message: String?, error: Error? = nil) {
        self.busy = false
        self.didUpdate?()
        self.didFinish?(message, error)
    }

    private func keychainOperation(_ work: @escaping () throws -> String?) {
        self.io.async { [self] in
            let operation = Result { try work() }
            // Refresh after partial failures too, so successful writes are visible.
            let result = Result { try Self.readBackups() }
            DispatchQueue.main.async { [self] in
                let message: String?
                var failure: Error?
                switch operation {
                case let .success(value): message = value
                case let .failure(error): message = nil; failure = error
                }
                switch result {
                case let .success(backups): self.backups = backups
                case let .failure(error): failure = failure ?? error
                }
                self.finish(message, error: failure)
            }
        }
    }

    func createBackup() {
        guard self.begin() else { return }
        self.operationDisposable = (combineLatest(self.context.sharedContext.accountManager.accountRecords(), self.context.sharedContext.activeAccountsWithInfo)
        |> take(1) |> deliverOnMainQueue).start(next: { [weak self] view, accounts in
            guard let self else { return }
            var unique: [Int64: AccountRecord<TelegramAccountManagerTypes.Attribute>] = [:]
            for record in view.records where !Self.loggedOut(record) && Self.peerId(record) != 0 { unique[Self.peerId(record)] = record }
            let backups = unique.map { id, record -> SolvgramSessionBackup in
                let peer = accounts.1.first(where: { $0.peer.id == EnginePeer.Id(id) })?.peer
                let name = peer.map { peer in peer.addressName.map { "@" + $0 } ?? peer.debugDisplayTitle }
                return SolvgramSessionBackup(name: name, date: Date(), accountRecord: record)
            }
            self.keychainOperation {
                for backup in backups { try KeychainBackupManager.shared.saveSession(id: String(backup.peerId), JSONEncoder().encode(backup)) }
                return String(backups.count)
            }
        })
    }

    func restoreBackups() {
        guard self.begin() else { return }
        self.io.async { [self] in
            let result = Result { try Self.readBackups() }
            DispatchQueue.main.async { [self] in
                switch result {
                case let .failure(error): self.finish(nil, error: error)
                case let .success(backups):
                    self.operationDisposable = (self.context.sharedContext.accountManager.transaction { transaction -> Int in
                        let records = transaction.getRecords()
                        var existing = Set(records.map(Self.peerId))
                        var order = records.flatMap { record in record.attributes.compactMap { attribute -> Int32? in
                            if case let .sortOrder(value) = attribute { return value.order }; return nil
                        } }.max() ?? 0
                        var restored = 0
                        for backup in backups where backup.peerId != 0 && !existing.contains(backup.peerId) {
                            guard order < Int32.max else { break }
                            order += 1
                            var attributes = backup.accountRecord.attributes.filter { if case .sortOrder = $0 { return false }; return true }
                            attributes.append(.sortOrder(AccountSortOrderAttribute(order: order)))
                            let _ = transaction.createRecord(attributes)
                            existing.insert(backup.peerId)
                            restored += 1
                        }
                        return restored
                    } |> deliverOnMainQueue).start(next: { [weak self] restored in self?.finish(String(restored)) })
                }
            }
        }
    }

    func deleteBackup(id: String?) {
        guard self.begin() else { return }
        self.keychainOperation {
            if let id { try KeychainBackupManager.shared.deleteSession(for: id) }
            else { try KeychainBackupManager.shared.deleteAllSessions() }
            return nil
        }
    }

    func removeFromApp(id: String) {
        guard let peerId = Int64(id), self.begin() else { return }
        self.operationDisposable = (self.context.sharedContext.accountManager.transaction { transaction -> Void in
            for record in transaction.getRecords() where Self.peerId(record) == peerId {
                transaction.updateRecord(record.id, { _ in nil })
            }
        } |> deliverOnMainQueue).start(completed: { [weak self] in self?.finish(nil) })
    }
}

import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

public struct SolvgramDeviceCacheState: Equatable {
    public var clearing = false
    public var failed = false
    /// Bumped after every finished clear, so open screens recount.
    public var generation = 0
    public init() {}
}

/// The one owner of Solvgram's saved data on this device: counts, clears and resumes an
/// interrupted clear for every category (deleted, edits, disappearing, stories, media).
/// It depends only on data on the device; no server object is involved.
public final class SolvgramDeviceCache {
    private let engine: TelegramEngine
    private let accountPeerId: PeerId
    private let store: SolvgramLocalArchiveStore
    private let statePromise = ValuePromise<SolvgramDeviceCacheState>(SolvgramDeviceCacheState(), ignoreRepeated: true)
    private var value = SolvgramDeviceCacheState()
    private var activeDisposable: Disposable?
    private let operation = MetaDisposable()
    private var stopped = false

    public var state: Signal<SolvgramDeviceCacheState, NoError> { self.statePromise.get() }
    public var currentState: SolvgramDeviceCacheState { self.value }

    public init(account: Account, active: Signal<Bool, NoError>) {
        self.engine = TelegramEngine(account: account)
        self.accountPeerId = account.peerId
        self.store = SolvgramLocalArchiveStore.shared(accountId: String(account.peerId.id._internalGetInt64Value()))
        self.activeDisposable = (active |> deliverOnMainQueue).start(next: { [weak self] active in
            guard let self, active, !self.stopped else { return }
            self.resumePendingClear()
        })
    }

    deinit {
        self.activeDisposable?.dispose()
        self.operation.dispose()
    }

    public func stop() {
        self.stopped = true
        self.activeDisposable?.dispose()
        self.operation.dispose()
    }

    public func statistics() -> Signal<SolvgramDeviceCacheStatistics?, NoError> {
        return self.engine.messages.solvgramDeviceCacheStatistics()
    }

    /// Everything (all categories, no chat), one category, or one chat.
    public func clear(categories: Set<SolvgramCacheCategory>, peerId: EnginePeer.Id? = nil, completion: ((Bool) -> Void)? = nil) {
        guard !categories.isEmpty, !self.value.clearing, !self.stopped else {
            completion?(false)
            return
        }
        self.value.clearing = true
        self.value.failed = false
        self.publish()
        let signal: Signal<Bool, NoError>
        if let peerId {
            signal = self.engine.messages.solvgramClearChatCache(peerId: peerId, categories: categories)
        } else {
            if categories.contains(.stories) {
                SolvgramArchiveStorage.shared.removeStoryViews(accountPeerId: self.accountPeerId.toInt64())
            }
            let messageCategories = categories.intersection(SolvgramCacheCategory.messageCategories)
            signal = messageCategories.isEmpty ? .single(true) : self.clearMessages(messageCategories)
        }
        self.operation.set((signal |> deliverOnMainQueue).start(next: { [weak self] success in
            self?.finish(success)
            completion?(success)
        }))
    }

    /// A clear interrupted by the app closing finishes the next time the app is active.
    public func resumePendingClear() {
        guard !self.value.clearing, !self.stopped, (try? self.store.hasPendingClear()) == true else { return }
        guard let categories = try? self.store.pendingClearCategories() else { return }
        self.value.clearing = true
        self.value.failed = false
        self.publish()
        self.operation.set((self.clearMessages(categories.intersection(SolvgramCacheCategory.messageCategories)) |> deliverOnMainQueue).start(next: { [weak self] success in
            self?.finish(success)
        }))
    }

    /// The clear is journaled in the local store first, so it resumes after a crash.
    private func clearMessages(_ categories: Set<SolvgramCacheCategory>) -> Signal<Bool, NoError> {
        let store = self.store
        let engine = self.engine
        return Signal<([SolvgramLocalArchiveItem], Set<SolvgramCacheCategory>, Date?)?, NoError> { subscriber in
            do {
                let items = try store.beginClear(categories: categories)
                subscriber.putNext((items, try store.pendingClearCategories(), try store.pendingClearDate()))
            } catch {
                subscriber.putNext(nil)
            }
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(Queue.concurrentDefaultQueue())
        |> mapToSignal { prepared -> Signal<Bool, NoError> in
            guard let (items, selected, date) = prepared else {
                return .single(false)
            }
            return engine.messages.solvgramClearServerArchive(items, categories: selected, clearDate: date)
            |> map { _ -> Bool in
                do {
                    try store.finishClear()
                    return true
                } catch {
                    return false
                }
            }
        }
    }

    private func finish(_ success: Bool) {
        guard !self.stopped else { return }
        self.value.clearing = false
        self.value.failed = !success
        self.value.generation += 1
        self.publish()
    }

    private func publish() {
        self.statePromise.set(self.value)
    }
}

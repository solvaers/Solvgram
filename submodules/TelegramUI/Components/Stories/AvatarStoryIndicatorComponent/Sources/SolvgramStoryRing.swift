import Foundation
import CoreGraphics
import SGSimpleSettings

public struct SolvgramStoryIdentity: Equatable {
    public let accountPeerId: Int64
    public let peerId: Int64
    public init(accountPeerId: Int64, peerId: Int64) {
        self.accountPeerId = accountPeerId
        self.peerId = peerId
    }
    fileprivate var key: String { "\(self.accountPeerId):\(self.peerId)" }
    fileprivate var legacyKey: String { "\(self.peerId)" }
}

/// Keeps reused avatars scoped to their current account and peer, without polling defaults.
public final class SolvgramStoryRingObserver {
    private var token: NSObjectProtocol?
    private let updated: () -> Void
    public var identity: SolvgramStoryIdentity? {
        didSet {
            if identity != nil, self.token == nil {
                self.token = NotificationCenter.default.addObserver(forName: Notification.Name("SolvgramAnonymousStoryViewsDidChange"), object: nil, queue: .main) { [weak self] notification in
                    guard let self, let identity = self.identity, let key = notification.userInfo?["key"] as? String,
                          key == identity.key || key == identity.legacyKey else { return }
                    self.updated()
                }
            } else if identity == nil, let token = self.token {
                NotificationCenter.default.removeObserver(token)
                self.token = nil
            }
        }
    }
    public init(updated: @escaping () -> Void) { self.updated = updated }
    deinit { if let token = self.token { NotificationCenter.default.removeObserver(token) } }
    public var isAnonymous: Bool {
        guard let identity = self.identity else { return false }
        // Two-in-one: with Hide Story Views off the gray rings are hidden; the records stay.
        return SolvgramSettings.hideStoryViews && SolvgramArchiveStorage.shared.storiesViewedAnonymously(identity.key, legacyKey: identity.legacyKey)
    }
}

public enum SolvgramStoryRingDash {
    /// Round caps remain separated, and a segment begins and ends with a complete dash.
    public static func pattern(length: CGFloat, lineWidth: CGFloat, closed: Bool) -> [CGFloat] {
        let baseDash = max(2.0, lineWidth * 1.6)
        let gap = baseDash + lineWidth * 1.8
        let period = baseDash + gap
        guard length > 0.0 else { return [baseDash, gap] }
        if closed {
            let count = max(1.0, (length / period).rounded())
            let scale = length / (count * period)
            return [baseDash * scale, gap * scale]
        }
        let count = max(1.0, ((length + gap) / period).rounded())
        let dash = (length - (count - 1.0) * gap) / count
        return [count == 1.0 || dash < 0.5 ? max(length, 0.5) : dash, gap]
    }
}

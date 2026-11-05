import Foundation

// MARK: Solvgram — switches of the live Swift settings menu, read live from
// UserDefaults.standard so a toggle takes effect without restarting the app. The keys are the
// ones the Lead tweak used, so settings saved by an older Lead-injected build carry over.
public enum SolvgramSettings {
    public static let phoneNumbersDidChange = Notification.Name("SolvgramPhoneNumbersDidChange")
    public enum Key {
        public static let ghostMode = "LeadGhostModeEnabled"
        public static let hideOnline = "disableOnlineStatus"
        public static let hideReadReceipts = "disableMessageReadReceipt"
        public static let hideStoryViews = "disableStoriesReadReceipt"
        public static let hideAds = "disableAllAds"
        public static let saveDeleted = "LeadAntiRevoke"
        public static let saveEdits = "LeadAntiEdit"
        public static let keepSelfDestructing = "LeadAntiSelfDestruct"
        public static let allowProtectedContent = "disableForwardRestriction"
        public static let allowScreenshots = "disableScreenshotNotification"
        public static let visualStars = "LeadVisualStarsEnabled"
        public static let visualStarsAmount = "LeadVisualStarsAmount"
        public static let fakeLocation = "LeadFakeLocation"
        public static let fakeLatitude = "LeadSavedLatitude"
        public static let fakeLongitude = "LeadSavedLongitude"
        public static let deletedMessages = "SolvgramDeletedMessages"
        public static let editHistory = "SolvgramEditHistory"
        /// "front", "rear" or "ask"; absent means Solvgram's startTelescopeWithRearCam decides.
        public static let roundVideoCamera = "SolvgramRoundVideoCamera"
        /// "system" (or absent), "en" or "ru": the language of Solvgram's own menu and texts.
        public static let language = "SolvgramLanguage"
        /// "normal", "high", "cartoon", "low" or "robot".
        public static let voiceSpeed = "SolvgramVoiceTempoStep02"
        public static let voiceEffect = "SolvgramVoiceEffect"
        /// Followed by the effect name: its strength, 1...5.
        public static let voiceEffectLevelPrefix = "SolvgramVoiceEffectLevel."
        /// "real", "hidden" or "custom": the phone number shown in your own profile and settings.
        public static let phoneMode = "SolvgramPhoneMode"
        public static let customPhone = "SolvgramCustomPhone"
        /// "real" or "hidden": phone numbers in other people's profiles.
        public static let otherPhoneMode = "SolvgramOtherPhoneMode"
        /// [peer id (PeerId.toInt64) as a string: "hide" or "show"]: Ghost Mode exceptions.
        public static let ghostExceptions = "SolvgramGhostExceptions"
        /// The voice the Voice Changer switch in a chat turns back on.
        public static let lastVoiceEffect = "SolvgramLastVoiceEffect"
        /// Read on Action: sending a message in a chat reads it, past Ghost Mode. On unless switched off.
        public static let readOnAction = "SolvgramReadOnAction"
        /// [peer id (PeerId.toInt64) as a string: "save" or "skip"]: saving exceptions.
        public static let captureExceptions = "SolvgramCaptureExceptions"
        /// Followed by "deleted." or "edits." and a chat type: saving in that type of chat.
        public static let capturePrefix = "SolvgramCapture."
    }

    // MARK: Saving — what is kept by type of chat and per chat. Every switch is two-in-one:
    // off stops saving new items and hides the marks of those already saved; saved data stays.

    public enum CaptureKind: String, CaseIterable {
        case deleted
        case edits
    }

    public enum ChatKind: String, CaseIterable {
        case privateChats = "private"
        case groups
        case channels
    }

    public enum CaptureException: String {
        case save
        case skip
    }

    private static func captureKey(_ kind: CaptureKind, _ chat: ChatKind) -> String {
        return Key.capturePrefix + kind.rawValue + "." + chat.rawValue
    }

    /// Saving of this kind in this type of chat. On unless switched off.
    public static func captures(_ kind: CaptureKind, in chat: ChatKind) -> Bool {
        return UserDefaults.standard.object(forKey: captureKey(kind, chat)) as? Bool ?? true
    }

    public static func setCaptures(_ kind: CaptureKind, in chat: ChatKind, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: captureKey(kind, chat))
    }

    public static var captureExceptions: [Int64: CaptureException] {
        let raw = UserDefaults.standard.dictionary(forKey: Key.captureExceptions) as? [String: String] ?? [:]
        var result: [Int64: CaptureException] = [:]
        for (key, value) in raw {
            if let peerId = Int64(key), let exception = CaptureException(rawValue: value) {
                result[peerId] = exception
            }
        }
        return result
    }

    public static func captureException(peerId: Int64) -> CaptureException? {
        let raw = UserDefaults.standard.dictionary(forKey: Key.captureExceptions) as? [String: String]
        return raw?["\(peerId)"].flatMap(CaptureException.init(rawValue:))
    }

    public static func setCaptureException(_ exception: CaptureException?, peerId: Int64) {
        var raw = UserDefaults.standard.dictionary(forKey: Key.captureExceptions) as? [String: String] ?? [:]
        raw["\(peerId)"] = exception?.rawValue
        UserDefaults.standard.set(raw, forKey: Key.captureExceptions)
    }

    /// Whether this kind is saved, and its saved items marked, in a chat: the main switch first,
    /// then the chat's exception, then its chat type (unknown type: saved).
    public static func captures(_ kind: CaptureKind, peerId: Int64, chat: ChatKind?) -> Bool {
        guard kind == .deleted ? saveDeleted : saveEdits else { return false }
        if let exception = captureException(peerId: peerId) {
            return exception == .save
        }
        guard let chat else { return true }
        return captures(kind, in: chat)
    }

    private static func bool(_ key: String) -> Bool {
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Solvgram's own texts are Russian when chosen, or when the system language is Russian; English otherwise.
    public static var isRussian: Bool {
        switch UserDefaults.standard.string(forKey: Key.language) {
        case "ru":
            return true
        case "en":
            return false
        default:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") ?? false
        }
    }

    public static var ghostMode: Bool {
        return bool(Key.ghostMode)
    }

    /// A Ghost Mode option: on only while Ghost Mode itself is on.
    public static func ghost(_ key: String) -> Bool {
        return ghostMode && bool(key)
    }

    // MARK: Ghost Mode exceptions — a chat that always hides or never hides, whatever Ghost Mode is.

    public enum GhostException: String {
        case hide
        case show
    }

    public static var ghostExceptions: [Int64: GhostException] {
        let raw = UserDefaults.standard.dictionary(forKey: Key.ghostExceptions) as? [String: String] ?? [:]
        var result: [Int64: GhostException] = [:]
        for (key, value) in raw {
            if let peerId = Int64(key), let exception = GhostException(rawValue: value) {
                result[peerId] = exception
            }
        }
        return result
    }

    public static func ghostException(peerId: Int64) -> GhostException? {
        let raw = UserDefaults.standard.dictionary(forKey: Key.ghostExceptions) as? [String: String]
        return raw?["\(peerId)"].flatMap(GhostException.init(rawValue:))
    }

    public static func setGhostException(_ exception: GhostException?, peerId: Int64) {
        var raw = UserDefaults.standard.dictionary(forKey: Key.ghostExceptions) as? [String: String] ?? [:]
        raw["\(peerId)"] = exception?.rawValue
        UserDefaults.standard.set(raw, forKey: Key.ghostExceptions)
    }

    /// Whether Ghost Mode applies in this chat: its exception if it has one, else Ghost Mode itself.
    public static func ghostActive(peerId: Int64?) -> Bool {
        if let peerId, let exception = ghostException(peerId: peerId) {
            return exception == .hide
        }
        return ghostMode
    }

    /// A Ghost Mode option, in this chat.
    public static func ghost(_ key: String, peerId: Int64?) -> Bool {
        return ghostActive(peerId: peerId) && bool(key)
    }

    public static func hidesReadReceipts(peerId: Int64?) -> Bool {
        return ghost(Key.hideReadReceipts, peerId: peerId)
    }

    public static var hideOnline: Bool { return ghost(Key.hideOnline) }
    public static var hideReadReceipts: Bool { return ghost(Key.hideReadReceipts) }
    public static var hideStoryViews: Bool { return bool(Key.hideStoryViews) }
    public static var hideAds: Bool { return bool(Key.hideAds) }
    public static var readOnAction: Bool {
        return UserDefaults.standard.object(forKey: Key.readOnAction) as? Bool ?? true
    }
    public static var saveDeleted: Bool { return bool(Key.saveDeleted) }
    public static var saveEdits: Bool { return bool(Key.saveEdits) }
    public static var keepSelfDestructing: Bool { return bool(Key.keepSelfDestructing) }
    public static var allowProtectedContent: Bool { return bool(Key.allowProtectedContent) }
    public static var allowScreenshots: Bool { return bool(Key.allowScreenshots) }

    /// The voice changer's effect for sent voice messages ("normal" when off).
    public static var voiceEffect: String {
        return UserDefaults.standard.string(forKey: Key.voiceEffect) ?? "normal"
    }

    /// UI 1x is the revised preset, at 0.75 of its original tempo.
    public static var voiceSpeedStep: Int {
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: Key.voiceSpeed) as? NSNumber { return min(5, max(1, value.intValue)) }
        if let old = defaults.object(forKey: "SolvgramVoiceTempo") as? NSNumber {
            let oldValues: [Float] = [0.5, 0.75, 1, 1.25, 1.5]
            let rate = oldValues[min(5, max(1, old.intValue)) - 1]
            let index = (0..<5).min { abs(Self.voiceSpeedValues[$0] - rate) < abs(Self.voiceSpeedValues[$1] - rate) }! + 1
            defaults.set(index, forKey: Key.voiceSpeed)
            return index
        }
        // Compatibility with the previous release's absolute tempo steps.
        let previous = defaults.integer(forKey: "SolvgramVoiceSpeed")
        if previous > 0 && previous != 2 {
            let rate: Float = [0.25, 0.5, 0.75, 1.0][min(4, max(1, previous)) - 1]
            let index = (0..<5).min { abs(Self.voiceSpeedValues[$0] * 0.75 - rate) < abs(Self.voiceSpeedValues[$1] * 0.75 - rate) }! + 1
            defaults.set(index, forKey: Key.voiceSpeed)
            return index
        }
        return 3
    }
    private static let voiceSpeedValues: [Float] = [0.6, 0.8, 1, 1.2, 1.4]
    public static var voiceSpeed: Float { voiceSpeedValues[voiceSpeedStep - 1] * 0.75 }
    public static func storyCaptureProtected(_ restricted: Bool) -> Bool {
        return restricted && !allowProtectedContent && !allowScreenshots
    }

    /// The strength of a voice effect, 1...5 (3 until set).
    public static func voiceEffectLevel(_ effect: String) -> Int {
        let value = UserDefaults.standard.integer(forKey: Key.voiceEffectLevelPrefix + effect)
        return value == 0 ? 3 : min(5, max(1, value))
    }

    /// The phone number to show in your own profile instead of the real one (Phone Number: Custom),
    /// nil when it is not set.
    public static var customPhoneNumber: String? {
        guard UserDefaults.standard.string(forKey: Key.phoneMode) == "custom" else {
            return nil
        }
        let value = UserDefaults.standard.string(forKey: Key.customPhone)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    public enum PhoneNumberMode: String {
        case real, hidden, custom
    }

    /// Preserve the old hiding preference while changing its presentation to a spoiler.
    public static func phoneNumberMode(isOwn: Bool, legacyHidden: Bool = false, defaults: UserDefaults = .standard) -> PhoneNumberMode {
        if !isOwn {
            return defaults.string(forKey: Key.otherPhoneMode) == "hidden" ? .hidden : .real
        }
        if legacyHidden { return .hidden }
        return PhoneNumberMode(rawValue: defaults.string(forKey: Key.phoneMode) ?? "real") ?? .real
    }

    /// Round videos ask which camera to record with each time.
    public static var roundVideoCameraAsks: Bool {
        return UserDefaults.standard.string(forKey: Key.roundVideoCamera) == "ask"
    }

    /// The Stars balance shown to the user instead of the real one, nil when the option is off.
    public static var visualStarsAmount: Int64? {
        guard bool(Key.visualStars) else {
            return nil
        }
        return Int64(UserDefaults.standard.integer(forKey: Key.visualStarsAmount))
    }

    /// The point shared instead of the real GPS position, nil when spoofing is off or no point
    /// was picked yet.
    public static var fakeLocation: (latitude: Double, longitude: Double)? {
        let defaults = UserDefaults.standard
        guard bool(Key.fakeLocation), defaults.object(forKey: Key.fakeLatitude) != nil,
              defaults.object(forKey: Key.fakeLongitude) != nil else {
            return nil
        }
        let latitude = defaults.double(forKey: Key.fakeLatitude)
        let longitude = defaults.double(forKey: Key.fakeLongitude)
        guard latitude.isFinite, longitude.isFinite,
              (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return nil }
        return (latitude, longitude)
    }
}

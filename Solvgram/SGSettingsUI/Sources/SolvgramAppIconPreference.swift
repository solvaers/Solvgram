import Foundation

/// UIKit can report nil after acknowledging an alternate icon, including on the
/// next launch. Keep the last confirmed change independently of any settings view.
public enum SolvgramAppIconPreference {
    private static let key = "SolvgramLastConfirmedAppIcon"
    private static let primary = "SolvDefault"
    private static let names: Set<String> = [
        "SolvDefault", "SolvBlackBlue", "SolvBlue", "SolvSilver", "SolvBlack", "SolvWhite"
    ]

    /// Reset only icons that no longer ship (the v100028 colours and the removed
    /// Premium icons). A confirmed supported choice wins
    /// over a stale native getter, just as it does during normal restoration.
    public static func needsRemovedIconReset(systemName: String?, defaults: UserDefaults = .standard) -> Bool {
        let removed: Set<String> = ["SolvRose", "SolvLilac", "SolvMint", "SolvCoral", "SolvGraphite", "SolvIce", "SolvPremiumLight", "SolvPremiumDark"]
        let saved = defaults.string(forKey: self.key)
        if let saved, names.contains(saved) { return false }
        if let systemName, names.contains(systemName) { return false }
        return removed.contains(systemName ?? "") || removed.contains(saved ?? "")
    }

    /// An obsolete-icon reset must not overwrite a newer supported user choice
    /// if UIKit acknowledges the startup migration after the user has selected it.
    public static func recordRemovedIconReset(defaults: UserDefaults = .standard) {
        if let saved = defaults.string(forKey: self.key), names.contains(saved) { return }
        self.recordSuccessfulChange(nil, defaults: defaults)
    }

    public static func currentName(systemName: String?, defaults: UserDefaults = .standard) -> String? {
        if let saved = defaults.string(forKey: self.key), self.names.contains(saved) {
            return saved == self.primary ? nil : saved
        }
        // Migrate an existing installation when UIKit knows its current icon.
        // A nil read is ambiguous, so it must not create a saved Default value.
        if let systemName, self.names.contains(systemName) {
            self.recordSuccessfulChange(systemName, defaults: defaults)
            return systemName == self.primary ? nil : systemName
        }
        return nil
    }

    /// Call only after the system's completion reports success. The primary icon
    /// needs an explicit sentinel: an absent preference means no confirmed choice.
    public static func recordSuccessfulChange(_ name: String?, defaults: UserDefaults = .standard) {
        let name = name ?? self.primary
        guard self.names.contains(name) else { return }
        defaults.set(name, forKey: self.key)
    }
}

import Foundation

public let FALLBACK_BASE_BUNDLE_ID: String = "app.swiftgram.ios"

public func sgBaseBundleIdentifier() -> String {
    let baseBundleId: String
    if let bundleId: String = Bundle.main.bundleIdentifier {
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            if let lastDotRange: Range<String.Index> = bundleId.range(of: ".", options: [.backwards]) {
                baseBundleId = String(bundleId[..<lastDotRange.lowerBound])
            } else {
                baseBundleId = FALLBACK_BASE_BUNDLE_ID
            }
        } else {
            baseBundleId = bundleId
        }
    } else {
        baseBundleId = FALLBACK_BASE_BUNDLE_ID
    }
    return baseBundleId
}

// MARK: Solvgram
// A re-signed build (for example by a sideloading tool) usually gets a provisioning profile
// whose app groups are not "group.<bundle id>". Resolve the group the app was actually signed
// with: the conventional name first, then the groups listed in the embedded profile, taking the
// first one the system really gives a container for.

private func sgEmbeddedProfileAppGroups() -> [String] {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
          let data = try? Data(contentsOf: url),
          let start = data.range(of: Data("<?xml".utf8)),
          let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex) else {
        return []
    }
    let plistData = data.subdata(in: start.lowerBound ..< end.upperBound)
    guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
          let entitlements = plist["Entitlements"] as? [String: Any],
          let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
        return []
    }
    return groups
}

private let resolvedAppGroupIdentifier: String = {
    let conventional = "group.\(sgBaseBundleIdentifier())"
    let candidates = [conventional] + sgEmbeddedProfileAppGroups().filter { $0 != conventional }
    for candidate in candidates {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: candidate) != nil {
            return candidate
        }
    }
    return conventional
}()

public func sgAppGroupIdentifier() -> String {
    let result: String = resolvedAppGroupIdentifier

    #if DEBUG
    print("APP_GROUP_IDENTIFIER: \(result)")
    #endif

    return result
}

/// The app group container, or a directory inside the app's own sandbox when the build has no
/// usable app group (only the main app then uses the data, so nothing needs to be shared).
public func sgAppGroupContainerURL() -> URL? {
    if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sgAppGroupIdentifier()) {
        return url
    }
    guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
        return nil
    }
    let fallback = library.appendingPathComponent("AppGroupFallback", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
    } catch {
        return nil
    }
    return fallback
}

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

filegroup(
    name = "SGUIAssets",
    srcs = glob(["Images.xcassets/**"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "SGSettingsUI",
    module_name = "SGSettingsUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Solvgram/SGKeychainBackupManager:SGKeychainBackupManager",
        "//Solvgram/SolvgramIcons:SolvgramIcons",
        "//Solvgram/SGItemListUI:SGItemListUI",
        "//Solvgram/SGLogging:SGLogging",
        "//Solvgram/SGSimpleSettings:SGSimpleSettings",
        "//Solvgram/SGStrings:SGStrings",
        "//Solvgram/SGProUI:SGProUI", # MARK: Solvgram — SolvgramMenuBridge opens its screens
        "//submodules/SettingsUI:SettingsUI", # MARK: Solvgram
#        "//Solvgram/SGAPI:SGAPI",
        "//Solvgram/SGAPIToken:SGAPIToken",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/OverlayStatusController:OverlayStatusController",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AppBundle:AppBundle",
        "//submodules/TelegramUI/Components/Settings/PeerNameColorScreen",
        "//submodules/UndoUI:UndoUI",
        "//submodules/LocalizedPeerData:LocalizedPeerData", # MARK: Solvgram
    ],
    visibility = [
        "//visibility:public",
    ],
)

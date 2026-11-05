load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")


swift_library(
    name = "SGProUI",
    module_name = "SGProUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Solvgram/SGKeychainBackupManager:SGKeychainBackupManager",
        "//Solvgram/SGItemListUI:SGItemListUI",
        "//Solvgram/SGLogging:SGLogging",
        "//Solvgram/SGSimpleSettings:SGSimpleSettings",
        "//Solvgram/SGStrings:SGStrings",
        "//Solvgram/SGAPI:SGAPI",
        "//Solvgram/SGAPIToken:SGAPIToken",
        "//Solvgram/SGSwiftUI:SGSwiftUI",
        #
        "//submodules/SettingsUI:SettingsUI",
        #
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
    ],
    visibility = [
        "//visibility:public",
    ],
)

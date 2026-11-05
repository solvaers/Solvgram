load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: Solvgram
sgdeps = [
    "//Solvgram/SGDebugUI:SGDebugUI",
    "//Solvgram/SGLogging:SGLogging",
    "//Solvgram/SGLoggingComposer:SGLoggingComposer",
    "//Solvgram/SGSimpleSettings:SGSimpleSettings"
]
#

swift_library(
    name = "DebugSettingsUI",
    module_name = "DebugSettingsUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [ # MARK: Solvgram
        "//submodules/BuildConfig:BuildConfig",
        "//submodules/CrashReporting:CrashReporting",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/OverlayStatusController:OverlayStatusController",
        "//submodules/UndoUI:UndoUI",
        "//submodules/ContextUI:ContextUI",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AppBundle:AppBundle",
        "//submodules/GZip:GZip",
        "//third-party/ZipArchive:ZipArchive",
        "//submodules/InAppPurchaseManager:InAppPurchaseManager",
        "//submodules/TelegramVoip",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/AlertComponent",
        "//submodules/TelegramUI/Components/AlertComponent/AlertCheckComponent",
        "//submodules/WalletContext",
        "//submodules/CpuProfiler:CpuProfiler",
    ],
    visibility = [
        "//visibility:public",
    ],
)

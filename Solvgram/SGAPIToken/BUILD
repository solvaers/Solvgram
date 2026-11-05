load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGAPIToken",
    module_name = "SGAPIToken",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
        "//Solvgram/SGLogging:SGLogging",
        "//Solvgram/SGWebSettingsScheme:SGWebSettingsScheme",
        "//Solvgram/SGConfig:SGConfig",
        "//Solvgram/SGWebAppExtensions:SGWebAppExtensions",
    ],
    visibility = [
        "//visibility:public",
    ],
)

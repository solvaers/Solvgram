load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGGHSettings",
    module_name = "SGGHSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Solvgram/SGGHSettingsScheme:SGGHSettingsScheme",
        "//Solvgram/SGLogging:SGLogging",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
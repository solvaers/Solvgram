load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGRegDate",
    module_name = "SGRegDate",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Solvgram/SGRegDateScheme:SGRegDateScheme",
        "//Solvgram/SGSimpleSettings:SGSimpleSettings",
        "//Solvgram/SGAPI:SGAPI",
        "//Solvgram/SGAPIToken:SGAPIToken",
        "//Solvgram/SGDeviceToken:SGDeviceToken",
        "//Solvgram/SGStrings:SGStrings",

        "//submodules/AccountContext:AccountContext",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)
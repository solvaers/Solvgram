load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGAPI",
    module_name = "SGAPI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//Solvgram/SGLogging:SGLogging",
        "//Solvgram/SGWebAppExtensions:SGWebAppExtensions",
        "//Solvgram/SGSimpleSettings:SGSimpleSettings",
        "//Solvgram/SGWebSettingsScheme:SGWebSettingsScheme",
        "//Solvgram/SGRegDateScheme:SGRegDateScheme",
        "//Solvgram/SGRequests:SGRequests",
        "//Solvgram/SGConfig:SGConfig"
    ],
    visibility = [
        "//visibility:public",
    ],
)

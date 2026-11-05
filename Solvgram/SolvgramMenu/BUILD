load("@rules_cc//cc:objc_library.bzl", "objc_library")

# The native Swift menu is the production entry point. Keep only these image
# resources in the app; the legacy renderer remains available for old previews.
filegroup(
    name = "Resources",
    srcs = glob(["Resources/*.png"]),
    visibility = ["//visibility:public"],
)

# Legacy menu; not linked into the release app.
objc_library(
    name = "SolvgramMenu",
    srcs = glob(["Sources/*.m"]),
    hdrs = glob(["Sources/*.h"]),
    copts = ["-fobjc-arc"],
    sdk_frameworks = ["UIKit", "Foundation", "CoreGraphics", "MapKit", "CoreLocation", "UserNotifications"],
    data = glob(["Resources/*.png"]),
    alwayslink = True,
    visibility = ["//visibility:public"],
)

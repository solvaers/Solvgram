# File picker and read-eye regression audit

Build with `zsh Tests/SolvgramFilePickerAudit/build.sh`. Install the generated `/tmp/SolvgramFilePickerAudit/FilePickerAudit.app` in the iOS simulator and launch `app.solvgram.file-picker-audit`. The app writes `Documents/audit.json` and small read-eye renders.

This compiles the production file-resource implementation, complete picker controller. It uses the actual SwiftSignalKit delivery/disposal primitives and actual UIKit/Foundation file APIs. Engine storage identities and legacy navigation adapters are isolated; only synthetic documents in the audit app's container are accessed, with no Telegram account or external files. PDF thumbnail rasterization is outside the audit.

Cases cover literal percent signs, spaces and Unicode names, empty/missing files, bookmark roundtrip, byte-for-byte coordinated upload copy, thumbnails, cancellation, picker disappearance before the selected-file callback, duplicate callbacks, delegate retention/cleanup, interactive dismissal, and preserved open/import/export behavior. The asset catalog contains the exact 24pt production read-eye PDF; both menu tints and its uncrossed center are checked after explicit 8-bit RGBA decoding.

Real iCloud/third-party providers require device validation; this audit neither signs in nor sends messages.

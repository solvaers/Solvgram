# Solvgram menu preview

This harness covers the **legacy Objective-C menu**, not the screen Telegram
currently opens. Use `Tests/SolvgramSettingsPreview/` for release verification.

An isolated simulator app that compiles the production `SolvgramMenu.m` and
`SolvgramIcons.m` with a local settings bridge. It uses `app.solvgram.menu-preview`
and never opens or changes a Telegram account.

Build with `zsh Tests/SolvgramMenuPreview/build.sh`. Install the resulting
`/tmp/SolvgramMenuPreview/SolvgramMenuPreview.app` using `simctl`, then launch it.
It checks all 13 categories and 97 settings, the 14 vector icons, Ghost Mode
persistence, disabled options, grouped recording flags, bridge dependencies and
search results. A 40-second scripted tour saves PNGs and `report.json` under the
app's `Documents/MenuPreview` directory. Only normal-size featured controls have
an icon; the accessibility layout uses a compact status and wider text area.

The tour covers light/dark themes, English/Russian text, the largest accessibility
font size, a 375-point viewport and a landscape-sized viewport. Viewport resizing
checks layout; it is not a physical-device orientation test. The bridge is a test
double, so opening Telegram-specific destination screens is not exercised here.

Record the tour with `simctl io <device> recordVideo --codec=h264 <output.mov>`.
Copy the screenshots/report into `design/solvgram-icons/implementation-preview/`,
then run `swift -module-cache-path /tmp/solvgram-swift-cache
Tests/SolvgramMenuPreview/images.swift <absolute-preview-directory>` to extract
recorded frames and compose review sheets. Run the app without Reduced Motion
for the recorded transitions; production row updates also respect the system
Reduced Motion setting.

The main app's full release build is verified separately using Make.py.

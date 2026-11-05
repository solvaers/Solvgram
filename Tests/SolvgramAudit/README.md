# Solvgram source audit

The release 100023 audit covers Solvgram's additions since upstream commit
`e3a392272b182dbf975d4ac5fc33b40a5954d749` and the changes made during the audit.
See [the report](AUDIT-100023.md) for findings, scope and practical limits.

Run the account-free checks on macOS with the project's selected Xcode:

```sh
zsh Tests/SolvgramAudit/build.sh
python3 Tests/SolvgramAudit/filter.py
python3 Tests/SolvgramAudit/version.py
python3 Tests/SolvgramAudit/audio.py
```

The archive test compiles the production Foundation storage and settings. It
checks concurrent updates, reloads, limits, stable eviction order, original-text
retention, duplicate edits, legacy compatibility, account isolation and malformed
coordinates. Separate executable launches verify persistence across processes.
It uses temporary, dedicated UserDefaults suites and removes them afterwards.

The request-filter test compiles the production filter and settings. It checks
global Ghost Mode, per-chat exceptions, independent story hiding and passthrough
for unrelated methods. Constructor IDs and response types are checked against
the repository's JSON schema and the actual TL source used to generate the API.

The audio test compiles the actual packet loops, waveform packing and effect
renderer. Its injectable codec boundary deliberately rejects a packet or stream
finalization; it is not an Opus round-trip test. The DSP checks run all four effects
at levels 1, 3 and 5 using the native offline AVAudioEngine.

The first three checks also run before builds in the GitHub workflow. Native UI
checks use [SolvgramSettingsPreview](../SolvgramSettingsPreview/README.md), including
the actual navigation observer with an account-free stack signal. They check
normal and reduced motion, continuous/stepped slider reuse, five voice levels,
observer cleanup, icon persistence, search and switches.

`results-100023/` contains the final reports. Raw simulator movies and intermediate
screenshots stay local. The release IPA is validated separately after a full build;
the verifier checks active frameworks, alternate icon resources, recording recovery
and removal of the old Objective-C menu from the app executable.

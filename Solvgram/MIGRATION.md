# Solvgram naming and settings compatibility

The source tree, product target, own UI types and asset names now use Solvgram.
The app bundle identifier, application-group selection, account/session records,
Keychain payloads and existing settings keys retain their compatibility contracts.
No account data is deleted or recreated by the naming change.

Upstream authorship and license notices remain intact. Historical external
service identifiers (including the old app-group fallback and upstream service
configuration) are compatibility references, not Solvgram-owned network endpoints.
They must not be replaced with invented domains or bots. Unused associated-domain
entries for the upstream product were removed from the build configuration.

Voice tempo uses `SolvgramVoiceTempo`. Displayed 1x is 0.75 of the original preset.
The previous release's `SolvgramVoiceSpeed` is read only for migration: its former
default maps to the new default, while custom values map to the closest new tempo.
Normal voice bypasses processing and has no tempo controls.

The existing `customAppBadge` preference is retained. Recognized new values are
`solvgram.badge.ghost` and `solvgram.badge.none`; an empty/obsolete asset name falls
back to the Solvgram badge. The old paid selector is removed. Both live application
and startup use the same image resolver.

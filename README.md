<p align="center">
  <img src=".github/assets/solvgram-icon.png" width="120" alt="Solvgram">
</p>

<h1 align="center">Solvgram</h1>

<p align="center">An unofficial Telegram client for iOS, focused on privacy, keeping messages and a configurable interface.</p>

Solvgram is built on [Swiftgram](https://github.com/Swiftgram/Telegram-iOS), which is built on the [official Telegram iOS app](https://github.com/TelegramMessenger/Telegram-iOS). All of its settings are in one menu: **Settings → Solvgram**.

## Features

### Privacy
- **Ghost Mode** hides your online status, typing, recording and uploading, choosing stickers, games and emoji interactions, and read receipts, including voice and video messages you listen to. Pick what it hides in the menu, and toggle it with the ghost button in the chat list.
- **Per-chat Ghost Mode**: keep Ghost Mode always on or always off in one chat from the settings button in its header.
- **Read on Action** (on by default): writing in a chat marks it read, even in Ghost Mode. **Read Now** does it on demand.
- **Hidden story views**: you don't appear in story viewer lists. Stories you watched this way get a gray dashed ring. Works without Ghost Mode.
- **Phone numbers**: show your own number as it is, hidden behind a spoiler, or a custom one; hide other people's numbers. Display only, nothing changes on Telegram's side.
- **Location spoofing** with a point picked on a map, and hiding the account name in notifications.

### Saved messages
Everything Solvgram keeps stays on your device. Nothing is sent anywhere.
- **Deleted messages stay in the chat**, see-through in a dashed outline.
- **Edits**: an edited message shows its original text in its lower part, split off by a dashed line.
- **Disappearing photos and videos are kept**, and the sender isn't told you opened them. Mark as Read reports one as viewed.
- **Auto-deleting messages** can be kept too. Save, copy and forward from chats and channels that forbid it.
- **Each switch does two things**: turning saving off stops keeping new items and hides the marks, while what was already saved stays until you clear it.
- **Choose where to save**: separate switches for private chats, groups and channels, for deleted messages and for edits.
- **Per-chat rules**: save or don't save in one chat from the settings button in its header, and manage every rule in one **Exceptions** list.

### Solvgram Cache
- One place for everything Solvgram keeps on this device: deleted messages, edits, disappearing messages, stories and media, each with its size and count.
- **Clearing really removes it**: cleared messages and edits leave your chats and don't come back. Clear one chat, one category or everything, with a confirmation first.

### Chats
- A settings button in every chat's header: Ghost Mode for this chat, saving for this chat, Read Now, the Voice Changer on or off.
- No ads in channels, hide the business bot bar, confirm before calling.
- Chat list: compact layout, one-line previews, swipe actions, folders at the bottom, hide "All Chats".
- Tab bar: hide it, Contacts and Calls tabs, tab names, search button.
- Chat screen: seconds in timestamps, hidden reactions, formatting panel, wide channel posts, pull to the next channel.
- Configurable message menu, sticker size, emoji options. Stories: hide the stories bar, ask before opening.

### Voice and video messages
- **Voice Changer**: several voices, each with its own strength, and a speed setting. Preview before sending.
- Round video camera: front, back, or ask every time. Send a round video as a voice message.

### Media
- Outgoing photo quality, large photos, faster uploads and downloads.

### More
- Translation and speech to text without Telegram Premium.
- A visual Stars balance that only you see.
- Session backup in the iOS Keychain.
- App icons in a carousel at the top of the menu, and the Solvgram badge by the Dynamic Island.
- The Solvgram menu in English or Russian, with search across all of it.

Server-based features are in development and are not part of this release.

## Versions

Solvgram has its own version, separate from the Telegram version it is built on: a major number for large changes and a minor number for everything else. This release is **Solvgram 1.0**, based on **Telegram 13.1.1**. Both are set in `versions.json` and shown at the bottom of the Solvgram menu.

## Building

Solvgram builds like the official app: Bazel, driven by `build-system/Make/Make.py`. Requirements, tests and repository notes are in [CLAUDE.md](CLAUDE.md).

1. Get your own [api_id and api_hash](https://core.telegram.org/api/obtaining_api_id).
2. Put them, your bundle ID and team ID in the build configuration (see `build-system/example-configuration`).
3. Build:

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --codesigningInformationPath build-system/fake-codesigning \
  --buildNumber=1 --configuration=release_arm64
```

The `.ipa` lands in `bazel-bin/Telegram/`. It is ad-hoc signed: re-sign it with your own certificate before installing.

Please follow Telegram's [rules for third-party apps](https://core.telegram.org/api/obtaining_api_id): use your own api_id, don't present your build as the official app, and publish your changes.

## Where Solvgram's code is

Every Solvgram change in the sources is marked `MARK: Solvgram`. The main places:

| What | Where |
|---|---|
| Solvgram menu | `Solvgram/SGSettingsUI/Sources/SolvgramSettingsController.swift` |
| Custom vector icons | `Solvgram/SGSettingsUI/Sources/SolvgramSettingsIcons.swift` |
| Swiftgram settings in the menu | `Solvgram/SGSettingsUI/Sources/SolvgramMenuBridge.swift` |
| Setting keys | `Solvgram/SGSimpleSettings/Sources/SolvgramSettings.swift` |
| Request filter (Ghost Mode, read receipts, ads) | `submodules/TelegramCore/Sources/Network/SolvgramRequestFilter.swift` |
| Deleted, edited and disappearing messages | `submodules/TelegramCore/Sources/Utils/SolvgramMessageArchive.swift` |
| Solvgram Cache: counting and clearing on the device | `submodules/TelegramCore/Sources/Utils/SolvgramDeviceCache.swift`, `Solvgram/SGSettingsUI/Sources/SolvgramCacheController.swift` |
| Saving exceptions | `Solvgram/SGSettingsUI/Sources/SolvgramCaptureExceptionsController.swift` |
| Ghost Mode button | `submodules/ChatListUI/Sources/SolvgramGhostButton.swift` |
| Chat settings button | `submodules/TelegramUI/Sources/Chat/ChatControllerSolvgramShield.swift` |

## Acknowledgements

Solvgram stands on other people's work. Thank you to:

- **[Swiftgram](https://github.com/Swiftgram/Telegram-iOS)** by [Kylmakalle](https://github.com/Kylmakalle) and its contributors. Solvgram is a fork of Swiftgram, and most of its interface settings, the session backup and the translation features are Swiftgram's.
- **Lead**, the Telegram tweak by w3ltyyy ([t.me/leadgramm](https://t.me/leadgramm)). Ghost Mode, keeping deleted, edited and disappearing messages, saving protected content, location spoofing, the visual Stars balance and sending round videos as voice messages started as Lead's features and were reimplemented in Solvgram's source.
- **[TGExtra](https://github.com/Aj3radi/TGExtra)** by Aj3radi, which Lead is a fork of, and chocolate fluffy, who wrote Lead's core.
- **[Telegram](https://github.com/TelegramMessenger/Telegram-iOS)** for the app and its open source code.

## License

GNU GPL v2, like the Telegram iOS source code. Solvgram is unofficial and is not affiliated with Telegram.

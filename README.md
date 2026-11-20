# AppleSign

A macOS app to re-sign iOS apps (`.ipa`), built on top of
[node-applesign](https://github.com/nowsecure/node-applesign). It bundles
applesign as a Node 26 single executable (SEA), so no Node install is needed.
Apple silicon (arm64) only, macOS 26+.

The window is a crafting table:

```
 ┌────────┐ ┌──┐            ┌────────┐       ┌──────┐
 │ 1 .ipa │ │2 │ profile    │4 signed│  ┄┄›  │5  📱 │
 │        │ ├──┤     🔨 ──› │  .ipa  │       │device│
 │        │ │3 │ identity   │        │       │      │
 └────────┘ └──┘            └────────┘       └──────┘
```

1. Drop an `.ipa` (or `.app`) on the left slot.
2. Choose a provisioning profile, or drop a `.mobileprovision`. The last one
   used and recent ones are remembered.
3. Pick a signing identity, or leave it on **Automatic** to derive it from the
   profile. The identity whose certificate is in the profile is selected for you.
   `.p12` files work too. Their password is kept in the Keychain.
4. Press the hammer (⌘↩). The `-resigned.ipa` shows up in the result slot.
   Drag it to Finder, or double-click it to reveal it.
5. With [libimobiledevice](https://libimobiledevice.org) installed
   (`brew install ideviceinstaller`), connected devices appear in the last
   slot. Click it to install the signed app, or drop any `.ipa` on it.

Every applesign command line option is in the **Options** inspector, along
with the exact command line it will run. The **Output** panel streams
applesign's output. Under Settings (⌘,) you can sign as soon as an app is
dropped, which helps when signing many apps in a row.

## Building

Requirements: Xcode 26 or newer, and git.

```sh
make              # builds vendor/applesign from ../node-applesign, then the app
make run          # build and launch
make install      # copy to /Applications (PREFIX=... to change)
make uninstall
make dmg          # build/AppleSign-<version>-arm64.dmg
make applesign    # rebuild the SEA after changing node-applesign
```

`scripts/build-applesign.sh` runs node-applesign's `npm run dist`. SEA needs an
official static Node ≥ 25.5. Homebrew's node is a shared build, so the script
then downloads the official darwin-arm64 Node 26 into `.cache/`.

You can also open `AppleSign.xcodeproj` in Xcode. The *Embed applesign* build
phase copies `vendor/applesign` (or `$APPLESIGN_BIN`) into
`AppleSign.app/Contents/Helpers/`.

## CI and releases

`.github/workflows/build.yml` runs on an Apple silicon runner. It clones
`nowsecure/node-applesign`, builds the SEA with Node 26, builds the app and the
DMG, and uploads the DMG as an artifact.

- Pushing a `v*` tag publishes a GitHub release with the DMG.
- A manual run can choose the node-applesign ref and publish a `continuous`
  prerelease.

The app is ad-hoc signed unless these repository secrets are set:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD` | Developer ID Application certificate |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Notarization with `notarytool` |

An ad-hoc signed download is quarantined by Gatekeeper. Open it with
right-click → Open, or run `xattr -dr com.apple.quarantine /Applications/AppleSign.app`.

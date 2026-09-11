English | [简体中文](README.zh-CN.md)

<div align="center">
  <img src="Resources/Icons/KidoX-400.png" width="160" height="160" alt="KidoX app icon">
  <h1>KidoX</h1>
  <p>A modern Launchpad replacement for Mac, with gestures, search, pages, and app uninstall.</p>
  <p>
    <a href="https://github.com/xjpz/kidox">Repository</a>
    ·
    <a href="https://github.com/defcc/kidox.app">Upstream</a>
  </p>
  <img src="media/kidox-launcher.png" width="100%" alt="KidoX launcher screenshot">
</div>

## About KidoX App

This repository is a fork of [defcc/kidox.app](https://github.com/defcc/kidox.app), maintained at [xjpz/kidox](https://github.com/xjpz/kidox). It adds Chinese pinyin search, configurable Frequent Apps, pinned apps, and a compact launcher. The app bundle identifier is `cc.xjpz.KidoX`.

KidoX is built for people who still want a fast, visual, keyboard-friendly way to browse, organize, and launch Mac apps.

It restores the Launchpad-style grid while improving the parts that matter day to day: quick search, clean organization, smooth navigation, customizable behavior, and a native macOS feel built with SwiftUI.

KidoX is not a system hack or a patched copy of Launchpad. It is an independent macOS app designed to provide a modern launcher experience that feels at home on current versions of macOS.

## Features

Core features:

- Launchpad-style app grid with pages, folders, drag-and-drop arrangement, and keyboard navigation
- Fast in-place search with Chinese names, full pinyin, and pinyin initials
- An optional frequent-apps page to the left of the first page in Default sorting, with compact 6 × 4 (up to 24 apps) or 7 × 5 (up to 35 apps) layouts that keep the original app arrangement intact
- Pinned apps at the front of Frequent Apps, with shared pin order in full-screen and compact modes
- Optional compact launcher with direct star/grid navigation, search, folders, and a vertically scrolling app grid
- Two-finger horizontal switching with directional slide transitions and Reduce Motion support
- Native Liquid Glass in compact mode on macOS 26, with a visual-effect fallback on earlier systems
- F4 / Launchpad key support, custom shortcuts, hot corners, menu-bar access, and Dock access
- Optional global four-finger trackpad gesture: pinch to show KidoX, spread to hide it
- Automatic scanning of standard Applications folders
- Wallpaper, glass, and solid-color appearance modes
- Localized app language support

Pro features:

- Advanced sorting modes, including recently used, most used, newly added, and name
- Hidden Apps for keeping rarely used apps out of the launch panel
- Built-in app uninstaller with related app data cleanup and protected-system-app checks
- Custom image backgrounds
- Backup and restore for layout, hidden apps, launch stats, sorting, shortcut, appearance, Dock icon, custom image, and frequent-apps preferences

The four-finger gesture is optional and disabled by default. It uses a runtime-loaded private macOS multitouch framework, so official KidoX builds are distributed outside the Mac App Store.

## Overview

This repository contains the KidoX Community Edition macOS app source code. It is published for transparency, security review, education, and community contributions under the GNU Affero General Public License v3.0.

The license-management backend, production release configuration, signing credentials, notarization credentials, and distribution infrastructure are not included in this repository.

## Community Edition

You may read the source code, study how the app works, audit it, modify it, build it, and redistribute it under the terms of the AGPL-3.0 license.

Upstream official KidoX builds are distributed through channels controlled by the upstream maintainers. The [upstream website](https://kidox.app) and [download page](https://kidox.app/download/) refer to that project, rather than builds from this fork. Third-party builds and forks must comply with the AGPL-3.0 license and may not use the KidoX name, logo, icon, or brand assets in a way that suggests an official release or endorsement.

## What's Included

- `KidoX/` - main macOS app source
- `KidoXApp.xcodeproj/` - Xcode project and shared scheme
- `KidoXIPC/` - shared IPC support code
- `KidoXDockTile/` - Dock tile plug-in
- `KidoXPrivilegedHelper/` - privileged helper for uninstall operations
- `KidoXTests/` - search, recommendation, pinning, and navigation tests
- `docs/` - feature designs and implementation notes
- `Resources/` - app icons and bundled visual assets
- `Packaging/DMG/` - local DMG packaging helper scripts

## Requirements

- macOS 15 or later to run the app
- Xcode 26 or later with the macOS 26 SDK to build the current source
- Xcode command line tools

## Local Development

Open `KidoXApp.xcodeproj` in Xcode and run the `KidoX` scheme. Configure your own signing team and keep the app and privileged helper signing requirements consistent.

You can also build from the command line:

```sh
xcodebuild -project KidoXApp.xcodeproj -scheme KidoX -configuration Debug build
```

The project uses Swift Package Manager dependencies resolved by Xcode.

## Usage

### Frequent Apps

Enable or disable the page in **Settings → General → Frequent Apps** (设置 → 通用 → 负一屏). It appears only with Default sorting when no search is active.

- **6 × 4** is the default, showing up to **24 apps**; **7 × 5** shows up to **35 apps**.
- Both layouts use compact spacing, keep partial rows left-aligned, and omit page headings and subtitles. Arrow-key navigation follows the selected column count.
- Layout changes take effect immediately and are saved automatically. Disabling the page keeps the selected layout; settings backups also include the switch, layout, pins, and excluded apps. Older configurations default to 6 × 4.
- Recommendations use existing local KidoX launch counts, including apps inside folders. Launches from Dock or Finder are not tracked. Hidden, unavailable, and excluded apps do not appear.
- Right-click an app to **pin or unpin** it. Pins appear first, share the 24/35-app capacity with recommendations, and can be reordered by dragging on the frequent-apps page. Pinning does not move the original app or require a previous launch. Reducing the layout retains excess pins. The pinned-apps list in Settings provides unpinning; reorder pins directly on the frequent-apps grid.
- Right-click an unpinned frequent app to stop recommending it, or restore excluded apps in Settings. Recommendation order stays stable until the next opening; changing the layout refreshes the list for the selected capacity.

Reopening the launcher remembers the last browsed page, including Frequent Apps, for the current app run. Reopening from search returns to the page before search; a full app restart starts on the original first page. See [Frequent Apps details](docs/recommendations.md) for behavior and persistence rules.

### Compact Launcher

Select **Settings → General → Launch mode → Compact launcher** (设置 → 通用 → 启动方式 → 小屏模式). Full screen remains the default; the full-screen settings menu also offers **Compact launcher**, and the compact toolbar can return to full screen.

- A 920 × 640 pt panel that fits the current display, with a draggable toolbar.
- Small star and four-square buttons switch directly between Frequent and All apps, with no dropdown and no pin badges. The search field is capped at 360 pt; the trailing gear opens the settings menu.
- A horizontal two-finger swipe switches Frequent/All. Sliding right returns from All to Frequent; sliding left opens All from Frequent, following the system scroll direction. The ends do not wrap.
- Swipes and star/grid clicks use a 0.28-second directional slide and fade, while the toolbar stays fixed. Reduce Motion uses a short fade instead. Switching commits when the gesture ends; the page does not track the fingers continuously.
- Vertical scrolling stays within the list. Small or ambiguous diagonal movements and momentum do not trigger repeated page changes. Search, open folders, and pin dragging keep their current interaction.
- On macOS 26, the panel uses native Liquid Glass; earlier systems retain an adaptive visual-effect material.
- All apps scroll vertically in the existing page/folder order; Frequent uses the selected 6 × 4 or 7 × 5 layout.
- Search spans all visible apps, including folder contents. Escape clears search, leaves a folder, then dismisses the panel.
- Successful launches dismiss the panel. Each mode remembers its own browsing position during the current app run.
- Pins and launch mode are included in settings backups. No screen-recording permission is added.

Ordinary app rearrangement remains available in full screen. See the [design and behavior](docs/pinned-apps-compact-launcher-design.md) and [implementation verification](docs/pinned-apps-compact-launcher-implementation.md).

### Search

Search supports Chinese text, English names, full pinyin, and pinyin initials: `x` or `xtsz` finds 系统设置, and `wx` or `weixin` finds 微信. With Default sorting, exact initials rank ahead of longer prefix matches. Language-tagged aliases keep unrelated foreign names out of single-letter searches. Search indexes are built in the background and updated when names change.

### Bundle Identifier and Existing Backups

The main app uses `cc.xjpz.KidoX`; IPC, Dock, and helper identifiers use the same prefix. Changing from an older identifier creates a new preferences domain, so import your saved backup in Settings to restore your preferences. macOS may ask you to authorize existing system permissions again.

The layout database remains at `~/Library/Application Support/KidoX/pages.json`. The backup format and `.kidoxbackup` extension remain compatible, including the existing backup file type identifier. Changing the app identifier does not delete the old preferences or layout data. See [the identifier change notes](docs/bundle-identifier-change.md).

## Tests

Run the focused search, recommendation, pinning, page mapping, gesture, and compatibility tests with:

```sh
xcodebuild -project KidoXApp.xcodeproj -scheme KidoXRecommendations -destination 'platform=macOS' test
```

This test scheme runs without launching KidoX or loading its user database. The tests are also registered in the main `KidoX` scheme.

Local builds are intended for evaluation, review, and development. If you distribute modified builds, you are responsible for complying with AGPL-3.0 and for removing or replacing reserved KidoX brand assets where required.

## Packaging

The DMG helper lives at `Packaging/DMG/build-dmg.sh`.

Release packaging requires local signing, notarization, and production configuration that are intentionally not committed to this repository. Local files such as `Packaging/DMG/release.env` are ignored and should not be committed.

## Maintainers

- Fork: [xjpz](https://github.com/xjpz)
- Upstream: [defcc](https://github.com/defcc)

## Contributing

Issues and pull requests are welcome when they improve the app, documentation, reliability, or security.

By submitting a contribution, you agree to license your contribution under AGPL-3.0 and confirm that you have the right to do so. For substantial contributions that may be included in dual-licensed or commercial-license-exempt releases, the maintainers may ask you to sign a contributor license agreement before merging.

## Disclaimer

This repository is the source distribution for KidoX Community Edition. It is not an official distribution channel for signed, notarized KidoX binaries.

## License

KidoX Community Edition is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0), available at <https://www.gnu.org/licenses/agpl-3.0.html>.

Use of KidoX Community Edition for commercial purposes is permitted, subject to full compliance with the terms and conditions of the AGPL-3.0 license.

If you require a commercial license that provides an exemption from the AGPL-3.0 requirements, contact the upstream maintainers at <support@kidox.app>.

The KidoX name, logo, icon, website assets, signing keys, release infrastructure, and other brand assets are not licensed under AGPL-3.0 unless explicitly stated otherwise.

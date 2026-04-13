# Tempo for Claude

A macOS menu bar app that tracks your Claude Code token and credit usage in real time, with an Apple Watch companion for haptic alerts when a session ends.

[![CI - Build](https://github.com/tenondecrpc/tempo-for-claude/actions/workflows/build.yml/badge.svg)](https://github.com/tenondecrpc/tempo-for-claude/actions/workflows/build.yml)
[![Security - CodeQL (Swift)](https://github.com/tenondecrpc/tempo-for-claude/actions/workflows/codeql.yml/badge.svg)](https://github.com/tenondecrpc/tempo-for-claude/actions/workflows/codeql.yml)
[![Security - Dependency Review](https://github.com/tenondecrpc/tempo-for-claude/actions/workflows/dependency-review.yml/badge.svg)](https://github.com/tenondecrpc/tempo-for-claude/actions/workflows/dependency-review.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Join the beta

Want early access to new Tempo builds? You can join the public beta on TestFlight here:

**[Join the Tempo beta on TestFlight](https://testflight.apple.com/join/1VJBBtVS)**

Install the app, try it on your devices, and send feedback while features are still evolving.

## Why this repo is trustworthy

- **CI on pull requests**: the macOS and iOS targets are built automatically in GitHub Actions for every PR.
- **Security checks**: Swift code is scanned with CodeQL, and dependency updates go through automated dependency review.
- **Maintainer review gates**: [`CODEOWNERS`](.github/CODEOWNERS) requires maintainer review for sensitive areas like workflows, project settings, entitlements, and app targets.
- **Structured contribution flow**: bug reports, feature requests, and PRs use templates with testing and risk checklists to keep changes reviewable.
- **Transparent data handling**: Tempo uses no custom backend; usage data stays on your Apple devices through iCloud sync.
- **Open license**: the project is released under the [`MIT License`](LICENSE), so the terms are explicit and easy to audit.

## Screenshots

### macOS menu bar

<p align="center">
  <a href="screenshots/mac-01.png">
    <img src="screenshots/mac-01.png" alt="Tempo menu bar popover" width="280" />
  </a>
</p>

### macOS desktop windows

<p align="center">
  <a href="screenshots/mac-02.png">
    <img src="screenshots/mac-02.png" alt="Tempo overview window" width="31%" />
  </a>
  <a href="screenshots/mac-03.png">
    <img src="screenshots/mac-03.png" alt="Tempo activity window" width="31%" />
  </a>
  <a href="screenshots/mac-04.png">
    <img src="screenshots/mac-04.png" alt="Tempo preferences window" width="31%" />
  </a>
</p>

### iPhone companion app

<p align="center">
  <a href="screenshots/ios-01.jpeg">
    <img src="screenshots/ios-01.jpeg" alt="Tempo iPhone dashboard" width="30%" />
  </a>
  <a href="screenshots/ios-02.jpeg">
    <img src="screenshots/ios-02.jpeg" alt="Tempo iPhone activity view" width="30%" />
  </a>
  <a href="screenshots/ios-03.jpeg">
    <img src="screenshots/ios-03.jpeg" alt="Tempo iPhone settings view" width="30%" />
  </a>
</p>

### Apple Watch

<p align="center">
  <a href="screenshots/watch_01.jpeg">
    <img src="screenshots/watch_01.jpeg" alt="Tempo Apple Watch dashboard" width="30%" />
  </a>
  <a href="screenshots/watch_02.jpeg">
    <img src="screenshots/watch_02.jpeg" alt="Tempo Apple Watch session detail" width="30%" />
  </a>
  <a href="screenshots/watch_03.jpeg">
    <img src="screenshots/watch_03.jpeg" alt="Tempo Apple Watch completion view" width="30%" />
  </a>
</p>

## What it does

- Shows your **5-hour and 7-day utilization** as a ring gauge in the macOS menu bar
- Displays **burn rate**, extra usage, and next reset time at a glance
- Includes an iOS companion UI (**Dashboard**, **Activity**, **Settings**) styled with Claude tokens
- Delivers a **haptic alert on your Apple Watch** the moment a Claude Code session ends
- Relays live usage data from macOS → iCloud (`usage.json`, `usage-history.json`) → iOS → Apple Watch

## Architecture

```
macOS menu bar app (OAuth + poll every 15 min)
  └─ iCloud Drive (usage.json / usage-history.json)
      └─ iOS companion (NSMetadataQuery + dashboard/activity/settings)
          └─ WatchConnectivity (transferUserInfo)
              └─ watchOS haptic + usage ring
```

Two independent data pipelines run in parallel:

| Pipeline | Trigger | Data |
|---|---|---|
| **OAuth API** | 15-min poll | Utilization %, reset timestamps |
| **Stop hook** | Session end event | Per-session tokens, cost, duration |

The OAuth API is the authoritative source for utilization - the plan limit is account-specific and never exposed locally. The Stop hook is the only way to deliver an instant haptic the moment a session closes.

## Privacy and data handling

- Tempo does **not** run any custom backend and does **not** store your usage data on third-party servers.
- Data is synchronized only between your Apple devices through your iCloud container.
- iCloud sync and transport rely on Apple's security model and encryption standards.

## Targets

| Folder | Target | Role |
|---|---|---|
| `Tempo macOS/` | macOS menu bar app | OAuth sign-in, usage polling, iCloud writer |
| `Tempo/` | iOS app | iCloud reader, WatchConnectivity sender |
| `Tempo Watch/` | watchOS app shell | Entry point |
| `Tempo Watch Extension/` | watchOS extension | All watch UI and haptic logic |
| `Shared/` | Shared code | Data models, business logic (no UI frameworks) |

## Getting started

1. Open `Tempo.xcodeproj` in Xcode
2. Enable **Outgoing Connections (Client)** in App Sandbox for the macOS target (required for calls to `platform.claude.com`)
3. Enable **iCloud Documents** on both the macOS and iOS targets using the same container ID (requires an Apple Developer account)
4. Build and run the macOS target
5. Sign in with your Claude account via OAuth - the app opens a browser and lets you paste the authorization code

## Requirements

- macOS 13+ (menu bar app)
- iOS 16+ (companion app)
- watchOS 9+ (haptic alerts and usage ring)
- Apple Developer account (for iCloud Documents entitlement)

## Roadmap

See [`docs/PLAN.md`](docs/PLAN.md) for the implementation roadmap and unscheduled backlog.

Current roadmap highlights:

- **Phase 6** - Reset alarm: strong haptic + notification at the exact moment your 5h limit resets
- **Phase 8** - Stats dashboard: session history and watch face complications
- **Phase 9** - Context window tracking: usage gauge per active session with threshold alerts

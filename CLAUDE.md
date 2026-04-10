# CLAUDE.md

## Language

All agent communication and written outputs in this repository must be in English.

## Project

Apple Watch app that tracks Claude Code token/credit usage and delivers haptic alerts when a session ends.

**Pipeline**: macOS app (OAuth + poll) → iCloud JSON → iOS companion → WatchConnectivity (`transferUserInfo`) → watchOS haptic + UI

See `docs/FUTURE_PLAN.md` for the full roadmap.

## Build

Open `Tempo.xcodeproj` in Xcode. No CLI build system.

> **macOS target**: requires "Outgoing Connections (Client)" enabled in App Sandbox (Signing & Capabilities) so HTTP calls to `platform.claude.com` work.

## Targets

| Folder | Target | Role |
|---|---|---|
| `Tempo macOS/` | macOS menu bar app | OAuth sign-in, usage polling, iCloud writer |
| `Tempo/` | iOS app | iCloud reader (`NSMetadataQuery`), WatchConnectivity sender |
| `Tempo Watch/` | watchOS app shell | Entry point only |
| `Tempo Watch Extension/` | watchOS extension | All watch UI and logic |

## Shared Logic

Code shared between targets lives in `Shared/`. The project uses `PBXFileSystemSynchronizedRootGroup` — files added to `Shared/` are automatically included in all linked targets, no manual Target Membership needed.

**Belongs in `Shared/`:** data models, pure business logic (no `UIKit`/`WatchKit`/`SwiftUI`), shared enums/constants.

**Does NOT belong in `Shared/`:** views, `WCSession` logic, iCloud/`NSMetadataQuery` code, haptic code.

## References

- Code style, patterns, and architecture: `docs/CONVENTIONS.md`

## Workflow

- **Design**: use `/opsx:propose` to draft changes before implementing
- **SwiftUI**: invoke `/swiftui-expert-skill` when writing or reviewing any Swift/SwiftUI code

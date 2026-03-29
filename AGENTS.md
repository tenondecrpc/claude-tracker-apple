# AGENTS.md

Guidelines for agentic coding agents operating in this repository.

## Project

Apple Watch app that tracks Claude Code token/credit usage and delivers haptic alerts when a session ends.

**Pipeline**: macOS app (OAuth + poll) → iCloud JSON → iOS companion → WatchConnectivity (`transferUserInfo`) → watchOS haptic + UI

## Build

Open `ClaudeTracker.xcodeproj` in Xcode. No CLI build system. No formal test suite.

## Targets

| Folder | Target | Role |
|---|---|---|
| `ClaudeTracker macOS/` | macOS menu bar app | OAuth sign-in, usage polling, iCloud writer |
| `ClaudeTracker/` | iOS app | iCloud reader, WatchConnectivity sender |
| `ClaudeTracker Watch/` | watchOS app shell | Entry point only |
| `ClaudeTracker Watch Extension/` | watchOS extension | All watch UI and logic |

## Shared Logic

Code shared between targets lives in `Shared/` (auto-synced via `PBXFileSystemSynchronizedRootGroup`).

**Belongs in `Shared/`:** data models, pure business logic, shared enums/constants.

**Does NOT belong in `Shared/`:** views, `WCSession` logic, iCloud code, haptic code.

## References

- Code style, patterns, and architecture: `docs/CONVENTIONS.md`
- Full roadmap: `docs/FUTURE_PLAN.md`

## Workflow

- **Design**: use `/opsx:propose` to draft changes before implementing
- **SwiftUI**: invoke `/swiftui-expert-skill` when writing or reviewing any Swift/SwiftUI code
- **Implementation**: use `/opsx:apply` to implement tasks from OpenSpec change documents

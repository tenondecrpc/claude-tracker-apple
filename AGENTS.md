# AGENTS.md

Guidelines for agentic coding agents operating in this repository.

## Language

All agent communication and written outputs in this repository must be in English.

## Project

Apple Watch app that tracks Claude Code token/credit usage and delivers haptic alerts when a session ends.

**Pipeline**: macOS app (OAuth + poll) → iCloud JSON → iOS companion → WatchConnectivity (`transferUserInfo`) → watchOS haptic + UI

## Build

Open `Tempo.xcodeproj` in Xcode. No CLI build system. No formal test suite.

## Targets

| Folder | Target | Role |
|---|---|---|
| `Tempo macOS/` | macOS menu bar app | OAuth sign-in, usage polling, iCloud writer |
| `Tempo/` | iOS app | iCloud reader, WatchConnectivity sender |
| `Tempo Watch/` | watchOS app shell | Entry point only |
| `Tempo Watch Extension/` | watchOS extension | All watch UI and logic |

## Shared Logic

Code shared between targets lives in `Shared/` (auto-synced via `PBXFileSystemSynchronizedRootGroup`).

**Belongs in `Shared/`:** data models, pure business logic, shared enums/constants.

**Does NOT belong in `Shared/`:** views, `WCSession` logic, iCloud code, haptic code.

## References

- Code style, patterns, and architecture: `docs/CONVENTIONS.md`
- Full roadmap: `docs/FUTURE_PLAN.md`

## Workflow

- **OpenSpec in Codex (stable alternative)**:
  - In Codex, use `/skills` and select: `openspec-propose`, `openspec-apply-change`, `openspec-explore`, `openspec-archive-change`
  - You can also invoke skills directly by name: `$openspec-propose`, `$openspec-apply-change`, `$openspec-explore`, `$openspec-archive-change`
- **OpenSpec in OpenCode**:
  - Use legacy commands: `/opsx:propose`, `/opsx:apply`, `/opsx:explore`, `/opsx:archive`
- **Design**: use `openspec-propose` (`/skills` or `$openspec-propose`) to draft before implementation
- **SwiftUI**: invoke `/swiftui-expert-skill` when writing or reviewing any Swift/SwiftUI code
- **Implementation**: use `openspec-apply-change` (`/skills` or `$openspec-apply-change`) to implement OpenSpec tasks

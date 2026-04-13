# AGENTS.md

Guidelines for agentic coding agents operating in this repository.

## Instruction Source

`AGENTS.md` is the single source of truth for repository instructions.

When Claude Code is used in this repository, `CLAUDE.md` must remain a thin bootstrap file that imports `AGENTS.md` and does not duplicate repository rules.

## Language

All agent communication and written outputs in this repository must be in English.

## Formatting

These formatting rules apply to all agent-written output in this repository, including Codex, OpenCode, and Claude Code.

Use ASCII punctuation by default.

Do not use em dashes (`—`) or en dashes (`–`) in prose, bullet lists, headings, commit messages, plans, or code comments.

Always use the plain ASCII hyphen (`-`) instead.

Preferred example:

- `Describe Chart - overview of axes and data series`

## Project

Apple Watch app that tracks Claude Code token/credit usage and delivers haptic alerts when a session ends.

**Pipelines**:
- Usage pipeline: macOS app (OAuth + poll) → iCloud JSON (`usage.json`, `usage-history.json`, `alert-preferences.json`) → iOS companion → WatchConnectivity → watchOS UI and alerts
- Session pipeline: macOS app reads Claude Code local data from `~/.claude/` → writes `latest.json` to iCloud → iOS companion relays to watchOS for completion alerts

The hook/session data and the OAuth usage data solve different problems. Do not collapse them into a single source.

## Build

Open `Tempo.xcodeproj` in Xcode for normal development.

CI builds with `xcodebuild` for the `Tempo macOS` and `Tempo` schemes. There is no comprehensive automated test suite, but there is a repo smoke test at `tools/widget_smoke_test.swift` for widget snapshot and route validation.

## Targets

| Folder | Target | Role |
|---|---|---|
| `Tempo macOS/` | macOS menu bar app | OAuth sign-in, usage polling, iCloud writer |
| `Tempo/` | iOS app | iCloud reader, dashboard/activity UI, WatchConnectivity sender |
| `Tempo Watch/` | watchOS app | Watch UI, WatchConnectivity receiver, haptic/session alerts |
| `Tempo macOS Widget/` | macOS widget extension | Desktop widgets backed by shared widget snapshots |
| `Tempo iOS Widget/` | iOS widget extension | iPhone widgets backed by shared widget snapshots |
| `Tempo Watch Widget/` | watchOS widget extension | Watch widget surfaces |

## Shared Logic

Code shared between targets lives in `Shared/` (auto-synced via `PBXFileSystemSynchronizedRootGroup`).

**Belongs in `Shared/`:** data models, pure business logic, shared enums/constants, shared formatting/presentation helpers, widget snapshot storage, and cross-target route definitions.

**Does NOT belong in `Shared/`:** app screens, `WCSession` session ownership, `NSMetadataQuery` lifecycle code, AppKit/UIKit/watchOS alert delivery, or target-specific entitlement/bookmark access code.

When identifiers such as iCloud container IDs, app group IDs, widget kinds, or deep-link routes are needed in multiple targets, define or update them in shared constants instead of duplicating string literals.

## Architecture Notes

- `Tempo macOS/TempoMacApp.swift` owns the macOS coordinator. It starts OAuth restore, polling, widget snapshot seeding, service monitoring, and local Claude session ingestion.
- `Tempo/TempoApp.swift` owns the iOS coordinator. It starts `iCloudUsageReader`, writes iOS widget snapshots, and relays usage/session data to the watch.
- `Tempo Watch/Tempo_WatchApp.swift` owns the watch coordinator. The watch receives data from iPhone relay code and is responsible for watch-side alert state and presentation.
- `Shared/WidgetUsageSnapshot.swift` is the contract for widget snapshot persistence. Changes here must keep the iOS and macOS widget targets aligned.
- `Tempo macOS/ClaudeLocalDBReader.swift` and `Tempo macOS/SessionEventWriter.swift` read from `~/.claude/` and rely on security-scoped access when sandboxed. Changes here must preserve the access-grant flow.
- `Shared/AlertPreferencesSync.swift` and `Shared/TempoICloud.swift` define cross-device sync locations. Treat path, container, and file-name changes as high-risk.

## Guardrails

- Do not store OAuth credentials in `UserDefaults`, widgets, or iCloud. The macOS app uses dedicated local credential storage.
- Do not move watch relay or haptic logic into `Shared/`.
- Do not break the distinction between `updateApplicationContext` for latest usage state and `transferUserInfo` for durable background delivery.
- Do not duplicate app group IDs, iCloud paths, widget kind names, or route URLs across targets if a shared constant already exists.
- Treat changes to entitlements, Info.plist values, bundle identifiers, app groups, iCloud containers, and `.xcodeproj` settings as high-risk changes that must be called out explicitly.

## References

- Code style, patterns, and architecture: `docs/CONVENTIONS.md`
- Full roadmap and backlog: `docs/PLAN.md`

## Workflow

- **OpenSpec in Codex (stable alternative)**:
  - In Codex, use `/skills` and select: `openspec-propose`, `openspec-apply-change`, `openspec-explore`, `openspec-archive-change`
  - You can also invoke skills directly by name: `$openspec-propose`, `$openspec-apply-change`, `$openspec-explore`, `$openspec-archive-change`
- **OpenSpec in OpenCode**:
  - Use legacy commands: `/opsx:propose`, `/opsx:apply`, `/opsx:explore`, `/opsx:archive`
- **Design**: use `openspec-propose` (`/skills` or `$openspec-propose`) to draft before implementation
- **SwiftUI**: invoke `/swiftui-expert-skill` when writing or reviewing any Swift/SwiftUI code
- **Implementation**: use `openspec-apply-change` (`/skills` or `$openspec-apply-change`) to implement OpenSpec tasks

## Verification

- For macOS or iOS code changes, prefer building the affected Xcode scheme locally.
- For widget or deep-link changes, run or update `tools/widget_smoke_test.swift` when relevant.
- For watch, iCloud, entitlement, or notification changes, include manual verification notes because simulator behavior is incomplete for some flows.
- UI changes should include screenshots or a short note describing what was manually verified.

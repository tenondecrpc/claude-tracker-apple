# Contributing to Tempo for Claude

Thanks for contributing. This project spans macOS, iOS, and watchOS, so changes should stay narrow, well-documented, and easy to review.

## Before You Start

- Read [README.md](README.md) for the product overview and setup requirements.
- Read [docs/CONVENTIONS.md](docs/CONVENTIONS.md) for code style and architectural patterns.
- Check [docs/PLAN.md](docs/PLAN.md) before proposing large features to avoid duplicating planned work.
- Keep all communication and written project artifacts in English.

## Development Setup

1. Open `Tempo.xcodeproj` in Xcode.
2. Use the appropriate Apple platform target for the area you are changing:
   - `Tempo macOS/` for OAuth, polling, and iCloud writing
   - `Tempo/` for iOS companion logic and WatchConnectivity sending
   - `Tempo Watch Extension/` for watch UI and haptic behavior
   - `Shared/` for pure shared models and business logic only
3. Configure the Apple capabilities required by the README when testing locally:
   - App Sandbox outgoing connections for the macOS target
   - iCloud Documents for the macOS and iOS targets with the same container ID

## Contribution Workflow

1. Create a focused branch from `main`.
2. Keep each pull request limited to one feature, fix, or documentation change.
3. Update documentation when behavior, setup, screenshots, or user-facing flows change.
4. Include screenshots or screen recordings for UI changes on macOS, iOS, or watchOS when relevant.
5. Open a pull request with a clear summary, testing notes, and any platform limitations.

## Code Guidelines

- Follow the file ownership described in `AGENTS.md`.
- Put shared models and pure logic in `Shared/`, but keep platform-specific UI and integrations out of it.
- Prefer small, readable SwiftUI views and explicit type annotations where the compiler needs help.
- Do not introduce unrelated refactors in the same change unless they are required to make the fix safe.
- Do not commit secrets, OAuth tokens, personal iCloud identifiers, or local signing artifacts.

## Testing Expectations

This repository does not currently have a formal automated test suite. Every contribution should still include reasonable verification.

Before opening a pull request, document what you validated:

- Which target(s) you built in Xcode
- Which platform(s) you ran manually
- What behavior changed
- What you could not verify locally

If your change affects UI or device-to-device flows, say whether you verified:

- macOS menu bar behavior
- iOS sync and display
- watchOS relay or haptic behavior

## Reporting Bugs

Use the bug report template and include:

- The affected platform and app target
- Clear reproduction steps
- Expected behavior and actual behavior
- Screenshots, logs, or crash details if available

## Suggesting Features

Use the feature request template for product ideas. Explain the user problem first, then the proposed solution.

For larger changes, align the proposal with the roadmap and existing architecture before implementation starts.

## Pull Request Review Criteria

Pull requests are reviewed for:

- Correctness
- Scope control
- Fit with the existing architecture
- Clarity of documentation and testing notes
- User impact across macOS, iOS, and watchOS

Contributions that do not meet these standards may be asked to revise before merge.

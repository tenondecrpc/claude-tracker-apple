# Task 9.7 - Build Verification

Integration build verification for the `multi-account-support` change.
Run against the multi-account branch after tasks 1 through 9.6 were
already marked complete.

## Commands

### Tempo macOS scheme

```
xcodebuild -project Tempo.xcodeproj \
  -scheme "Tempo macOS" \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
```

Result: `** BUILD SUCCEEDED **` on the first attempt. No code changes
were required for the macOS scheme.

### Tempo scheme (iOS, which transitively builds Tempo Watch + iOS widget)

```
xcodebuild -project Tempo.xcodeproj \
  -scheme "Tempo" \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
```

Result: `** BUILD SUCCEEDED **` after the single code fix described
below (first attempt failed only in the `Tempo Watch` target).

### Repo widget smoke test

The smoke test declares `@main` and references Shared types, so it must
be compiled with `swiftc` against the `Shared/` sources (same pattern
already used by the other standalone tests in `tools/`). It also asserts
the built macOS bundle at `/tmp/tempo-macos-final/Debug/TempoForClaude.app`,
so the macOS scheme must first be built with `BUILD_DIR=/tmp/tempo-macos-final`:

```
xcodebuild -project Tempo.xcodeproj \
  -scheme "Tempo macOS" \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  BUILD_DIR=/tmp/tempo-macos-final \
  build

swiftc -parse-as-library \
  -o /tmp/widget_smoke_test \
  tools/widget_smoke_test.swift Shared/*.swift

/tmp/widget_smoke_test
```

Result: `Widget smoke test passed` (exit code 0). All six assertions
(`assertRoutes`, `assertAccountRouteParsing`, `assertSnapshotRoundTrip`,
`assertMultiAccountSnapshots`, `assertAccountIntentPlaceholder`,
`assertBuiltMacWidgetBundle`) pass.

## Code changes made during this task

Only one change was needed to reach green:

- `Tempo Watch/ContentView.swift`: removed `.textSelection(.enabled)`
  from the account detail sheet's `Text(fullAccountLabel())` view.
  `textSelection(_:)` is unavailable on watchOS (the iOS `Tempo` scheme
  build failed in the `Tempo Watch` target with
  `'textSelection' is unavailable in watchOS` and
  `'enabled' is unavailable in watchOS`). The sheet still displays the
  full account label and retains the accessibility label; only the
  (unsupported) copy-select affordance was removed.

No other targets required edits. No entitlements, Info.plist, bundle
identifiers, app groups, iCloud containers, or OAuth credential paths
were touched.

## Summary

- macOS build: succeeded.
- iOS build (including Tempo Watch + iOS widget extension + iOS
  widget extension as embedded extensions): succeeded after the
  `textSelection` fix above.
- macOS widget extension: builds clean as part of `Tempo macOS` (it is
  listed as an explicit dependency in the target dependency graph).
- Widget smoke test: passes.

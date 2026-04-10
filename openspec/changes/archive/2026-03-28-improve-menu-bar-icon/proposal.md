## Why

The current menu bar icon is static and doesn't provide at-a-glance information about Claude Code token/credit usage. Adding an indicator graph based on the percentage of use will provide immediate visual feedback to the user without needing to click the menu bar item.

## What Changes

- Replace the static app icon in the macOS menu bar with a dynamic indicator graph.
- The indicator graph will visually represent the current percentage of token/credit usage out of the total limit.
- The icon will need to update whenever the usage data is polled and changes.

## Capabilities

### New Capabilities

- None

### Modified Capabilities

- `macos-menu-bar-ui`: Modify the menu bar item to render a dynamic indicator graph instead of a static image, driven by the current token usage percentage.

## Impact

- macOS menu bar app (`Tempo macOS/`)
- Specifically, the `NSStatusItem` handling, drawing code for the menu bar icon, and the observation of usage data to trigger icon updates.

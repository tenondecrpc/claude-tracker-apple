## Why

Tempo already exposes usage data in the macOS menu bar app, the iPhone companion, and the Apple Watch complication, but there is no glanceable widget surface on iPhone or Mac desktop. Adding widgets now extends the existing "check usage at a glance" value proposition to the platforms where users spend most of their time, using the same session, weekly, reset, and extra-usage signals already present in the product.

## What Changes

- Add WidgetKit-based usage widgets for both iOS and macOS, with layouts inspired by the provided references: a ring-focused compact widget, a horizontal summary widget, and a compact stacked-metrics variant.
- Reuse existing Tempo metrics in widgets: current session utilization, weekly utilization, reset timing, and extra-usage summary when available.
- Introduce a widget-specific snapshot/cache flow so widgets render from app-managed shared data instead of performing their own iCloud or API reads.
- Support stale, empty, and mock-data states so widgets stay informative when no fresh payload is available.
- Deep-link widget taps into the existing Tempo dashboard experience on iOS and the relevant window on macOS.
- Keep the ClaudeCode visual language consistent across widget families while adapting density per platform and size class.

## Capabilities

### New Capabilities
- `usage-widgets`: Cross-platform WidgetKit widgets for iOS and macOS that expose Tempo usage in compact and expanded formats using shared widget snapshot data.

### Modified Capabilities
- `icloud-usage-sync`: Extend the iOS iCloud reader flow so the app also materializes the latest widget snapshot into shared widget storage and triggers widget timeline reloads when iCloud usage data changes.
- `macos-usage-writer`: Extend the macOS polling/writer flow so successful usage polls also update a shared widget snapshot and reload macOS widget timelines.

## Impact

- Affected targets: `Tempo/`, `Tempo macOS/`, `Shared/`, plus new iOS and macOS widget extension targets.
- Likely touched systems: `iCloudUsageReader`, macOS usage polling/writing flow, shared snapshot/formatting models, app entitlements/App Group configuration, widget deep links, and Xcode target configuration.
- Dependencies/systems: WidgetKit timeline reload behavior, shared container/App Group storage, existing iCloud usage/history/session files, and ClaudeCode theme tokens.
- Risk areas: stale widget content, keeping iOS and macOS widget variants visually consistent without putting views in `Shared/`, and keeping widget refresh behavior reliable within WidgetKit budget limits.

## Context

Currently, the macOS menu bar app for Claude Tracker uses a static app icon. The usage data is polled and available within the app, but the user must click the menu bar item to see their current token/credit usage. We want to improve this by drawing a dynamic indicator graph directly into the menu bar icon based on the percentage of usage.

## Goals / Non-Goals

**Goals:**
- Provide immediate visual feedback of token/credit usage in the menu bar.
- Draw a dynamic indicator (e.g., a ring or pie chart) as the `NSStatusItem` image.
- Efficiently update the icon when new usage data is polled.

**Non-Goals:**
- Changes to the iOS companion app or watchOS app.
- Changes to the core OAuth or polling logic (only observing the results).
- Complex multi-colored or interactive graphs in the menu bar (keep it simple and native-looking).

## Decisions

- **Dynamic Image Generation**: We will generate an `NSImage` dynamically using CoreGraphics. This image will draw a base shape (like the Claude logo outline or a simple circle) and overlay a progress indicator (e.g., a filled arc or ring) representing the current usage percentage (used / total).
- **Observation**: The menu bar controller will observe the shared state (e.g., `TokenStore` or similar) where the polled usage data is kept. When this state updates, the controller will recalculate the percentage, regenerate the `NSImage`, and set it on the `NSStatusItem.button.image`.
- **Icon Style**: A simple circular ring graph that fills up as usage increases. This is a common and easily readable pattern for menu bar resource monitors.

## Risks / Trade-offs

- **Performance (CPU Usage)**: Continuously redrawing the icon could use unnecessary CPU.
  - *Mitigation*: Only redraw the icon when the percentage changes by a visible amount (e.g., >1%), or only when a new polling result arrives (which is already infrequent).
- **Visibility in different themes**: The icon needs to look good in both Light and Dark mode on macOS.
  - *Mitigation*: Use template images (`isTemplate = true`) where possible, or explicitly draw using standard macOS label/control colors (`NSColor.controlTextColor` or similar) so the system handles the appearance adjustments automatically.

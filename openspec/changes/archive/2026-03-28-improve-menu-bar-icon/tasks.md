## 1. Dynamic Icon Generation

- [x] 1.1 Implement an extension or helper method to generate an `NSImage` representing the token usage (e.g., a ring graph or pie chart).
- [x] 1.2 Ensure the generated `NSImage` is drawn correctly as a template image (`isTemplate = true`) so it adapts to macOS light/dark modes automatically.

## 2. Menu Bar Controller Update

- [x] 2.1 Update the menu bar controller (`ClaudeTracker macOS` target) to observe the shared usage data state (e.g., `TokenStore` or equivalent).
- [x] 2.2 Add logic to update the `NSStatusItem.button.image` with the generated dynamic image when usage data is available and the user is authenticated.
- [x] 2.3 Add logic to display the static default app icon when the user is not authenticated or usage data is nil.
- [x] 2.4 Add a threshold check or update mechanism so that the icon updates only when the usage percentage changes, to avoid unnecessary CPU usage.

## 1. Shared Widget Snapshot Foundation

- [x] 1.1 Add shared widget snapshot models, freshness helpers, storage keys, and encode/decode helpers in `Shared/`
- [x] 1.2 Add shared widget formatting helpers for percentage, reset labels, and stale/mock state presentation without introducing widget views into `Shared/`
- [x] 1.3 Add shared widget route/deep-link definitions consumable by both iOS and macOS apps

## 2. iOS Host-App Widget Data Flow

- [x] 2.1 Configure an iOS widget App Group for the iPhone app and its widget extension target
- [x] 2.2 Extend the iOS iCloud-driven flow to derive and persist the latest widget snapshot whenever `UsageState` updates
- [x] 2.3 Preserve the last valid iOS widget snapshot when iCloud usage decoding fails or data is temporarily unavailable
- [x] 2.4 Trigger iOS widget timeline reloads after successful widget snapshot writes

## 3. macOS Host-App Widget Data Flow

- [x] 3.1 Configure a macOS widget App Group for the macOS app and its widget extension target
- [x] 3.2 Extend the macOS polling path to derive and persist the latest widget snapshot after successful usage polls
- [x] 3.3 Preserve the last valid macOS widget snapshot across transient poll failures, auth failures, and rate limits
- [x] 3.4 Trigger macOS widget timeline reloads after successful widget snapshot writes

## 4. Widget Extension Targets and Layouts

- [x] 4.1 Create the iOS widget extension target and add the three v1 widget variants: small ring, medium summary, and small compact metrics
- [x] 4.2 Create the macOS widget extension target and add the same three v1 widget variants adapted for desktop widget presentation
- [x] 4.3 Implement placeholder, waiting, stale, and mock rendering states in both widget targets
- [x] 4.4 Apply ClaudeCode theme colors, status thresholds, and extra-usage presentation consistently across widget variants

## 5. Widget Navigation and App Integration

- [x] 5.1 Add widget deep links that open the iOS app to the dashboard surface
- [x] 5.2 Add widget deep links that open the macOS app to the stats/detail window
- [x] 5.3 Wire host apps to handle the new widget routes without regressing existing launch behavior

## 6. Validation and Documentation

- [ ] 6.1 Manually verify iOS widget updates after new iCloud `usage.json` data arrives
- [ ] 6.2 Manually verify macOS widget updates after successful poll refreshes
- [ ] 6.3 Manually verify stale, waiting, and mock states in both widget platforms
- [ ] 6.4 Manually verify widget taps open the intended destination on iOS and macOS
- [ ] 6.5 Update repo documentation or screenshots if widget support becomes part of the documented feature set

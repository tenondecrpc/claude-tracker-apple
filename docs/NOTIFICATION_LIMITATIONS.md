# Notification Limitations Analysis

> **Date**: 2026-04-11
> **Status**: Documentation only -- no code changes proposed.

This document breaks down the current limitations of Tempo's notification system across all three platforms (macOS, iOS, watchOS), the architectural constraints that cause them, and what would be needed to resolve each one.

---

## Current Notification Architecture

```
macOS (SessionEventWriter)
  polls ~/.claude/projects/*/*.jsonl every 20s
  detects idle session (15s threshold)
  writes latest.json to iCloud Drive
      |
      v
iCloud Drive (Documents/Tempo/latest.json)
      |
      v
iOS (iCloudUsageReader)
  NSMetadataQuery watches for file changes
  decodes SessionInfo from latest.json
  triggers PhoneAlertManager (local UNNotification)
  relays SessionInfo to watch via WatchConnectivity
      |
      v
watchOS (WatchSessionReceiver)
  receives transferUserInfo payload
  triggers WatchAlertManager (local UNNotification)
  shows CompletionView sheet
```

---

## Limitation 1: No Real Push Notifications

**What happens now**: All notifications are **local** (`UNNotificationRequest` with `trigger: nil`). They are generated on-device by `PhoneAlertManager` (iOS) and `WatchAlertManager` (watchOS) when the app processes a new `SessionInfo`.

**Why real push isn't possible today**:
- No backend server exists to send APNs (Apple Push Notification service) payloads.
- No device token registration: neither iOS nor watchOS calls `UIApplication.registerForRemoteNotifications()` or collects device tokens.
- No database stores device tokens or user-to-device mappings.
- The `aps-environment = development` entitlement exists in all three targets, but it's unused -- it was likely added by Xcode when enabling the Push Notifications capability, not because any push code exists.
- The transport layer is purely iCloud Drive file sync -- there is no server that could initiate a push.

**Impact**: Notifications can only fire when the app's own code detects the event. If the app isn't running or the iCloud sync hasn't propagated, no notification is delivered.

**What would be needed**:
- A backend service (e.g., Cloudflare Worker, Supabase, custom server) that receives session events and sends APNs payloads.
- Device token registration on iOS and watchOS.
- APNs certificate or key configuration in Apple Developer portal.
- Server-side storage of device tokens.

---

## Limitation 2: iOS Notifications Require the App to Be in Foreground

**What happens now**: `iCloudUsageReader` uses `NSMetadataQuery` to detect iCloud file changes. This query **only runs while the app is in the foreground** (or briefly during a background fetch window, which is not configured).

**Evidence in code**:
- `TempoApp.swift:111-127` -- `onBecomeActive()` calls `iCloudReader.restart()` only when `scenePhase == .active`.
- No `UIBackgroundModes` are declared in any `Info.plist`.
- No `BGTaskScheduler` usage exists anywhere in the codebase.
- No `BGAppRefreshTaskRequest` or `BGProcessingTaskRequest` is registered.

**What this means in practice**:
- If a Claude Code session finishes while the iOS app is backgrounded or killed, the `NSMetadataQuery` does not fire.
- The `SessionInfo` is only picked up the **next time the user opens the iOS app**, at which point it may be stale or irrelevant.
- The `PhoneAlertManager.notifySessionCompletion()` call never happens until the app returns to foreground.

**What would be needed**:
- Enable `UIBackgroundModes: fetch` in the iOS target's `Info.plist`.
- Register a `BGAppRefreshTask` that periodically wakes the app to check iCloud for new files.
- Alternatively, use CloudKit subscriptions (`CKSubscription`) with push notifications to wake the app when a record changes -- but this requires migrating from iCloud Drive files to CloudKit records.

---

## Limitation 3: watchOS Notifications Require the App to Be in Foreground

**What happens now**: The watch receives data via `WCSession.transferUserInfo()`, which is a background-capable API. However:

- `WatchSessionReceiver` does receive `didReceiveUserInfo` callbacks in the background.
- `WatchAlertManager.notifySessionCompletion()` schedules a `UNNotificationRequest` with `trigger: nil` (immediate).
- **The issue**: `transferUserInfo` is queued and delivered at the system's discretion. When the watch app is not running, `WCSession` may not activate and the delegate may not receive the payload until the user raises their wrist or launches the app.

**Evidence in code**:
- `Tempo_WatchApp.swift:33-41` -- `onScenePhaseChange` only syncs authorization when `phase == .active`.
- No `WKBackgroundModes` are declared.
- No `WKApplicationRefreshBackgroundTask` or `WKExtendedRuntimeSession` usage exists.
- No `WKSnapshotRefreshBackgroundTask` is implemented.

**What this means in practice**:
- `transferUserInfo` payloads may sit in the WatchConnectivity queue for minutes or hours.
- The notification fires only once the watchOS extension processes the payload, which may be significantly delayed.
- The haptic/alert is not time-sensitive and may arrive long after the session actually ended.

**What would be needed**:
- Enable `WKBackgroundModes: remote-notification` to allow APNs to wake the watch extension.
- Implement `WKApplicationRefreshBackgroundTask` for periodic background wakeups.
- Or: rely on real push notifications (Limitation 1) sent directly to the watch via APNs, which would wake the extension immediately.

---

## Limitation 4: macOS Has No Notification at All

**What happens now**: The macOS menu bar app (`TempoMacApp`) detects completed sessions via `SessionEventWriter`, which polls `~/.claude/` every 20 seconds. When it finds a completed session, it writes `latest.json` to iCloud -- but it **does not display any notification to the macOS user**.

**Evidence in code**:
- `MacAppCoordinator` has no reference to `UNUserNotificationCenter` or any alert manager.
- `SessionEventWriter` writes to iCloud and logs, but has no notification side effect.
- `MacSettingsStore` has alert preference properties (`iPhoneAlertsEnabled`, `watchAlertsEnabled`) but no `macAlertsEnabled` equivalent.

**Impact**: The macOS user who is actively coding with Claude Code gets no haptic/sound/banner feedback when a session completes, even though the macOS app is the first to know about it.

**What would be needed**:
- Add a `MacAlertManager` similar to `PhoneAlertManager` using `UNUserNotificationCenter` on macOS.
- Add a `macAlertsEnabled` preference to `MacSettingsStore` and `SessionAlertPreferences`.
- Wire `SessionEventWriter` to trigger the notification when a new session is detected.

---

## Limitation 5: iCloud Sync Latency Is Unpredictable

**What happens now**: The entire notification pipeline depends on iCloud Drive file sync:
1. macOS writes `latest.json` to the iCloud ubiquity container.
2. Apple's iCloud daemon syncs the file to Apple servers.
3. Apple's servers push the change to the iOS device's iCloud daemon.
4. iOS `NSMetadataQuery` picks up the change.

**The problem**: Steps 2-3 have unpredictable latency. Apple does not guarantee any SLA for iCloud Drive sync speed. In practice:
- On the same Wi-Fi network: typically 5-30 seconds.
- On cellular or different networks: can take 1-5 minutes.
- Under heavy iCloud load or poor connectivity: can take 10+ minutes or fail silently.

**Impact**: Even if both iOS and watchOS apps are in the foreground, the notification may arrive 30 seconds to several minutes after the Claude Code session actually ended. This undermines the "real-time haptic alert" value proposition.

**What would be needed**:
- Supplement iCloud with a real-time channel (WebSocket, Server-Sent Events, or APNs push) for time-sensitive events.
- Keep iCloud as the durable sync mechanism, but use the real-time channel to trigger immediate wakeups.

---

## Limitation 6: Single-Session Detection Only

**What happens now**: `SessionEventWriter` writes only `latest.json` -- a single file representing the most recently completed session. If two sessions complete in rapid succession (or while iOS is backgrounded), only the latest one is captured.

**Evidence in code**:
- `SessionEventWriter.swift:71` -- always writes to the same `latest.json` path, overwriting any previous content.
- `iCloudUsageReader.swift:315-319` -- deduplicates by `sessionId`, so if it reads the same `latest.json` twice it skips it, but it cannot recover a session that was overwritten before being read.

**Impact**: Missed notifications for sessions that complete in close succession. The user only gets alerted about the last one.

**What would be needed**:
- Write each session to a unique file (e.g., `session-{id}.json`) or append to a journal file.
- iOS reader would process all unread entries and notify for each.

---

## Limitation 7: No Notification Delivery Confirmation or Retry

**What happens now**: Both `PhoneAlertManager` and `WatchAlertManager` schedule a local notification and log success/failure, but there is no retry mechanism if the notification fails to schedule.

**Evidence in code**:
- `PhoneAlertManager.swift:108-126` -- on `center.add(request)` failure, it only prints an error log. No retry. No fallback.
- `WatchAlertManager.swift:86-94` -- same pattern.
- The `lastAlertedSessionID` is set **only on success**, so a failed notification does leave the door open for a future attempt -- but nothing triggers that retry.

**Impact**: If `UNUserNotificationCenter.add()` fails (rare, but possible during system pressure), the notification is silently lost.

---

## Limitation 8: No Haptic Feedback on Watch Notification

**What happens now**: Despite the project plan mentioning `WKInterfaceDevice.current().play(.notification)` for haptics, **no haptic code exists in the codebase**.

**Evidence**: A grep for `haptic`, `WKInterfaceDevice`, and `.play(` across all Swift files returns zero relevant matches.

**What happens instead**: The watch relies on the system default behavior of `UNNotificationRequest` with `.sound = .default`, which may or may not include a haptic tap depending on the user's watch notification settings.

**Impact**: The "haptic alert" feature described in the project plan and README is not explicitly implemented. The watch may vibrate via the system notification sound, but there is no custom haptic sequence or guaranteed tactile feedback.

---

## Summary Table

| # | Limitation | Severity | Root Cause | Effort to Fix |
|---|---|---|---|---|
| 1 | No real push notifications | High | No backend, no device tokens, no APNs | High (requires server) |
| 2 | iOS requires foreground | High | No background modes, no BGTask | Medium |
| 3 | watchOS requires foreground-ish | High | transferUserInfo delivery is system-paced | Medium-High |
| 4 | macOS has no notifications | Medium | Not implemented | Low |
| 5 | iCloud sync latency | Medium | Architectural (file-based sync) | High (requires real-time channel) |
| 6 | Single-session detection | Low | latest.json overwrite design | Low |
| 7 | No notification retry | Low | No retry logic | Low |
| 8 | No explicit haptic on watch | Medium | Code not implemented | Low |

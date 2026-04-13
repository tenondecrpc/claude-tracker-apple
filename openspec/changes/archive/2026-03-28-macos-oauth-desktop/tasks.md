## 1. Xcode Project Setup

- [x] 1.1 Add new macOS app target "Tempo macOS" to `Tempo.xcodeproj` - SwiftUI lifecycle, menu bar app (no Dock icon via `LSUIElement = YES`)
- [x] 1.2 Link `Shared/` folder to the macOS target (same `PBXFileSystemSynchronizedRootGroup` pattern as iOS/watchOS)
- [ ] 1.3 Enable iCloud capability with "iCloud Documents" on macOS target (also verify iOS target has it)
  > ⚠️ **Bloqueado - requiere cuenta Apple Developer de pago ($99/año)**
  > La Personal Team gratuita no soporta capacidades iCloud.
  > Ver opciones en `docs/FUTURE_PLAN.md` → sección "iCloud Transport - Opciones".

## 2. macOS OAuth Client

- [x] 2.1 Create `Tempo macOS/MacOSAPIClient.swift` - OAuth PKCE flow using `NSWorkspace.shared.open()` for browser, `code#state` paste-code parsing, token exchange via POST to `https://platform.claude.com/v1/oauth/token`
- [x] 2.2 Implement `CredentialStore.swift` - read/write `~/.config/tempo-for-claude/credentials.json` with `0600` file permissions, `0700` directory permissions. Store `accessToken`, `refreshToken`, `expiresAt`, `scopes`
- [x] 2.3 Implement auto-restore on launch - check `credentials.json` for valid (non-expired) token, refresh if expired, skip sign-in UI if valid
- [x] 2.4 Implement token refresh on 401 - force-refresh once and retry, delete credentials on `invalid_grant`
- [x] 2.5 Implement sign-out - delete `credentials.json`, stop polling, return to sign-in UI

## 3. macOS Usage Poller + iCloud Writer

- [x] 3.1 Create `Tempo macOS/UsagePoller.swift` - poll `GET /api/oauth/usage` every 15 minutes with `Authorization: Bearer` and `anthropic-beta: oauth-2025-04-20` headers
- [x] 3.2 Map API response to `UsageState` - divide utilization by 100, parse ISO 8601 dates, set `isMocked = false`
- [x] 3.3 Implement reset timestamp reconciliation - preserve previous `resetAt5h`/`resetAt7d` when API returns null, discard on utilization drop
- [x] 3.4 Implement exponential backoff on 429 - use `Retry-After` header, cap at 3600s, resume 15min on success
- [x] 3.5 Write `UsageState` as JSON to `~/Library/Mobile Documents/com~apple~CloudDocs/Tempo/usage.json` - create directory if missing
  > ℹ️ El write al path iCloud Drive funciona sin entitlement en macOS ("Sign to Run Locally").
  > El archivo llega a iCloud. El problema es la **lectura en iOS** (ver task 5.1).
- [x] 3.6 Fire immediate poll on successful authentication

## 4. macOS Menu Bar UI

- [x] 4.1 Create `Tempo macOS/TempoMacApp.swift` - `@main` App with `MenuBarExtra` (system image icon, no Dock icon)
- [x] 4.2 Create sign-in view - "Sign in with Claude Code" button, TextField for paste-code, Submit/Cancel buttons
- [x] 4.3 Create authenticated view - show account email (from `~/.claude/.claude.json` `oauthAccount.emailAddress`), sign-out button, last poll timestamp
- [x] 4.4 Read Claude Code profile from `~/.claude/.claude.json` for display name/email (display only, not for auth)

## 5. iOS iCloud Reader (replace direct API polling)

- [x] 5.1 Create `Tempo/iCloudUsageReader.swift` - `NSMetadataQuery` watching `Tempo/usage.json` in iCloud Drive, decode `UsageState`, relay to watch via `WatchConnectivity`
  > ⚠️ `NSMetadataQueryUbiquitousDocumentsScope` requiere iCloud entitlement en iOS.
  > Código listo, pero no funcional hasta resolver task 1.3 (o cambiar transporte).
- [x] 5.2 Handle file not-yet-downloaded - call `startDownloadingUbiquitousItem(at:)`, wait for next update notification
- [x] 5.3 Restart `NSMetadataQuery` on `applicationDidBecomeActive` to catch changes from background
- [x] 5.4 Update iOS `ContentView.swift` - replace sign-in screen with "Connect via Mac app" status, show "Syncing from Mac" when `usage.json` is detected, show staleness indicator if data > 30min old

## 6. Documentation Updates

- [x] 6.1 Update `CLAUDE.md` - add macOS target to targets table, document new data flow
- [x] 6.2 Update `docs/FUTURE_PLAN.md` - reflect macOS-first auth architecture in Phase 1

## 7. Verification

- [x] 7.1 Build macOS target - compile sin errores ✓
- [x] 7.2 Sign in via browser OAuth on macOS - verify `credentials.json` created with correct permissions
  > ✓ OAuth funciona end-to-end. Fix requerido: activar "Outgoing Connections (Client)" en App Sandbox.
- [ ] 7.3 Verify poll fires and `usage.json` appears in iCloud Drive
  > Depende de 7.2 (sign-in) y de que iCloud Drive esté activo en el Mac.
- [ ] 7.4 Verify iOS app detects `usage.json` via `NSMetadataQuery` and relays to watch
  > ⚠️ Bloqueado por task 1.3 (iCloud entitlement en iOS).
- [ ] 7.5 Verify sign-out deletes credentials and stops polling
  > Pendiente: probar después de 7.2.

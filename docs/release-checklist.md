# MVP manual release checklist

Record the tested hardware, OS, OpenCode version, Tailscale version, iPhone model/iOS version, date, and tester in the release notes. Complete this checklist against the exact ZIP candidate; deterministic tests do not replace these real integrations.

## Automated candidate verification

- [ ] `./script/ci.sh` passes on macOS 26 Apple Silicon.
- [ ] `shasum -a 256 -c OpenCodeConnect.zip.sha256` verifies the downloaded candidate.
- [ ] `codesign --verify --deep --strict OpenCodeConnect.app` accepts the expanded app.
- [ ] The app has no Dock icon or permanent main window.
- [ ] Every Observed State uses text and a distinguishable symbol; meaning does not depend on color.
- [ ] Setup, Start, Stop, Retry, Complete Tailscale Setup, and Retry Inspection expose the correct single primary action.
- [ ] VoiceOver identifies the menu item, primary action, QR code, hidden/revealed credential, Endpoint actions, Settings, Diagnostics, and Quit.

## Dependencies and access

- [ ] Discover a real supported OpenCode installation and record its version/path.
- [ ] Discover a real supported Tailscale installation and record its version/path.
- [ ] Exercise first-time Tailscale Serve HTTPS approval through Complete Tailscale Setup.
- [ ] Start Protected Access and verify authenticated local and Tailscale Endpoint health.
- [ ] Confirm the Managed Server listens only on `127.0.0.1` and Funnel is not enabled.
- [ ] Scan the Endpoint-only QR code from an iPhone connected to the same tailnet.
- [ ] Enter the separate Access Credential, save it in Safari, reload, and confirm saved login succeeds.
- [ ] Bookmark the Endpoint, Stop and Start, and confirm the bookmark remains valid.
- [ ] Switch to Tailnet-Only Access through its warning and verify access without Basic Auth.
- [ ] Return to Protected Access and confirm the retained Access Credential works.

## Lifecycle and recovery

- [ ] Stop and confirm the matching Managed Route is removed before the Managed Server exits.
- [ ] Start again, Quit, and confirm the same route-first cleanup completes.
- [ ] Create an occupied backend-port conflict; confirm Conflict without termination or overwrite.
- [ ] Create an occupied/changed Serve route conflict; confirm Conflict without destructive mutation.
- [ ] Simulate an app crash with surviving managed resources; reopen and confirm safe adoption without duplicates.
- [ ] Change ownership evidence before reopen; confirm Conflict rather than adoption or cleanup.
- [ ] Sleep and wake with Enabled intent; confirm wake reconciliation returns to Available.
- [ ] Verify On External Power, Always, and Never on AC and battery, including prompt assertion release.
- [ ] Verify closed-lid availability is never promised in the interface or diagnostics.
- [ ] Verify login restores Enabled intent when Launch at Login is On.
- [ ] Verify logout/shutdown disables and attempts cleanup when Launch at Login is Off.
- [ ] Reboot and confirm both Launch at Login policies behave as documented.

## Privacy, installation, and removal

- [ ] Feed diagnostics hostile output containing a password, Authorization header, environment assignment, username, and sensitive path; confirm secrets are redacted and the report remains useful.
- [ ] Confirm diagnostics require review before copying and warn that local paths can be sensitive.
- [ ] Install the ZIP on a clean account and exercise Gatekeeper's Open Anyway flow.
- [ ] Replace the app with a newer candidate to verify the manual update procedure.
- [ ] Quit, remove the app, preferences, and optional Keychain credential using the README instructions.

# OpenCode Connect

OpenCode Connect is a menu-bar-only macOS utility that makes a separately installed OpenCode server available to an iPhone through a private Tailscale Serve route. Manage and see your tailscale endpoint to OpenCode at a glance. 

<img width="431" height="415" alt="image" src="https://github.com/user-attachments/assets/a96dbb84-a7c4-48d7-81ef-37d1e1971a99" />

OpenCode/Tailscale default CLI commands works great, but it's still clunky to share the endpoint to your phone, especially if you regularly have port conflicts from other dev processes. I wanted something simple that made it easier to see the OpenCode server you have running, and send your Tailscale endpoint to your phone. I considered a relay service, but didn't want extra background daemons. This is basically a menu bar GUI wrapper for existing OpenCode and Tailscale services that transparently manages an OpenCode server, an app-owned route, enrollment via QR code, recovery, and cleanup without adding invisible, unnecessary background daemons. 

## Support status

The MVP is required and tested on **macOS 26 on Apple Silicon** with Xcode 26. macOS 14 and Intel compatibility are best effort only; neither is claimed as supported until it has been verified on real hardware. The Swift package currently declares macOS 14 as its compilation floor to avoid gratuitous incompatibility, not as a support claim.

OpenCode and Tailscale are separate prerequisites. OpenCode Connect does not install, bundle, update, sign in to, or broadly configure either dependency.

## Security model

OpenCode Connect always launches its Managed Server on `127.0.0.1` and exposes it only through a private Tailscale Serve Managed Route. The bind address is not configurable. Tailscale Funnel, direct LAN exposure, and public endpoints are never supported.

Protected Access is the default and requires both tailnet authorization and OpenCode Basic Auth. Its generated six-word Access Credential is stored in the Mac Keychain. It is not embedded in the Endpoint or QR code, ordinary preferences, runtime records, logs, diagnostics, or command arguments. Tailnet-Only Access is an advanced reduced-defense mode where tailnet policy is the only request-level check.

The app is distributed outside the Mac App Store and is **not sandboxed**. This is necessary because OpenCode must retain normal access to user-selected projects and development tools. OpenCode owns Project Selection through its web interface; OpenCode Connect does not constrain folders or provide a second project picker.

The MVP has no analytics, remote telemetry, automatic crash upload, automatic updater, persistent helper, Developer ID signature, or notarization.

## Prerequisites

- A Mac running macOS 26 on Apple Silicon.
- Xcode 26 for a source build.
- [OpenCode](https://opencode.ai) installed separately.
- [Tailscale](https://tailscale.com/download/mac) installed, signed in, and connected on the Mac.
- Tailscale installed, signed in to the same tailnet, and connected on the iPhone.
- Permission from the tailnet owner to enable Tailscale Serve HTTPS when prompted.

The app searches common Homebrew, standalone, and App Store locations. Custom executable paths can be selected while Desired State is Disabled.

## Build from source

Clone the repository and run the complete automated suite:

```sh
git clone https://github.com/avoidthekitchen/opencode-connect.git
cd opencode-connect
./script/ci.sh
```

The repository is an open-source Swift Package Manager Xcode project. To build and run it in Xcode:

```sh
open Package.swift
```

In Xcode, select the `OpenCodeConnect` scheme and `My Mac`, then choose **Product > Run**. To build and launch the same `.app` bundle from Terminal:

```sh
./script/build_and_run.sh
```

`swift test` runs the Access Coordinator scenarios, recorded CLI parsing contract tests, and limited SwiftUI smoke/accessibility tests. `script/ci.sh` is the command used by GitHub Actions on `macos-26`; it runs Swift Testing as `swift test --parallel --num-workers 1` so process-lifecycle tests do not race each other on hosted macOS runners, then builds and verifies the release ZIP through `script/test_release.sh`. The large stdout/stderr pipe-drain stress tests are local-only because hosted macOS runners have repeatedly timed out those subprocesses without producing a product failure.

## Install a binary release

MVP ZIP releases are ad-hoc signed, not Developer ID signed or notarized. An ad-hoc signature verifies bundle integrity but does not establish an Apple-verified developer identity.

1. Download `OpenCodeConnect.zip` and `OpenCodeConnect.zip.sha256` from the same GitHub release.
2. In Terminal, change to the download directory and verify integrity:

   ```sh
   shasum -a 256 -c OpenCodeConnect.zip.sha256
   ```

3. Expand the ZIP and move `OpenCodeConnect.app` to `/Applications`.
4. Open the app. If Gatekeeper blocks it, open **System Settings > Privacy & Security**, find the OpenCode Connect message, choose **Open Anyway**, and confirm. Do this only after checking the checksum and release source.

Updates are manual: choose Quit so access is disabled and cleaned up, download and verify the newer release, then replace the existing app in `/Applications`. An unsigned DMG may be added later but is not required for the MVP.

To remove the app, choose Quit first and move `/Applications/OpenCodeConnect.app` to the Trash. To also remove preferences, run `defaults delete com.avoidthekitchen.OpenCodeConnect`. To remove the Access Credential, use **Delete Credential** before removing the app, or delete the `com.avoidthekitchen.OpenCodeConnect` / `protected-access` generic password in Keychain Access.

## Initial setup and iPhone enrollment

1. Open OpenCode Connect from the menu bar. Resolve any **Needs Setup** remediation for missing or invalid dependencies.
2. Select **Start**. Start persists Desired State as Enabled; a failure does not silently discard that intent.
3. If Tailscale reports that Serve is not enabled, select **Complete Tailscale Setup**. The app opens Tailscale's official approval URL only after this explicit action. Approve Serve, return to the app, and retry.
4. Wait for **Available**. Available means authenticated local health, the Managed Route, Endpoint discovery, and authenticated HTTPS access through the Endpoint all succeeded.
5. Select **Show QR Code**. The QR contains only the verified Endpoint.
6. Scan it on the connected iPhone. For Protected Access, enter username `opencode` and the separately revealed six-word Access Credential. Let Safari save the login, then bookmark the Endpoint.

The Endpoint normally remains stable across Start and Stop. If Tailscale's node or tailnet naming changes, the app warns that a saved bookmark may be stale.

## Normal operation

- **Start** sets Desired State to Enabled and reconciles toward Available.
- **Stop** sets Desired State to Disabled, removes the matching Managed Route first, stops the verified Managed Server, and releases any power assertion.
- **Quit** performs the same disable-and-cleanup contract before terminating the app.
- After a temporary failure, **Retry** performs a fresh bounded reconciliation. Ambiguous ownership produces **Conflict** and blocks destructive mutation.

If the app itself crashes, it cannot guarantee immediate cleanup. On the next launch it conservatively reconciles persisted identity and live evidence; it adopts only a verified Managed Server and Managed Route and never terminates a process based only on its name or occupied port.

## Settings

Operational settings are editable only while Desired State is Disabled:

- Protected Access or advanced Tailnet-Only Access.
- Basic Auth username, Access Credential rotation, and explicit credential deletion.
- OpenCode backend port (default `4096`) and Tailscale Serve HTTPS port (default `443`).
- Custom OpenCode and Tailscale executable paths.
- Reset to Defaults. Reset preserves the Access Credential and does not mutate active resources.

Launch at Login may be changed at any time and defaults Off. When enabled, login reconciles toward persisted Desired State. When disabled, logout or shutdown disables intent and attempts cleanup.

## Sleep and power limitations

Availability Policy defaults to **On External Power**. **Always** also prevents idle system sleep on battery; **Never** permits normal idle sleep. The app uses a native macOS idle-sleep assertion and does not launch `caffeinate` or install an always-running helper.

No policy guarantees availability while a MacBook lid is closed. Sleep can make the Endpoint unreachable. Sleep preserves Desired State, and wake triggers reconciliation while the app is running.

## Diagnostics and troubleshooting

**Diagnostics** shows a reviewable, sanitized report before copying. It includes versions, detected executable paths, Desired and Observed State, component health, the route target, failure stage, and recent bounded lifecycle output. Credentials, authorization headers, and environment secrets are redacted. Local paths can still be sensitive, so review the report before sharing it.

Common failures:

- **OpenCode or Tailscale missing:** install it separately or select its executable while access is Disabled.
- **Tailscale signed out or disconnected:** sign in and connect on both the Mac and iPhone, then Retry.
- **Serve approval required:** use Complete Tailscale Setup and approve the official Tailscale URL.
- **Conflict:** inspect the reported process, port, or route evidence. The app will not overwrite or remove an unrecognized resource. Resolve it externally or choose different ports while Disabled, then Retry Inspection.
- **Degraded:** the Managed Server or route exists but Endpoint health is temporarily unavailable. Keep the Mac awake and connected; bounded recovery may restore Available.
- **Safari rejects saved credentials after rotation:** reveal the new credential and update the saved login on the iPhone.
- **Endpoint bookmark stopped working:** compare it with the currently verified Endpoint; a Tailscale rename can change the URL.

Do not use `tailscale serve reset` as routine troubleshooting because it can destroy unrelated Serve configuration.

## Release process and deferred work

Run `./script/release.sh` to create `dist/release/OpenCodeConnect.zip` and `OpenCodeConnect.zip.sha256`. See [the manual release checklist](docs/release-checklist.md) before publication and [the MVP release notes](docs/releases/0.1.0.md) for known limitations.

Developer ID signing, notarization, paid Apple Developer membership, automatic updates, guaranteed Intel support, and guaranteed macOS 14 support are explicitly deferred. Source-only publication may precede the ZIP. An unsigned DMG is optional after lifecycle behavior stabilizes and is not an MVP blocker.

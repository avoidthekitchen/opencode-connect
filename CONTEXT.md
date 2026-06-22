# OpenCode Connect

OpenCode Connect manages temporary, private mobile access to an OpenCode server running on a Mac.

## Language

**Desired State**:
The user’s persisted intent for remote access to be either Enabled or Disabled. Start sets it to Enabled; Stop and normal Quit set it to Disabled.
_Avoid_: Process state, current state

**Observed State**:
The app’s current assessment of the OpenCode process, Tailscale route, and endpoint health: Stopped, Needs Setup, Starting, Available, Degraded, Stopping, Conflict, or Error. Available requires verified authenticated access through the Endpoint.
_Avoid_: Desired state, preference

**Protected Access**:
The default access mode in which both tailnet authorization and OpenCode Basic Auth are required.
_Avoid_: Password mode, secure mode

**Tailnet-Only Access**:
An advanced access mode in which tailnet authorization is the only request-level access check. OpenCode remains bound to loopback and is never exposed through Tailscale Funnel.
_Avoid_: Unsecured access, public access

**Access Credential**:
The persistent OpenCode Basic Auth username and generated passphrase used by Protected Access. It is stored in the Mac Keychain and enrolled into the iPhone browser during initial setup.
_Avoid_: Tailscale password, API key, QR credential

**Project Selection**:
The choice of local folder OpenCode uses for a session. OpenCode owns this choice through its web interface; OpenCode Connect does not configure or constrain it.
_Avoid_: App working directory, default project setting

**Managed Route**:
The Tailscale Serve mapping created and currently recognized as owned by OpenCode Connect. The app may reconcile or remove it only while its target still matches the expected OpenCode endpoint.
_Avoid_: Tailscale configuration, Serve state

**Managed Server**:
An OpenCode server launched by OpenCode Connect whose persisted runtime identity and authenticated health can still be verified. The app does not adopt or terminate an arbitrary process based only on its name or port.
_Avoid_: OpenCode process, port occupant

**Conflict**:
An Observed State in which existing process or route evidence cannot be safely recognized as managed by OpenCode Connect. The app blocks automatic start and cleanup until the conflict is explicitly resolved.
_Avoid_: Error, stale state

**Endpoint**:
The currently verified Tailscale node HTTPS URL presented for remote access, bookmarking, and QR-code enrollment. It is discovered from Tailscale rather than constructed by the app.
_Avoid_: Backend address, Managed Route, mDNS name

**Availability Policy**:
The user’s choice of when Enabled access may prevent idle system sleep: on external power, always, or never. It does not promise availability while the MacBook lid is closed.
_Avoid_: Sleep blocker, always online

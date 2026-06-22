# Expose OpenCode only through Tailscale

OpenCode Connect will bind its Managed Server exclusively to `127.0.0.1` and expose it remotely only through a private Tailscale Serve Managed Route. The bind address is not configurable, Tailscale Funnel is unsupported, and Protected Access adds OpenCode Basic Auth by default; this deliberately trades general-purpose network flexibility for a small, defensible security boundary suitable for an agent with filesystem and shell access.

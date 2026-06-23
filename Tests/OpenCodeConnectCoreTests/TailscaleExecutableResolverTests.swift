import Testing
@testable import OpenCodeConnectCore

@Test("Tailscale executable resolver centralizes known paths and App Store CLI environment")
func tailscaleExecutableResolverCentralizesPathAndEnvironment() {
    #expect(TailscaleExecutableResolver.knownPaths == [
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ])

    #expect(TailscaleExecutableResolver.environment(
        for: "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    ) == ["TS_MAC_CLIENT_USE_CLI": "1"])
    #expect(TailscaleExecutableResolver.environment(for: "/opt/homebrew/bin/tailscale") == [:])
}

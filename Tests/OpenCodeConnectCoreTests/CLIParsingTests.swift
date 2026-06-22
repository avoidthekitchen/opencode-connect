import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("recorded OpenCode version output yields a bounded version string")
func parsesOpenCodeVersionFixture() throws {
    let output = try fixture("opencode-version", extension: "txt")

    #expect(CLIOutputParser.openCodeVersion(output) == "1.1.25")
}

@Test("recorded Tailscale version output yields the client version")
func parsesTailscaleVersionFixture() throws {
    let output = try fixture("tailscale-version", extension: "txt")

    #expect(CLIOutputParser.tailscaleVersion(output) == "1.82.5")
}

@Test("recorded running Tailscale status is connected")
func parsesConnectedTailscaleStatusFixture() throws {
    let output = try fixture("tailscale-status-running", extension: "json")

    #expect(CLIOutputParser.tailscaleConnection(output) == .connected)
}

@Test("recorded NeedsLogin status is signed out")
func parsesSignedOutTailscaleStatusFixture() throws {
    let output = try fixture("tailscale-status-needs-login", extension: "json")

    #expect(CLIOutputParser.tailscaleConnection(output) == .signedOut)
}

@Test("recorded Serve output yields only the official approval URL")
func parsesServeApprovalFixture() throws {
    let output = try fixture("tailscale-serve-approval", extension: "txt")

    #expect(CLIOutputParser.tailscaleApprovalURL(output) == URL(string: "https://login.tailscale.com/admin/serve?node=example"))
    #expect(CLIOutputParser.tailscaleApprovalURL("Visit https://example.com/not-official") == nil)
}

private func fixture(_ name: String, extension fileExtension: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: fileExtension))
    return try String(contentsOf: url, encoding: .utf8)
}

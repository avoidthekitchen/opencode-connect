import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("local diagnostics bound captured output and redact hostile secret-bearing content")
func localDiagnosticsAreBoundedAndRedacted() async {
    let diagnostics = LocalDiagnostics(capacity: 2, maximumEntryLength: 240)
    let credential = "alpha bravo charlie delta echo foxtrot"
    let hostile = """
    Authorization: Basic dXNlcjpzZWNyZXQ=
    OPENCODE_SERVER_PASSWORD=\(credential)
    QR_PAYLOAD=https://user:\(credential)@mac.tailnet.ts.net
    COMPLETE_ENV={HOME=/Users/alice, TOKEN=private-token}
    useful failure: endpoint timed out
    """

    await diagnostics.recordLifecycle("starting", sensitiveValues: [credential, "private-token"])
    await diagnostics.recordCommandOutput(hostile, sensitiveValues: [credential, "private-token"])
    await diagnostics.recordLifecycle("retrying", sensitiveValues: [credential])

    let entries = await diagnostics.recentEntries()
    let text = entries.joined(separator: "\n")
    #expect(entries.count == 2)
    #expect(entries.allSatisfy { $0.count <= 240 })
    #expect(!text.contains(credential))
    #expect(!text.contains("dXNlcjpzZWNyZXQ="))
    #expect(!text.contains("private-token"))
    #expect(!text.contains("user:"))
    #expect(!text.contains("COMPLETE_ENV={"))
    #expect(text.contains("useful failure: endpoint timed out"))
}

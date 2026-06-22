import SwiftUI
import Testing
@testable import OpenCodeConnect
import OpenCodeConnectCore

@Test("enrollment view renders a safe QR and explicit credential controls")
@MainActor
func enrollmentViewRenders() {
    let view = EnrollmentView(
        enrollment: EnrollmentViewState(
            endpoint: URL(string: "https://test.tailnet.ts.net")!,
            qrPayload: "https://test.tailnet.ts.net",
            username: "opencode",
            revealedCredential: "alpha bravo charlie delta echo foxtrot",
            endpointChangeWarning: "The Endpoint changed.",
            guidance: ["Ensure Tailscale is connected on the iPhone."]
        ),
        revealCredential: {},
        copyCredential: {}
    )

    #expect(ImageRenderer(content: view).nsImage != nil)
}

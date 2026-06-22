import SwiftUI
import Testing
@testable import OpenCodeConnect
import OpenCodeConnectCore

@Test("Settings renders access modes, advanced ports, and credential controls")
@MainActor
func settingsViewRenders() {
    let coordinator = AccessCoordinator(dependencies: SmokeReadyDependencies())
    let view = SettingsView(coordinator: coordinator)

    #expect(ImageRenderer(content: view).nsImage != nil)
}

private struct SmokeReadyDependencies: DependencyReadinessChecking {
    func evaluate(settings: DependencySettings) async -> ReadinessEvaluation {
        ReadinessEvaluation(
            openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
            tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
        )
    }
}

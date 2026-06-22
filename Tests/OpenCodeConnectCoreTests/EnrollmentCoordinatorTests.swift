import Foundation
import Testing
@testable import OpenCodeConnectCore

private let enrollmentReadyDependencies = EnrollmentDependencies()
private let verifiedEndpoint = URL(string: "https://test.tailnet.ts.net")!

@Test("enrollment actions are unavailable before an Endpoint is verified")
@MainActor
func enrollmentIsUnavailableWithoutVerifiedEndpoint() async {
    let coordinator = AccessCoordinator(dependencies: enrollmentReadyDependencies)
    await coordinator.handle(.evaluateReadiness)
    #expect(coordinator.viewModel.enrollment == .unavailable)
}

@Test("a verified Endpoint enables enrollment with the Endpoint-only QR payload")
@MainActor
func verifiedEndpointEnablesSafeEnrollment() async {
    let coordinator = enrollmentCoordinator()
    await coordinator.handle(.start)
    #expect(coordinator.viewModel.enrollment.endpoint == verifiedEndpoint)
    #expect(coordinator.viewModel.enrollment.qrPayload == verifiedEndpoint.absoluteString)
    #expect(coordinator.viewModel.enrollment.username == "opencode")
}

@Test("an Endpoint containing credentials is rejected before it can become a QR payload")
@MainActor
func credentialBearingEndpointIsRejected() async {
    let coordinator = enrollmentCoordinator(
        route: EnrollmentRoute(endpoint: URL(string: "https://opencode:secret@test.tailnet.ts.net")!)
    )
    await coordinator.handle(.start)
    #expect(coordinator.viewModel.observedState == .error)
    #expect(coordinator.viewModel.enrollment == .unavailable)
}

@Test("Endpoint actions use only the verified Endpoint")
@MainActor
func endpointActionsUseVerifiedEndpoint() async {
    let opener = EnrollmentURLOpener()
    let clipboard = EnrollmentClipboard()
    let coordinator = enrollmentCoordinator(opener: opener, clipboard: clipboard)
    await coordinator.handle(.start)
    await coordinator.handle(.openEndpoint)
    await coordinator.handle(.copyEndpoint)
    #expect(await opener.values == [verifiedEndpoint])
    #expect(await clipboard.values == [verifiedEndpoint.absoluteString])
}

@Test("Access Credential reveal and copy require explicit actions")
@MainActor
func credentialActionsAreExplicit() async {
    let clipboard = EnrollmentClipboard()
    let coordinator = enrollmentCoordinator(clipboard: clipboard)
    await coordinator.handle(.start)
    #expect(coordinator.viewModel.enrollment.revealedCredential == nil)
    #expect(await clipboard.values.isEmpty)
    await coordinator.handle(.revealCredential)
    #expect(coordinator.viewModel.enrollment.revealedCredential == "alpha bravo charlie delta echo foxtrot")
    await coordinator.handle(.copyCredential)
    #expect(await clipboard.values == ["alpha bravo charlie delta echo foxtrot"])
}

@Test("a changed Endpoint warns about stale bookmarks and persists only the current Endpoint")
@MainActor
func changedEndpointWarnsAndPersistsCurrentEndpoint() async {
    let store = EnrollmentEndpointStore(existing: URL(string: "https://old.tailnet.ts.net")!)
    let coordinator = enrollmentCoordinator(endpointStore: store)
    await coordinator.handle(.start)
    #expect(coordinator.viewModel.enrollment.endpointChangeWarning?.contains("bookmark may be stale") == true)
    #expect(await store.saved == [verifiedEndpoint])
}

@Test("enrollment guidance covers the one-time Safari flow")
@MainActor
func enrollmentGuidanceCoversSafariFlow() async {
    let coordinator = enrollmentCoordinator()
    await coordinator.handle(.start)
    let guidance = coordinator.viewModel.enrollment.guidance.joined(separator: " ")
    for requiredTerm in ["Tailscale", "iPhone", "Safari", "username", "passphrase", "iCloud Passwords"] {
        #expect(guidance.contains(requiredTerm))
    }
}

@MainActor
private func enrollmentCoordinator(
    opener: any ExternalURLOpening = NoopURLOpener(),
    clipboard: any ClipboardWriting = NoopClipboard(),
    endpointStore: any LastVerifiedEndpointPersisting = NoopLastVerifiedEndpointStore(),
    route: any ManagedRouteControlling = EnrollmentRoute(endpoint: verifiedEndpoint)
) -> AccessCoordinator {
    AccessCoordinator(
        dependencies: enrollmentReadyDependencies,
        urlOpener: opener,
        clipboard: clipboard,
        endpointStore: endpointStore,
        credentialStore: EnrollmentCredentialStore(),
        passphraseGenerator: EnrollmentPassphraseGenerator(),
        server: EnrollmentServer(),
        route: route,
        homeDirectory: URL(fileURLWithPath: "/Users/test")
    )
}

private struct EnrollmentDependencies: DependencyReadinessChecking {
    func evaluate(settings: DependencySettings) async -> ReadinessEvaluation {
        ReadinessEvaluation(
            openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
            tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
        )
    }
}

private actor EnrollmentCredentialStore: AccessCredentialStoring {
    func load() async throws -> String? { "alpha bravo charlie delta echo foxtrot" }
    func save(_ credential: String) async throws {}
    func delete() async throws {}
}

private struct EnrollmentPassphraseGenerator: PassphraseGenerating {
    func generate() throws -> String { "unused" }
}

private actor EnrollmentServer: ManagedServerControlling {
    func launch(_ configuration: ManagedServerConfiguration) async throws -> Bool { true }
    func runtimeRecord() async throws -> ManagedServerRecord? { nil }
    func verifyLocalHealth(authentication: AccessAuthentication) async throws {}
    func stopGracefully(timeout: Duration) async -> Bool { true }
    func ownershipIsVerified() async -> Bool { true }
    func forceStop() async {}
}

private actor EnrollmentRoute: ManagedRouteControlling {
    let endpoint: URL
    init(endpoint: URL) { self.endpoint = endpoint }
    func inspect(httpsPort: Int, backendPort: Int) async throws -> ManagedRouteInspection { .available }
    func create(tailscalePath: String, httpsPort: Int, backendPort: Int) async throws {}
    func discoverEndpoint(httpsPort: Int) async throws -> URL { endpoint }
    func verifyEndpoint(_ endpoint: URL, authentication: AccessAuthentication) async throws {}
    func removeIfMatching(httpsPort: Int, backendPort: Int) async throws {}
}

private actor EnrollmentURLOpener: ExternalURLOpening {
    private(set) var values: [URL] = []
    func open(_ url: URL) async { values.append(url) }
}

private actor EnrollmentClipboard: ClipboardWriting {
    private(set) var values: [String] = []
    func write(_ value: String) async { values.append(value) }
}

private actor EnrollmentEndpointStore: LastVerifiedEndpointPersisting {
    private let existing: URL?
    private(set) var saved: [URL] = []
    init(existing: URL?) { self.existing = existing }
    func load() async -> URL? { existing }
    func save(_ endpoint: URL) async { saved.append(endpoint) }
}

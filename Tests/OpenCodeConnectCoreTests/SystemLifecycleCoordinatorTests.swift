import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("Launch at Login defaults Off and can change while access is Enabled")
@MainActor
func launchAtLoginIsIndependentFromOperationalSettings() async {
    let loginItem = LifecycleLoginItem()
    let coordinator = AccessCoordinator(
        dependencies: LifecycleDependencies(),
        initialDesiredState: .enabled,
        loginItem: loginItem
    )

    #expect(coordinator.settingsViewModel.launchAtLogin == false)

    await coordinator.handle(.updateLaunchAtLogin(true))

    #expect(coordinator.settingsViewModel.launchAtLogin == true)
    #expect(await loginItem.values == [true])
    #expect(coordinator.viewModel.desiredState == .enabled)
}

@Test("Login reconciles persisted Enabled access and leaves Disabled access idle")
@MainActor
func loginReconcilesPersistedIntent() async {
    let enabled = lifecycleCoordinator(initialDesiredState: .enabled, loginEnabled: true)
    await enabled.handle(.login)
    #expect(enabled.viewModel.observedState == .available)

    let disabled = lifecycleCoordinator(initialDesiredState: .disabled, loginEnabled: true)
    await disabled.handle(.login)
    #expect(disabled.viewModel.desiredState == .disabled)
    #expect(disabled.viewModel.observedState == .stopped)
}

@Test("On External Power acquires on AC and releases promptly on battery")
@MainActor
func externalPowerPolicyTracksPowerSource() async {
    let power = LifecyclePower(source: .external)
    let coordinator = lifecycleCoordinator(
        initialDesiredState: .disabled,
        loginEnabled: false,
        power: power
    )

    await coordinator.handle(.start)
    #expect(await power.values == [true])

    await power.setSource(.battery)
    await coordinator.handle(.powerSourceChanged)
    #expect(await power.values == [true, false])
    #expect(coordinator.viewModel.availabilityWarning?.contains("battery") == true)
}

@Test("Availability policy transitions update an active assertion and Stop releases it")
@MainActor
func availabilityPoliciesAndStopReleaseAssertion() async {
    let power = LifecyclePower(source: .battery)
    let coordinator = lifecycleCoordinator(initialDesiredState: .disabled, loginEnabled: false, power: power)
    await coordinator.handle(.start)
    #expect(await power.values == [false])

    await coordinator.handle(.updateAvailabilityPolicy(.always))
    await coordinator.handle(.updateAvailabilityPolicy(.never))
    await coordinator.handle(.stop)

    #expect(await power.values == [false, true, false, false])
    #expect(coordinator.settingsViewModel.availabilityPolicy == .never)
}

@Test("Sleep preserves Enabled intent and Wake re-verifies the Endpoint")
@MainActor
func sleepAndWakeRecovery() async {
    let coordinator = lifecycleCoordinator(initialDesiredState: .disabled, loginEnabled: true)
    await coordinator.handle(.start)

    await coordinator.handle(.sleep)
    #expect(coordinator.viewModel.desiredState == .enabled)
    #expect(coordinator.viewModel.observedState == .degraded)
    #expect(coordinator.viewModel.endpoint == nil)

    await coordinator.handle(.wake)
    #expect(coordinator.viewModel.observedState == .available)
    #expect(coordinator.viewModel.endpoint == URL(string: "https://test.tailnet.ts.net"))
}

@Test("Logout disables and cleans up only when Launch at Login is Off")
@MainActor
func logoutPolicyFollowsLaunchAtLogin() async {
    let offStore = LifecycleDesiredStateStore()
    let off = lifecycleCoordinator(initialDesiredState: .disabled, loginEnabled: false, desiredStateStore: offStore)
    await off.handle(.start)
    await off.handle(.logoutOrShutdown)
    #expect(off.viewModel.desiredState == .disabled)
    #expect(await offStore.values.last == .disabled)

    let onStore = LifecycleDesiredStateStore()
    let on = lifecycleCoordinator(initialDesiredState: .disabled, loginEnabled: true, desiredStateStore: onStore)
    await on.handle(.start)
    await on.handle(.logoutOrShutdown)
    #expect(on.viewModel.desiredState == .enabled)
    #expect(await onStore.values.last == .enabled)
}

@Test("Failure recovery releases an active idle-sleep assertion")
@MainActor
func failureReleasesAssertion() async {
    let power = LifecyclePower(source: .external)
    let route = LifecycleRoute()
    let coordinator = lifecycleCoordinator(
        initialDesiredState: .disabled,
        loginEnabled: false,
        power: power,
        route: route,
        retryPolicy: RetryPolicy(maximumAttempts: 1, delays: [])
    )
    await coordinator.handle(.start)
    await route.setEndpointFailure(true)

    await coordinator.handle(.checkHealth)

    #expect(coordinator.viewModel.observedState == .error)
    #expect(await power.values == [true, false])
}

@Test("Power assertion acquisition failure degrades availability instead of reporting success")
@MainActor
func powerAssertionFailureIsVisible() async {
    let power = FailingLifecyclePower()
    let coordinator = lifecycleCoordinator(
        initialDesiredState: .disabled,
        loginEnabled: false,
        power: power
    )

    await coordinator.handle(.start)

    #expect(coordinator.viewModel.observedState == .degraded)
    #expect(coordinator.viewModel.availabilityWarning?.contains("could not be kept awake") == true)
    #expect(coordinator.viewModel.components.first { $0.name == "Keep Awake" }?.status == .needsSetup)
}

@Test("Explicit Quit disables access and releases the assertion regardless of login setting")
@MainActor
func explicitQuitDisablesAndReleases() async {
    let power = LifecyclePower(source: .external)
    let store = LifecycleDesiredStateStore()
    let coordinator = lifecycleCoordinator(
        initialDesiredState: .disabled,
        loginEnabled: true,
        power: power,
        desiredStateStore: store
    )
    await coordinator.handle(.start)

    await coordinator.handle(.quit)

    #expect(coordinator.viewModel.desiredState == .disabled)
    #expect(await store.values.last == .disabled)
    #expect(await power.values == [true, false])
}

@MainActor
private func lifecycleCoordinator(
    initialDesiredState: DesiredState,
    loginEnabled: Bool,
    power: any PowerAssertionControlling = LifecyclePower(source: .external),
    desiredStateStore: LifecycleDesiredStateStore = LifecycleDesiredStateStore(),
    route: LifecycleRoute = LifecycleRoute(),
    retryPolicy: RetryPolicy = RetryPolicy()
) -> AccessCoordinator {
    AccessCoordinator(
        dependencies: LifecycleDependencies(),
        initialDesiredState: initialDesiredState,
        credentialStore: LifecycleCredentialStore(),
        passphraseGenerator: LifecyclePassphraseGenerator(),
        server: LifecycleServer(),
        route: route,
        desiredStateStore: desiredStateStore,
        retryPolicy: retryPolicy,
        loginItem: LifecycleLoginItem(enabled: loginEnabled),
        power: power
    )
}

private actor LifecycleDesiredStateStore: DesiredStatePersisting {
    private(set) var values: [DesiredState] = []
    nonisolated func load() -> DesiredState { .disabled }
    func save(_ desiredState: DesiredState) async { values.append(desiredState) }
}

private actor LifecyclePower: PowerAssertionControlling {
    private var source: PowerSource
    private(set) var values: [Bool] = []
    init(source: PowerSource) { self.source = source }
    func currentSource() async -> PowerSource { source }
    func setSource(_ source: PowerSource) { self.source = source }
    func setIdleSleepPreventionRequired(_ required: Bool) async { values.append(required) }
}

private actor FailingLifecyclePower: PowerAssertionControlling {
    func currentSource() async -> PowerSource { .external }
    func setIdleSleepPreventionRequired(_ required: Bool) async throws {
        if required { throw LifecyclePowerFailure.unavailable }
    }
}

private enum LifecyclePowerFailure: LocalizedError {
    case unavailable
    var errorDescription: String? { "Assertion service unavailable." }
}

private struct LifecycleDependencies: DependencyReadinessChecking {
    func evaluate(settings: DependencySettings) async -> ReadinessEvaluation {
        ReadinessEvaluation(
            openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
            tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
        )
    }
}

private actor LifecycleLoginItem: LaunchAtLoginControlling {
    private let enabled: Bool
    private(set) var values: [Bool] = []
    init(enabled: Bool = false) { self.enabled = enabled }
    nonisolated func isEnabled() -> Bool { enabled }
    func setEnabled(_ enabled: Bool) async throws { values.append(enabled) }
}

private struct LifecycleCredentialStore: AccessCredentialStoring {
    func load() async throws -> String? { "secret" }
    func save(_ credential: String) async throws {}
    func delete() async throws {}
}

private struct LifecyclePassphraseGenerator: PassphraseGenerating {
    func generate() throws -> String { "unused" }
}

private actor LifecycleServer: ManagedServerControlling {
    func launch(_ configuration: ManagedServerConfiguration) async throws -> Bool { true }
    func runtimeRecord() async throws -> ManagedServerRecord? {
        ManagedServerRecord(processIdentifier: 42, executablePath: "/test/opencode", backendPort: 4096, executableFingerprint: "test")
    }
    func inspect(record: ManagedServerRecord?, expectedConfiguration: ManagedServerConfiguration, authentication: AccessAuthentication) async -> ManagedServerInspection { .missing }
    func verifyLocalHealth(authentication: AccessAuthentication) async throws {}
    func stopGracefully(timeout: Duration) async -> Bool { true }
    func ownershipIsVerified() async -> Bool { true }
    func forceStop() async {}
}

private actor LifecycleRoute: ManagedRouteControlling {
    private var endpointFailure = false
    func setEndpointFailure(_ fails: Bool) { endpointFailure = fails }
    func inspect(httpsPort: Int, backendPort: Int) async throws -> ManagedRouteInspection { .matching }
    func create(tailscalePath: String, httpsPort: Int, backendPort: Int) async throws {}
    func discoverEndpoint(httpsPort: Int) async throws -> URL { URL(string: "https://test.tailnet.ts.net")! }
    func verifyEndpoint(_ endpoint: URL, authentication: AccessAuthentication) async throws {
        if endpointFailure { throw LifecycleFailure.endpoint }
    }
    func removeIfMatching(httpsPort: Int, backendPort: Int) async throws {}
}

private enum LifecycleFailure: Error { case endpoint }

import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("transient startup failure retries on the deterministic schedule and recovers")
@MainActor
func transientStartupFailureRetriesAndRecovers() async {
    let scheduler = RecoveryScheduler()
    let route = RecoveryRoute(endpointFailures: 1)
    let coordinator = recoveryCoordinator(route: route, scheduler: scheduler)

    await coordinator.handle(.start)

    #expect(coordinator.viewModel.observedState == .available)
    #expect(await scheduler.sleeps == [.seconds(1)])
    #expect(await route.endpointVerificationCount == 2)
}

@Test("retry exhaustion preserves Enabled intent and publishes stable staged Error")
@MainActor
func retryExhaustionPublishesStableError() async {
    let scheduler = RecoveryScheduler()
    let route = RecoveryRoute(endpointFailures: .max)
    let coordinator = recoveryCoordinator(route: route, scheduler: scheduler)

    await coordinator.handle(.start)

    #expect(coordinator.viewModel.desiredState == .enabled)
    #expect(coordinator.viewModel.observedState == .error)
    #expect(coordinator.viewModel.failedStage == .endpointVerification)
    #expect(coordinator.viewModel.remediation?.contains("Retry") == true)
    #expect(coordinator.viewModel.primaryAction == .retry)
    #expect(await scheduler.sleeps == [.seconds(1), .seconds(2)])
    #expect(await route.endpointVerificationCount == 3)

    await coordinator.handle(.reconcile)

    #expect(coordinator.viewModel.observedState == .error)
    #expect(await route.endpointVerificationCount == 3)
}

@Test("Retry reconciles from fresh ownership evidence and Stop cleans verified resources")
@MainActor
func retryAndStopUseFreshOwnershipEvidence() async {
    let scheduler = RecoveryScheduler()
    let route = RecoveryRoute(endpointFailures: .max)
    let desiredStates = RecoveryDesiredStateStore()
    let coordinator = AccessCoordinator(
        dependencies: RecoveryDependencies(),
        credentialStore: RecoveryCredentialStore(),
        passphraseGenerator: RecoveryPassphraseGenerator(),
        server: RecoveryServer(),
        route: route,
        desiredStateStore: desiredStates,
        retryScheduler: scheduler,
        retryPolicy: RetryPolicy(maximumAttempts: 1, delays: [])
    )
    await coordinator.handle(.start)
    await route.setEndpointFailures(0)

    await coordinator.handle(.retry)
    await coordinator.handle(.stop)

    #expect(await route.inspectionCount == 3)
    #expect(await route.removalCount == 1)
    #expect(await desiredStates.saved == [.enabled, .enabled, .disabled])
    #expect(coordinator.viewModel.desiredState == .disabled)
    #expect(coordinator.viewModel.observedState == .stopped)
}

@Test("temporary Endpoint loss publishes Degraded and recovery re-verifies the complete path")
@MainActor
func degradedRecoveryReverifiesCompletePath() async {
    let scheduler = ControlledRecoveryScheduler()
    let route = RecoveryRoute(endpointFailures: 0)
    let server = RecoveryServer()
    let coordinator = AccessCoordinator(
        dependencies: RecoveryDependencies(),
        initialDesiredState: .enabled,
        credentialStore: RecoveryCredentialStore(),
        passphraseGenerator: RecoveryPassphraseGenerator(),
        server: server,
        route: route,
        retryScheduler: scheduler,
        retryPolicy: RetryPolicy(maximumAttempts: 2, delays: [.seconds(1)])
    )
    await coordinator.handle(.reconcile)
    await route.setEndpointFailures(1)

    let healthCheck = Task { await coordinator.handle(.checkHealth) }
    await scheduler.waitUntilSleeping()

    #expect(coordinator.viewModel.observedState == .degraded)
    #expect(coordinator.viewModel.desiredState == .enabled)

    await scheduler.resume()
    await healthCheck.value

    #expect(coordinator.viewModel.observedState == .available)
    #expect(await server.localHealthVerificationCount == 3)
    #expect(await route.inspectionCount == 3)
    #expect(await route.endpointVerificationCount == 3)
}

@Test("Available publishes sanitized health for OpenCode, Tailscale, Endpoint, and keep-awake")
@MainActor
func availablePublishesFourSanitizedComponentStatuses() async {
    let coordinator = recoveryCoordinator(route: RecoveryRoute(endpointFailures: 0), scheduler: RecoveryScheduler())

    await coordinator.handle(.start)

    #expect(coordinator.viewModel.components.map(\.name) == ["OpenCode", "Tailscale", "Endpoint", "Keep Awake"])
    #expect(coordinator.viewModel.components.allSatisfy { !$0.detail.contains("Authorization") })
    #expect(coordinator.viewModel.components.allSatisfy { !$0.detail.contains("secret") })
}

@Test("notifications are limited to user-initiated Start or recovery settling in Error or Conflict")
@MainActor
func notificationsAreLimitedToUserRelevantFailures() async {
    let userNotifications = RecoveryNotifier()
    let userCoordinator = AccessCoordinator(
        dependencies: RecoveryDependencies(),
        credentialStore: RecoveryCredentialStore(),
        passphraseGenerator: RecoveryPassphraseGenerator(),
        server: RecoveryServer(),
        route: RecoveryRoute(endpointFailures: .max),
        retryPolicy: RetryPolicy(maximumAttempts: 1, delays: []),
        notifier: userNotifications
    )
    await userCoordinator.handle(.start)

    let routineNotifications = RecoveryNotifier()
    let routineCoordinator = AccessCoordinator(
        dependencies: RecoveryDependencies(),
        initialDesiredState: .enabled,
        credentialStore: RecoveryCredentialStore(),
        passphraseGenerator: RecoveryPassphraseGenerator(),
        server: RecoveryServer(),
        route: RecoveryRoute(
            endpointFailures: .max,
            endpointFailureMessage: "Authorization: Basic secret; endpoint timed out"
        ),
        retryPolicy: RetryPolicy(maximumAttempts: 1, delays: []),
        notifier: routineNotifications
    )
    await routineCoordinator.handle(.reconcile)

    #expect(await userNotifications.states == [.error])
    #expect(await routineNotifications.states.isEmpty)
}

@Test("Copy Diagnostics requires review and includes sanitized failure context")
@MainActor
func diagnosticsRequireReviewBeforeCopying() async {
    let diagnostics = LocalDiagnostics(capacity: 10)
    await diagnostics.recordCommandOutput(
        "Authorization: Basic secret\nuseful endpoint timeout",
        sensitiveValues: ["secret"]
    )
    let clipboard = RecoveryClipboard()
    let coordinator = AccessCoordinator(
        dependencies: RecoveryDependencies(),
        clipboard: clipboard,
        credentialStore: RecoveryCredentialStore(),
        passphraseGenerator: RecoveryPassphraseGenerator(),
        server: RecoveryServer(),
        route: RecoveryRoute(
            endpointFailures: .max,
            endpointFailureMessage: "Authorization: Basic secret; endpoint timed out"
        ),
        retryPolicy: RetryPolicy(maximumAttempts: 1, delays: []),
        diagnostics: diagnostics,
        diagnosticsMetadata: DiagnosticsMetadata(appVersion: "1.0", osVersion: "macOS Test")
    )
    await coordinator.handle(.start)
    #expect(!coordinator.viewModel.explanation.contains("secret"))
    #expect(!coordinator.viewModel.explanation.contains("Authorization"))
    await coordinator.handle(.copyDiagnostics)
    #expect(await clipboard.values.isEmpty)

    await coordinator.handle(.reviewDiagnostics)

    let review = coordinator.viewModel.diagnosticsReview
    #expect(review?.warning.contains("local paths may be sensitive") == true)
    #expect(review?.text.contains("App: 1.0") == true)
    #expect(review?.text.contains("OS: macOS Test") == true)
    #expect(review?.text.contains("OpenCode: 1.2.3 (/test/opencode)") == true)
    #expect(review?.text.contains("Tailscale: 1.82.0 (/test/tailscale)") == true)
    #expect(review?.text.contains("Desired State: Enabled") == true)
    #expect(review?.text.contains("Observed State: Error") == true)
    #expect(review?.text.contains("Failure Stage: endpointVerification") == true)
    #expect(review?.text.contains("Route Target: https:443 -> http://127.0.0.1:4096") == true)
    #expect(review?.text.contains("useful endpoint timeout") == true)
    #expect(review?.text.contains("Authorization: Basic secret") == false)

    await coordinator.handle(.copyDiagnostics)
    #expect(await clipboard.values == [review!.text])
}

@MainActor
private func recoveryCoordinator(
    route: RecoveryRoute,
    scheduler: RecoveryScheduler
) -> AccessCoordinator {
    AccessCoordinator(
        dependencies: RecoveryDependencies(),
        credentialStore: RecoveryCredentialStore(),
        passphraseGenerator: RecoveryPassphraseGenerator(),
        server: RecoveryServer(),
        route: route,
        retryScheduler: scheduler,
        retryPolicy: RetryPolicy(maximumAttempts: 3, delays: [.seconds(1), .seconds(2)])
    )
}

private struct RecoveryDependencies: DependencyReadinessChecking {
    func evaluate(settings: DependencySettings) async -> ReadinessEvaluation {
        ReadinessEvaluation(
            openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
            tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
        )
    }
}

private struct RecoveryCredentialStore: AccessCredentialStoring {
    func load() async throws -> String? { "secret" }
    func save(_ credential: String) async throws {}
    func delete() async throws {}
}

private struct RecoveryPassphraseGenerator: PassphraseGenerating {
    func generate() throws -> String { "unused" }
}

private actor RecoveryScheduler: RetryScheduling {
    private(set) var sleeps: [Duration] = []
    func sleep(for duration: Duration) async { sleeps.append(duration) }
}

private actor ControlledRecoveryScheduler: RetryScheduling {
    private var sleepContinuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func sleep(for duration: Duration) async {
        waiter?.resume()
        waiter = nil
        await withCheckedContinuation { sleepContinuation = $0 }
    }

    func waitUntilSleeping() async {
        if sleepContinuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        sleepContinuation?.resume()
        sleepContinuation = nil
    }
}

private actor RecoveryServer: ManagedServerControlling {
    private(set) var localHealthVerificationCount = 0
    func launch(_ configuration: ManagedServerConfiguration) async throws -> Bool { false }
    func runtimeRecord() async throws -> ManagedServerRecord? { nil }
    func inspect(
        record: ManagedServerRecord?,
        expectedConfiguration: ManagedServerConfiguration,
        authentication: AccessAuthentication
    ) async -> ManagedServerInspection { .verified(recoveryRecord) }
    func verifyLocalHealth(authentication: AccessAuthentication) async throws {
        localHealthVerificationCount += 1
    }
    func stopGracefully(timeout: Duration) async -> Bool { true }
    func ownershipIsVerified() async -> Bool { true }
    func forceStop() async {}
}

private actor RecoveryRoute: ManagedRouteControlling {
    private var remainingEndpointFailures: Int
    private let endpointFailureMessage: String
    private(set) var endpointVerificationCount = 0
    private(set) var inspectionCount = 0
    private(set) var removalCount = 0

    init(endpointFailures: Int, endpointFailureMessage: String = "temporarily unreachable") {
        remainingEndpointFailures = endpointFailures
        self.endpointFailureMessage = endpointFailureMessage
    }

    func setEndpointFailures(_ count: Int) { remainingEndpointFailures = count }
    func inspect(httpsPort: Int, backendPort: Int) async throws -> ManagedRouteInspection {
        inspectionCount += 1
        return .matching
    }
    func create(tailscalePath: String, httpsPort: Int, backendPort: Int) async throws {}
    func discoverEndpoint() async throws -> URL { URL(string: "https://test.tailnet.ts.net")! }
    func verifyEndpoint(_ endpoint: URL, authentication: AccessAuthentication) async throws {
        endpointVerificationCount += 1
        if remainingEndpointFailures > 0 {
            remainingEndpointFailures -= 1
            throw RecoveryError.temporarilyUnreachable(endpointFailureMessage)
        }
    }
    func removeIfMatching(httpsPort: Int, backendPort: Int) async throws { removalCount += 1 }
}

private actor RecoveryDesiredStateStore: DesiredStatePersisting {
    private(set) var saved: [DesiredState] = []
    nonisolated func load() -> DesiredState { .disabled }
    func save(_ desiredState: DesiredState) async { saved.append(desiredState) }
}

private actor RecoveryNotifier: UserNotifying {
    private(set) var states: [ObservedState] = []
    func notifyFailure(state: ObservedState, explanation: String) async { states.append(state) }
}

private actor RecoveryClipboard: ClipboardWriting {
    private(set) var values: [String] = []
    func write(_ value: String) async { values.append(value) }
}

private let recoveryRecord = ManagedServerRecord(
    processIdentifier: 4242,
    executablePath: "/test/opencode",
    backendPort: 4096,
    executableFingerprint: "fingerprint"
)

private enum RecoveryError: LocalizedError {
    case temporarilyUnreachable(String)
    var errorDescription: String? {
        switch self {
        case let .temporarilyUnreachable(message): message
        }
    }
}

import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("reconciliation adopts verified resources and creates only missing resources")
@MainActor
func reconciliationCreatesOnlyMissingResources() async {
    let record = reconciliationRecord
    let scenarios: [(ManagedServerRecord?, ManagedServerInspection, ManagedRouteInspection, [String])] = [
        (record, .verified(record), .matching, []),
        (record, .verified(record), .available, ["route.create"]),
        (nil, .missing, .matching, ["server.launch"]),
        (nil, .missing, .available, ["server.launch", "route.create"]),
    ]

    for (storedRecord, serverInspection, routeInspection, expectedCreations) in scenarios {
        let log = ReconciliationLog()
        let coordinator = AccessCoordinator(
            dependencies: ReconciliationDependencies(),
            initialDesiredState: .enabled,
            credentialStore: ReconciliationCredentialStore(),
            passphraseGenerator: ReconciliationPassphraseGenerator(),
            server: ReconciliationServer(log: log, inspection: serverInspection),
            route: ReconciliationRoute(log: log, inspection: routeInspection),
            runtimeRecordStore: ReconciliationRecordStore(record: storedRecord)
        )

        await coordinator.handle(.reconcile)

        #expect(coordinator.viewModel.observedState == .available)
        let creations = await log.entries.filter { $0 == "server.launch" || $0 == "route.create" }
        #expect(creations == expectedCreations)
    }
}

@Test("ambiguous server or route evidence publishes Conflict and blocks mutation")
@MainActor
func ambiguousEvidenceBlocksMutation() async {
    let conflicts = [
        "The recorded PID is no longer running.",
        "PID 4242 now belongs to a different executable.",
        "The recorded executable changed on disk.",
        "Backend port 4096 is occupied without a verifiable runtime record.",
    ]

    for evidence in conflicts {
        let log = ReconciliationLog()
        let coordinator = reconciliationCoordinator(
            log: log,
            storedRecord: reconciliationRecord,
            serverInspection: .conflict(evidence),
            routeInspection: .available
        )

        await coordinator.handle(.reconcile)
        await coordinator.handle(.stop)

        #expect(coordinator.viewModel.observedState == .conflict)
        #expect(coordinator.viewModel.explanation == evidence)
        #expect(coordinator.viewModel.primaryAction == .retryConflict)
        #expect(await log.entries.isEmpty)
    }

    let routeLog = ReconciliationLog()
    let routeCoordinator = reconciliationCoordinator(
        log: routeLog,
        storedRecord: reconciliationRecord,
        serverInspection: .verified(reconciliationRecord),
        routeInspection: .occupied
    )

    await routeCoordinator.handle(.reconcile)
    await routeCoordinator.handle(.stop)

    #expect(routeCoordinator.viewModel.observedState == .conflict)
    #expect(routeCoordinator.viewModel.explanation.contains("Tailscale"))
    #expect(routeCoordinator.viewModel.explanation.contains("different target"))
    #expect(routeCoordinator.viewModel.primaryAction == .retryConflict)
    #expect(await routeLog.entries.isEmpty)
}

@Test("Retry Inspection resolves Conflict only after external evidence becomes safe")
@MainActor
func retryInspectionResolvesConflictWithoutForcingResources() async {
    let log = ReconciliationLog()
    let server = ReconciliationServer(
        log: log,
        inspection: .conflict("Backend port 4096 is occupied without a verifiable runtime record.")
    )
    let coordinator = AccessCoordinator(
        dependencies: ReconciliationDependencies(),
        initialDesiredState: .enabled,
        credentialStore: ReconciliationCredentialStore(),
        passphraseGenerator: ReconciliationPassphraseGenerator(),
        server: server,
        route: ReconciliationRoute(log: log, inspection: .matching),
        runtimeRecordStore: ReconciliationRecordStore(record: nil)
    )

    await coordinator.handle(.reconcile)
    #expect(coordinator.viewModel.observedState == .conflict)
    #expect(await log.entries.isEmpty)

    await server.setInspection(.missing)
    await coordinator.handle(.retryConflict)

    #expect(coordinator.viewModel.observedState == .available)
    #expect(await log.entries == ["server.launch"])
}

@Test("Start persists Enabled intent and Stop persists Disabled intent")
@MainActor
func lifecyclePersistsDesiredState() async {
    let log = ReconciliationLog()
    let desiredStates = ReconciliationDesiredStateStore(initial: .disabled)
    let coordinator = AccessCoordinator(
        dependencies: ReconciliationDependencies(),
        credentialStore: ReconciliationCredentialStore(),
        passphraseGenerator: ReconciliationPassphraseGenerator(),
        server: ReconciliationServer(log: log, inspection: .missing),
        route: ReconciliationRoute(log: log, inspection: .available),
        runtimeRecordStore: ReconciliationRecordStore(record: nil),
        desiredStateStore: desiredStates
    )

    await coordinator.handle(.start)
    await coordinator.handle(.stop)

    #expect(await desiredStates.saved == [.enabled, .disabled])
}

@Test("Stop cleans up only while both Managed Route and Managed Server identity remain verified")
@MainActor
func stopRequiresVerifiedCleanupEvidence() async {
    let routeLog = ReconciliationLog()
    let changedRoute = ReconciliationRoute(log: routeLog, inspection: .matching)
    let routeCoordinator = AccessCoordinator(
        dependencies: ReconciliationDependencies(),
        initialDesiredState: .enabled,
        credentialStore: ReconciliationCredentialStore(),
        passphraseGenerator: ReconciliationPassphraseGenerator(),
        server: ReconciliationServer(log: routeLog, inspection: .verified(reconciliationRecord)),
        route: changedRoute,
        runtimeRecordStore: ReconciliationRecordStore(record: reconciliationRecord)
    )
    await routeCoordinator.handle(.reconcile)
    await routeLog.removeAll()
    await changedRoute.setInspection(.occupied)

    await routeCoordinator.handle(.stop)

    #expect(routeCoordinator.viewModel.observedState == .conflict)
    #expect(await routeLog.entries == [])

    let serverLog = ReconciliationLog()
    let changedServer = ReconciliationServer(
        log: serverLog,
        inspection: .verified(reconciliationRecord),
        ownershipVerified: false
    )
    let serverCoordinator = AccessCoordinator(
        dependencies: ReconciliationDependencies(),
        initialDesiredState: .enabled,
        credentialStore: ReconciliationCredentialStore(),
        passphraseGenerator: ReconciliationPassphraseGenerator(),
        server: changedServer,
        route: ReconciliationRoute(log: serverLog, inspection: .matching),
        runtimeRecordStore: ReconciliationRecordStore(record: reconciliationRecord)
    )
    await serverCoordinator.handle(.reconcile)
    await serverLog.removeAll()

    await serverCoordinator.handle(.stop)

    #expect(serverCoordinator.viewModel.observedState == .conflict)
    #expect(await serverLog.entries == [])
}

@Test("Retry Inspection preserves Disabled intent after a Stop conflict")
@MainActor
func retryInspectionRetriesCleanupWhenDisabled() async {
    let log = ReconciliationLog()
    let route = ReconciliationRoute(log: log, inspection: .matching)
    let coordinator = AccessCoordinator(
        dependencies: ReconciliationDependencies(),
        initialDesiredState: .enabled,
        credentialStore: ReconciliationCredentialStore(),
        passphraseGenerator: ReconciliationPassphraseGenerator(),
        server: ReconciliationServer(log: log, inspection: .verified(reconciliationRecord)),
        route: route,
        runtimeRecordStore: ReconciliationRecordStore(record: reconciliationRecord)
    )
    await coordinator.handle(.reconcile)
    await log.removeAll()
    await route.setInspection(.occupied)
    await coordinator.handle(.stop)

    #expect(coordinator.viewModel.desiredState == .disabled)
    #expect(coordinator.viewModel.observedState == .conflict)

    await route.setInspection(.matching)
    await coordinator.handle(.retryConflict)

    #expect(coordinator.viewModel.desiredState == .disabled)
    #expect(coordinator.viewModel.observedState == .stopped)
    #expect(await log.entries == ["route.remove", "server.stop"])
}

@MainActor
private func reconciliationCoordinator(
    log: ReconciliationLog,
    storedRecord: ManagedServerRecord?,
    serverInspection: ManagedServerInspection,
    routeInspection: ManagedRouteInspection
) -> AccessCoordinator {
    AccessCoordinator(
        dependencies: ReconciliationDependencies(),
        initialDesiredState: .enabled,
        credentialStore: ReconciliationCredentialStore(),
        passphraseGenerator: ReconciliationPassphraseGenerator(),
        server: ReconciliationServer(log: log, inspection: serverInspection),
        route: ReconciliationRoute(log: log, inspection: routeInspection),
        runtimeRecordStore: ReconciliationRecordStore(record: storedRecord)
    )
}

private let reconciliationRecord = ManagedServerRecord(
    processIdentifier: 4242,
    executablePath: "/test/opencode",
    backendPort: 4096,
    executableFingerprint: "fingerprint"
)

private struct ReconciliationDependencies: DependencyReadinessChecking {
    func evaluate(settings: DependencySettings) async -> ReadinessEvaluation {
        ReadinessEvaluation(
            openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
            tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
        )
    }
}

private struct ReconciliationCredentialStore: AccessCredentialStoring {
    func load() async throws -> String? { "secret" }
    func save(_ credential: String) async throws {}
    func delete() async throws {}
}

private struct ReconciliationPassphraseGenerator: PassphraseGenerating {
    func generate() throws -> String { "unused" }
}

private actor ReconciliationLog {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
    func removeAll() { entries.removeAll() }
}

private actor ReconciliationRecordStore: ManagedServerRecordStoring {
    private var record: ManagedServerRecord?
    init(record: ManagedServerRecord?) { self.record = record }
    func load() async throws -> ManagedServerRecord? { record }
    func save(_ record: ManagedServerRecord) async throws { self.record = record }
    func clear() async throws { record = nil }
}

private actor ReconciliationDesiredStateStore: DesiredStatePersisting {
    private(set) var saved: [DesiredState] = []
    let initial: DesiredState
    init(initial: DesiredState) { self.initial = initial }
    nonisolated func load() -> DesiredState { initial }
    func save(_ desiredState: DesiredState) async { saved.append(desiredState) }
}

private actor ReconciliationServer: ManagedServerControlling {
    let log: ReconciliationLog
    private var inspection: ManagedServerInspection
    let ownershipVerified: Bool
    init(
        log: ReconciliationLog,
        inspection: ManagedServerInspection,
        ownershipVerified: Bool = true
    ) {
        self.log = log
        self.inspection = inspection
        self.ownershipVerified = ownershipVerified
    }
    func setInspection(_ inspection: ManagedServerInspection) { self.inspection = inspection }
    func inspect(
        record: ManagedServerRecord?,
        expectedConfiguration: ManagedServerConfiguration,
        authentication: AccessAuthentication
    ) async -> ManagedServerInspection { inspection }
    func launch(_ configuration: ManagedServerConfiguration) async throws -> Bool {
        await log.append("server.launch")
        return true
    }
    func runtimeRecord() async throws -> ManagedServerRecord? { reconciliationRecord }
    func verifyLocalHealth(authentication: AccessAuthentication) async throws {}
    func stopGracefully(timeout: Duration) async -> Bool {
        await log.append("server.stop")
        return true
    }
    func ownershipIsVerified() async -> Bool { ownershipVerified }
    func forceStop() async {}
}

private actor ReconciliationRoute: ManagedRouteControlling {
    let log: ReconciliationLog
    private var inspection: ManagedRouteInspection
    init(log: ReconciliationLog, inspection: ManagedRouteInspection) {
        self.log = log
        self.inspection = inspection
    }
    func setInspection(_ inspection: ManagedRouteInspection) { self.inspection = inspection }
    func inspect(httpsPort: Int, backendPort: Int) async throws -> ManagedRouteInspection { inspection }
    func create(tailscalePath: String, httpsPort: Int, backendPort: Int) async throws {
        await log.append("route.create")
    }
    func discoverEndpoint(httpsPort: Int) async throws -> URL { URL(string: "https://test.tailnet.ts.net")! }
    func verifyEndpoint(_ endpoint: URL, authentication: AccessAuthentication) async throws {}
    func removeIfMatching(httpsPort: Int, backendPort: Int) async throws {
        await log.append("route.remove")
    }
}

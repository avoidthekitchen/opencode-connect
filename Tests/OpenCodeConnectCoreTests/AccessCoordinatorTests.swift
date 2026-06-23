import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("valid dependencies with disabled intent are stopped")
@MainActor
func validDependenciesAreStopped() async {
    let dependencies = DeterministicDependencyReadiness(
        openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
        tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
    )
    let coordinator = AccessCoordinator(dependencies: dependencies)

    await coordinator.handle(.evaluateReadiness)

    #expect(coordinator.viewModel.observedState == .stopped)
    #expect(coordinator.viewModel.primaryAction == .start)
    #expect(coordinator.viewModel.components == [
        ComponentReadiness(name: "OpenCode", status: .ready, detail: "1.2.3"),
        ComponentReadiness(name: "Tailscale", status: .ready, detail: "1.82.0"),
    ])
}

@Test("missing OpenCode explains how to install it")
@MainActor
func missingOpenCodeNeedsSetup() async {
    let dependencies = DeterministicDependencyReadiness(
        openCode: .missing,
        tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
    )
    let coordinator = AccessCoordinator(dependencies: dependencies)

    await coordinator.handle(.evaluateReadiness)

    #expect(coordinator.viewModel.observedState == .needsSetup)
    #expect(coordinator.viewModel.explanation.contains("OpenCode was not found"))
    #expect(coordinator.viewModel.primaryAction == .retryReadiness)
    #expect(coordinator.viewModel.components.first?.status == .needsSetup)
}

@Test("missing Tailscale explains Mac and iPhone prerequisites")
@MainActor
func missingTailscaleNeedsSetup() async {
    let dependencies = DeterministicDependencyReadiness(
        openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
        tailscale: .missing
    )
    let coordinator = AccessCoordinator(dependencies: dependencies)

    await coordinator.handle(.evaluateReadiness)

    #expect(coordinator.viewModel.observedState == .needsSetup)
    #expect(coordinator.viewModel.explanation.contains("Tailscale was not found"))
    #expect(coordinator.viewModel.explanation.contains("iPhone"))
    #expect(coordinator.viewModel.primaryAction == .retryReadiness)
}

@Test("an invalid custom OpenCode executable has specific remediation")
@MainActor
func invalidCustomOpenCodePathNeedsSetup() async {
    let dependencies = DeterministicDependencyReadiness(
        openCode: .invalidCustomPath(path: "/chosen/opencode", reason: "File is not executable"),
        tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
    )
    let coordinator = AccessCoordinator(dependencies: dependencies)

    await coordinator.handle(.selectCustomOpenCodePath("/chosen/opencode"))

    #expect(coordinator.viewModel.observedState == .needsSetup)
    #expect(coordinator.viewModel.explanation.contains("/chosen/opencode"))
    #expect(coordinator.viewModel.explanation.contains("not executable"))
    #expect(coordinator.viewModel.primaryAction == .retryReadiness)
}

@Test("disconnected Tailscale is distinct from a missing executable")
@MainActor
func disconnectedTailscaleNeedsSetup() async {
    let dependencies = DeterministicDependencyReadiness(
        openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
        tailscale: .disconnected
    )
    let coordinator = AccessCoordinator(dependencies: dependencies)

    await coordinator.handle(.evaluateReadiness)

    #expect(coordinator.viewModel.observedState == .needsSetup)
    #expect(coordinator.viewModel.explanation.contains("installed but disconnected"))
    #expect(coordinator.viewModel.explanation.contains("iPhone"))
}

@Test("signed-out Tailscale requests sign-in")
@MainActor
func signedOutTailscaleNeedsSetup() async {
    let dependencies = DeterministicDependencyReadiness(
        openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
        tailscale: .signedOut
    )
    let coordinator = AccessCoordinator(dependencies: dependencies)

    await coordinator.handle(.evaluateReadiness)

    #expect(coordinator.viewModel.explanation.contains("signed out"))
    #expect(coordinator.viewModel.explanation.contains("Sign in"))
}

@Test("Tailscale approval opens only after the explicit setup action")
@MainActor
func approvalRequiresExplicitAction() async {
    let approvalURL = URL(string: "https://login.tailscale.com/admin/machines")!
    let dependencies = DeterministicDependencyReadiness(
        openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
        tailscale: .serveApprovalRequired(approvalURL)
    )
    let opener = RecordingURLOpener()
    let coordinator = AccessCoordinator(dependencies: dependencies, urlOpener: opener)

    await coordinator.handle(.evaluateReadiness)

    #expect(coordinator.viewModel.primaryAction == .completeTailscaleSetup(approvalURL))
    #expect(await opener.openedURLs.isEmpty)

    await coordinator.handle(.completeTailscaleSetup)

    #expect(await opener.openedURLs == [approvalURL])
}

@Test("an invalid custom Tailscale executable has specific remediation")
@MainActor
func invalidCustomTailscalePathNeedsSetup() async {
    let dependencies = DeterministicDependencyReadiness(
        openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
        tailscale: .invalidCustomPath(path: "/chosen/tailscale", reason: "File does not exist")
    )
    let coordinator = AccessCoordinator(dependencies: dependencies)

    await coordinator.handle(.selectCustomTailscalePath("/chosen/tailscale"))

    #expect(coordinator.viewModel.explanation.contains("custom Tailscale path"))
    #expect(coordinator.viewModel.explanation.contains("does not exist"))
}

private struct DeterministicDependencyReadiness: DependencyReadinessChecking {
    let openCode: DependencyReadiness
    let tailscale: DependencyReadiness

    func evaluate(settings: DependencySettings) async -> ReadinessEvaluation {
        ReadinessEvaluation(openCode: openCode, tailscale: tailscale)
    }
}

private struct RejectingCustomPathReadiness: DependencyReadinessChecking {
    func evaluate(settings: DependencySettings) async -> ReadinessEvaluation {
        ReadinessEvaluation(
            openCode: settings.customOpenCodePath.map {
                .invalidCustomPath(path: $0, reason: "File is not executable")
            } ?? .ready(version: "1.2.3", executablePath: "/test/opencode"),
            tailscale: settings.customTailscalePath.map {
                .invalidCustomPath(path: $0, reason: "File is not executable")
            } ?? .ready(version: "1.82.0", executablePath: "/test/tailscale")
        )
    }
}

private actor RecordingURLOpener: ExternalURLOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) async {
        openedURLs.append(url)
    }
}

@Test("Start reaches Available only after authenticated local and Endpoint verification")
@MainActor
func startReachesAvailableThroughProtectedPath() async {
    let operations = OperationLog()
    let credentialStore = DeterministicCredentialStore(existing: nil, operations: operations)
    let server = DeterministicServer(operations: operations)
    let route = DeterministicRoute(operations: operations)
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        credentialStore: credentialStore,
        passphraseGenerator: FixedPassphraseGenerator("alpha bravo charlie delta echo foxtrot"),
        server: server,
        route: route,
        homeDirectory: URL(fileURLWithPath: "/Users/test")
    )

    await coordinator.handle(.start)

    #expect(coordinator.viewModel.desiredState == .enabled)
    #expect(coordinator.viewModel.observedState == .available)
    #expect(coordinator.viewModel.endpoint == URL(string: "https://test.tailnet.ts.net"))
    #expect(await server.launchConfiguration == ManagedServerConfiguration(
        executablePath: "/test/opencode",
        arguments: ["serve", "--hostname", "127.0.0.1", "--port", "4096"],
        environment: [
            "OPENCODE_SERVER_USERNAME": "opencode",
            "OPENCODE_SERVER_PASSWORD": "alpha bravo charlie delta echo foxtrot",
        ],
        workingDirectory: URL(fileURLWithPath: "/Users/test")
    ))
    #expect(await operations.entries == [
        "credential.load", "credential.save", "route.inspect", "server.launch",
        "server.verifyLocal", "route.create", "route.discoverEndpoint", "route.verifyEndpoint",
    ])
}

@Test("Stop waits for an in-flight reconciliation and remains the final intent")
@MainActor
func stopSerializesBehindInFlightStart() async {
    let dependencies = BlockingDependencyReadiness()
    let operations = OperationLog()
    let coordinator = AccessCoordinator(
        dependencies: dependencies,
        credentialStore: DeterministicCredentialStore(existing: "secret", operations: operations),
        passphraseGenerator: FixedPassphraseGenerator("unused"),
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(operations: operations)
    )

    let start = Task { await coordinator.handle(.start) }
    await dependencies.waitUntilEvaluating()
    let stop = Task { await coordinator.handle(.stop) }
    await Task.yield()
    await dependencies.resume()
    await start.value
    await stop.value

    #expect(coordinator.viewModel.desiredState == .disabled)
    #expect(coordinator.viewModel.observedState == .stopped)
    #expect(await operations.entries.suffix(4) == [
        "route.inspect", "server.ownership", "route.remove", "server.stopGracefully",
    ])
}

@Test("Tailnet-Only Access reaches Available without Basic Auth and remains loopback-only")
@MainActor
func tailnetOnlyStartsWithoutBasicAuth() async {
    let operations = OperationLog()
    let credentialStore = DeterministicCredentialStore(existing: "preserved credential", operations: operations)
    let server = DeterministicServer(operations: operations)
    let route = DeterministicRoute(operations: operations)
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        settings: DependencySettings(accessMode: .tailnetOnly),
        credentialStore: credentialStore,
        passphraseGenerator: FixedPassphraseGenerator("must not be used"),
        server: server,
        route: route,
        homeDirectory: URL(fileURLWithPath: "/Users/test")
    )

    await coordinator.handle(.start)

    #expect(coordinator.viewModel.observedState == .available)
    #expect(await server.launchConfiguration?.arguments == [
        "serve", "--hostname", "127.0.0.1", "--port", "4096",
    ])
    #expect(await server.launchConfiguration?.environment == [:])
    #expect(!(await operations.entries.contains("credential.load")))
    #expect(await route.verifiedAuthentication == AccessAuthentication.none)
}

@Test("Tailnet-Only Access does not depend on credential infrastructure")
@MainActor
func tailnetOnlyDoesNotRequireCredentialAdapters() async {
    let operations = OperationLog()
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        settings: DependencySettings(accessMode: .tailnetOnly),
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(operations: operations)
    )

    await coordinator.handle(.start)

    #expect(coordinator.viewModel.observedState == .available)
}

@Test("Tailnet-Only Access requires explicit reduced-defense confirmation and preserves the credential")
@MainActor
func tailnetOnlyRequiresConfirmation() async {
    let operations = OperationLog()
    let settingsStore = RecordingSettingsStore()
    let credentialStore = DeterministicCredentialStore(existing: "keep me", operations: operations)
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        settingsStore: settingsStore,
        credentialStore: credentialStore
    )

    await coordinator.handle(.requestAccessMode(.tailnetOnly))

    #expect(coordinator.settingsViewModel.accessMode == .protected)
    #expect(coordinator.settingsViewModel.tailnetOnlyWarningPending)
    #expect(await settingsStore.saved.isEmpty)

    await coordinator.handle(.confirmTailnetOnlyAccess)

    #expect(coordinator.settingsViewModel.accessMode == .tailnetOnly)
    #expect(!coordinator.settingsViewModel.tailnetOnlyWarningPending)
    #expect(await settingsStore.saved.last?.accessMode == .tailnetOnly)
    #expect(await credentialStore.storedCredential == "keep me")
}

@Test("Disabled users can configure backend and Serve HTTPS ports used by the next session")
@MainActor
func disabledUsersCanConfigurePorts() async {
    let operations = OperationLog()
    let settingsStore = RecordingSettingsStore()
    let server = DeterministicServer(operations: operations)
    let route = DeterministicRoute(operations: operations)
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        settingsStore: settingsStore,
        credentialStore: DeterministicCredentialStore(existing: "secret", operations: operations),
        passphraseGenerator: FixedPassphraseGenerator("unused"),
        server: server,
        route: route
    )

    await coordinator.handle(.updatePorts(backend: 5000, https: 8443))
    await coordinator.handle(.start)

    #expect(coordinator.settingsViewModel.backendPort == 5000)
    #expect(coordinator.settingsViewModel.httpsPort == 8443)
    #expect(await settingsStore.saved.last?.backendPort == 5000)
    #expect(await server.launchConfiguration?.arguments == [
        "serve", "--hostname", "127.0.0.1", "--port", "5000",
    ])
    #expect(await route.inspectionPorts == PortPair(https: 8443, backend: 5000))
    #expect(await route.creationPorts == PortPair(https: 8443, backend: 5000))
}

@Test("Enabled intent blocks every operational settings mutation")
@MainActor
func enabledIntentBlocksOperationalSettings() async {
    let operations = OperationLog()
    let settingsStore = RecordingSettingsStore()
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        settingsStore: settingsStore,
        credentialStore: DeterministicCredentialStore(existing: "secret", operations: operations),
        passphraseGenerator: FixedPassphraseGenerator("unused"),
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(operations: operations)
    )
    await coordinator.handle(.start)

    await coordinator.handle(.updatePorts(backend: 5000, https: 8443))
    await coordinator.handle(.updateUsername("changed"))
    await coordinator.handle(.requestAccessMode(.tailnetOnly))
    await coordinator.handle(.selectCustomOpenCodePath("/changed/opencode"))
    await coordinator.handle(.selectCustomTailscalePath("/changed/tailscale"))

    #expect(coordinator.settingsViewModel.backendPort == 4096)
    #expect(coordinator.settingsViewModel.httpsPort == 443)
    #expect(coordinator.settingsViewModel.accessUsername == "opencode")
    #expect(coordinator.settingsViewModel.accessMode == .protected)
    #expect(!coordinator.settingsViewModel.tailnetOnlyWarningPending)
    #expect(await settingsStore.saved.isEmpty)
}

@Test("Invalid usernames, ports, and executable selections are rejected before persistence")
@MainActor
func invalidOperationalSettingsAreNotSaved() async {
    let settingsStore = RecordingSettingsStore()
    let coordinator = AccessCoordinator(
        dependencies: RejectingCustomPathReadiness(),
        settingsStore: settingsStore
    )

    await coordinator.handle(.updateUsername("   "))
    #expect(coordinator.settingsViewModel.message?.contains("username") == true)

    await coordinator.handle(.updatePorts(backend: 0, https: 70_000))
    #expect(coordinator.settingsViewModel.message?.contains("ports") == true)

    await coordinator.handle(.selectCustomOpenCodePath("/invalid/opencode"))
    await coordinator.handle(.selectCustomTailscalePath("/invalid/tailscale"))

    #expect(await settingsStore.saved.isEmpty)
    #expect(coordinator.settingsViewModel.accessUsername == "opencode")
    #expect(coordinator.settingsViewModel.backendPort == 4096)
    #expect(coordinator.settingsViewModel.httpsPort == 443)
}

@Test("Port validation rejects privileged backend ports and overlapping backend and HTTPS ports")
@MainActor
func unsafePortSelectionsAreRejectedBeforePersistence() async {
    let settingsStore = RecordingSettingsStore()
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        settingsStore: settingsStore
    )

    await coordinator.handle(.updatePorts(backend: 80, https: 8443))
    #expect(coordinator.settingsViewModel.message?.contains("backend port must be 1024 or higher") == true)

    await coordinator.handle(.updatePorts(backend: 4096, https: 4096))
    #expect(coordinator.settingsViewModel.message?.contains("must be different") == true)

    #expect(await settingsStore.saved.isEmpty)
    #expect(coordinator.settingsViewModel.backendPort == 4096)
    #expect(coordinator.settingsViewModel.httpsPort == 443)
}

@Test("Credential rotation warns the iPhone user, deletion is explicit, and Protected Access repairs absence")
@MainActor
func credentialLifecycleIsExplicitAndRepairable() async {
    let operations = OperationLog()
    let credentialStore = DeterministicCredentialStore(existing: "old credential", operations: operations)
    let replacement = "alpha bravo charlie delta echo foxtrot"
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        credentialStore: credentialStore,
        passphraseGenerator: FixedPassphraseGenerator(replacement),
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(operations: operations)
    )

    await coordinator.handle(.rotateCredential)

    #expect(await credentialStore.storedCredential == replacement)
    #expect(coordinator.settingsViewModel.message?.contains("iPhone") == true)

    await coordinator.handle(.deleteCredential)
    #expect(await credentialStore.storedCredential == nil)
    #expect(coordinator.settingsViewModel.message?.contains("deleted") == true)

    await coordinator.handle(.start)
    #expect(await credentialStore.storedCredential == replacement)
    #expect(await operations.entries.filter { $0 == "credential.save" }.count == 2)
}

@Test("Reset to Defaults restores operational defaults without deleting the credential or touching live resources")
@MainActor
func resetToDefaultsPreservesCredentialAndResources() async {
    let operations = OperationLog()
    let settingsStore = RecordingSettingsStore()
    let credentialStore = DeterministicCredentialStore(existing: "keep me", operations: operations)
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        settingsStore: settingsStore,
        credentialStore: credentialStore,
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(operations: operations)
    )
    await coordinator.handle(.selectCustomOpenCodePath("/custom/opencode"))
    await coordinator.handle(.selectCustomTailscalePath("/custom/tailscale"))
    await coordinator.handle(.updateUsername("custom-user"))
    await coordinator.handle(.updatePorts(backend: 5000, https: 8443))
    await coordinator.handle(.updateAvailabilityPolicy(.always))
    await coordinator.handle(.requestAccessMode(.tailnetOnly))
    await coordinator.handle(.confirmTailnetOnlyAccess)
    await operations.removeAll()

    await coordinator.handle(.resetToDefaults)

    #expect(await settingsStore.saved.last == DependencySettings())
    #expect(coordinator.settingsViewModel == SettingsViewModel(
        accessMode: .protected,
        accessUsername: "opencode",
        backendPort: 4096,
        httpsPort: 443,
        availabilityPolicy: .onExternalPower,
        message: "Settings were reset to defaults."
    ))
    #expect(await credentialStore.storedCredential == "keep me")
    #expect(await operations.entries.isEmpty)
}

@Test("readiness reevaluation preserves an Available protected session")
@MainActor
func readinessReevaluationPreservesAvailableSession() async {
    let operations = OperationLog()
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        credentialStore: DeterministicCredentialStore(existing: "stored credential", operations: operations),
        passphraseGenerator: FixedPassphraseGenerator("replacement must not be used"),
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(operations: operations),
        homeDirectory: URL(fileURLWithPath: "/Users/test")
    )

    await coordinator.handle(.start)
    await coordinator.handle(.evaluateReadiness)

    #expect(coordinator.viewModel.desiredState == .enabled)
    #expect(coordinator.viewModel.observedState == .available)
    #expect(coordinator.viewModel.endpoint == URL(string: "https://test.tailnet.ts.net"))
    #expect(coordinator.viewModel.primaryAction == .stop)
}

@Test("later starts reuse the stored Access Credential")
@MainActor
func laterStartsReuseCredential() async {
    let operations = OperationLog()
    let store = DeterministicCredentialStore(existing: "stored credential", operations: operations)
    let server = DeterministicServer(operations: operations)
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        credentialStore: store,
        passphraseGenerator: FixedPassphraseGenerator("replacement must not be used"),
        server: server,
        route: DeterministicRoute(operations: operations),
        homeDirectory: URL(fileURLWithPath: "/Users/test")
    )

    await coordinator.handle(.start)

    #expect(await server.launchConfiguration?.environment["OPENCODE_SERVER_PASSWORD"] == "stored credential")
    #expect(!(await operations.entries.contains("credential.save")))
}

@Test("launch persists only bounded non-secret Managed Server identity")
@MainActor
func launchPersistsBoundedRuntimeIdentity() async {
    let operations = OperationLog()
    let runtimeStore = DeterministicRuntimeRecordStore(operations: operations)
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        credentialStore: DeterministicCredentialStore(existing: "top secret", operations: operations),
        passphraseGenerator: FixedPassphraseGenerator("unused"),
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(operations: operations),
        runtimeRecordStore: runtimeStore
    )

    await coordinator.handle(.start)

    #expect(await runtimeStore.record == ManagedServerRecord(
        processIdentifier: 4242,
        executablePath: "/test/opencode",
        backendPort: 4096,
        executableFingerprint: "test-fingerprint"
    ))
    let encoded = try! JSONEncoder().encode(await runtimeStore.record)
    let persistedText = String(decoding: encoded, as: UTF8.self)
    #expect(!persistedText.contains("top secret"))
    #expect(!persistedText.contains("OPENCODE_SERVER_PASSWORD"))
    #expect(!persistedText.contains("Authorization"))
}

@Test("generated Access Credentials contain six readable words")
func generatedCredentialsAreSixWords() throws {
    let generator = SecureReadablePassphraseGenerator()

    let credentials = try (0..<20).map { _ in try generator.generate() }

    #expect(Set(credentials).count == credentials.count)
    #expect(credentials.allSatisfy { credential in
        let words = credential.split(separator: " ")
        return words.count == 6 && words.allSatisfy {
            $0.count >= 6 && $0.allSatisfy { $0.isLowercase && $0.isLetter }
        }
    })
}

@Test("Protected Access rejects an empty configured username")
@MainActor
func emptyUsernameIsRejected() async {
    let operations = OperationLog()
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        settings: DependencySettings(accessUsername: "   "),
        credentialStore: DeterministicCredentialStore(existing: "secret", operations: operations),
        passphraseGenerator: FixedPassphraseGenerator("unused"),
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(operations: operations)
    )

    await coordinator.handle(.start)

    #expect(coordinator.viewModel.observedState == .error)
    #expect(coordinator.viewModel.explanation.contains("username"))
    #expect(await operations.entries.isEmpty)
}

@Test("Stop closes the Managed Route before stopping the Managed Server")
@MainActor
func stopClosesRouteFirst() async {
    let operations = OperationLog()
    let server = DeterministicServer(operations: operations)
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        credentialStore: DeterministicCredentialStore(existing: "secret", operations: operations),
        passphraseGenerator: FixedPassphraseGenerator("unused"),
        server: server,
        route: DeterministicRoute(operations: operations)
    )
    await coordinator.handle(.start)
    await operations.removeAll()

    await coordinator.handle(.stop)

    #expect(coordinator.viewModel.desiredState == .disabled)
    #expect(coordinator.viewModel.observedState == .stopped)
    #expect(await operations.entries == [
        "route.inspect", "server.ownership", "route.remove", "server.stopGracefully",
    ])
    #expect(await server.gracefulTimeout == .seconds(5))
}

@Test("normal Quit uses the same route-first cleanup contract")
@MainActor
func quitClosesRouteFirst() async {
    let operations = OperationLog()
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        credentialStore: DeterministicCredentialStore(existing: "secret", operations: operations),
        passphraseGenerator: FixedPassphraseGenerator("unused"),
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(operations: operations)
    )
    await coordinator.handle(.start)
    await operations.removeAll()

    await coordinator.handle(.quit)

    #expect(await operations.entries == [
        "route.inspect", "server.ownership", "route.remove", "server.stopGracefully",
    ])
    #expect(coordinator.viewModel == AccessViewModel(
        desiredState: .disabled,
        observedState: .stopped,
        explanation: "OpenCode Connect is ready to start private access.",
        components: [
            ComponentReadiness(name: "OpenCode", status: .ready, detail: "1.2.3"),
            ComponentReadiness(name: "Tailscale", status: .ready, detail: "1.82.0"),
            ComponentReadiness(name: "Keep Awake", status: .ready, detail: "On external power"),
        ],
        primaryAction: .start
    ))
}

@Test("forced termination follows timeout only while ownership remains verified")
@MainActor
func forceStopRequiresVerifiedOwnership() async {
    let verifiedOperations = OperationLog()
    let verifiedServer = DeterministicServer(
        operations: verifiedOperations, gracefulResult: false, ownershipVerified: true
    )
    let verifiedCoordinator = AccessCoordinator(
        dependencies: readyDependencies, server: verifiedServer,
        route: DeterministicRoute(operations: verifiedOperations)
    )
    await verifiedCoordinator.handle(.stop)
    #expect(await verifiedOperations.entries == [
        "route.inspect", "server.ownership", "route.remove", "server.stopGracefully",
        "server.ownership", "server.forceStop",
    ])

    let unverifiedOperations = OperationLog()
    let unverifiedCoordinator = AccessCoordinator(
        dependencies: readyDependencies,
        server: DeterministicServer(
            operations: unverifiedOperations, gracefulResult: false, ownershipVerified: false
        ),
        route: DeterministicRoute(operations: unverifiedOperations)
    )
    await unverifiedCoordinator.handle(.stop)
    #expect(await unverifiedOperations.entries == ["route.inspect", "server.ownership"])
}

@Test("first-start failure rolls back only resources created by that attempt")
@MainActor
func startupFailureRollsBackCreatedResources() async {
    let scenarios: [(stage: String, expectedSuffix: [String])] = [
        ("credential.load", []),
        ("credential.save", []),
        ("server.launch", []),
        ("server.verifyLocal", ["server.stopGracefully"]),
        ("route.inspect", []),
        ("route.create", ["route.remove", "server.stopGracefully"]),
        ("route.discoverEndpoint", ["route.remove", "server.stopGracefully"]),
        ("route.verifyEndpoint", ["route.remove", "server.stopGracefully"]),
    ]

    for scenario in scenarios {
        let operations = OperationLog()
        let coordinator = AccessCoordinator(
            dependencies: readyDependencies,
            credentialStore: DeterministicCredentialStore(
                existing: scenario.stage == "credential.save" ? nil : "secret",
                operations: operations,
                failAt: scenario.stage
            ),
            passphraseGenerator: FixedPassphraseGenerator("alpha bravo charlie delta echo foxtrot"),
            server: DeterministicServer(operations: operations, failAt: scenario.stage),
            route: DeterministicRoute(operations: operations, failAt: scenario.stage),
            retryPolicy: RetryPolicy(maximumAttempts: 1, delays: [])
        )

        await coordinator.handle(.start)

        #expect(coordinator.viewModel.desiredState == .enabled)
        #expect(coordinator.viewModel.observedState == .error)
        let entries = await operations.entries
        let failedIndex = entries.firstIndex(of: scenario.stage)!
        #expect(Array(entries.suffix(from: entries.index(after: failedIndex))) == scenario.expectedSuffix)
    }
}

@Test("rollback preserves a pre-existing matching Managed Route")
@MainActor
func rollbackPreservesReusedRoute() async {
    let operations = OperationLog()
    let coordinator = AccessCoordinator(
        dependencies: readyDependencies,
        credentialStore: DeterministicCredentialStore(existing: "secret", operations: operations),
        passphraseGenerator: FixedPassphraseGenerator("unused"),
        server: DeterministicServer(operations: operations),
        route: DeterministicRoute(
            operations: operations, failAt: "route.verifyEndpoint", inspection: .matching
        ),
        retryPolicy: RetryPolicy(maximumAttempts: 1, delays: [])
    )

    await coordinator.handle(.start)

    #expect(coordinator.viewModel.observedState == .error)
    #expect(!(await operations.entries.contains("route.remove")))
    #expect(await operations.entries.last == "server.stopGracefully")
}

private struct InjectedFailure: Error {}

private let readyDependencies = DeterministicDependencyReadiness(
    openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
    tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
)

private actor OperationLog {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
    func removeAll() { entries.removeAll() }
}

private actor BlockingDependencyReadiness: DependencyReadinessChecking {
    private var evaluationContinuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func evaluate(settings: DependencySettings) async -> ReadinessEvaluation {
        waiter?.resume()
        waiter = nil
        await withCheckedContinuation { evaluationContinuation = $0 }
        return ReadinessEvaluation(
            openCode: .ready(version: "1.2.3", executablePath: "/test/opencode"),
            tailscale: .ready(version: "1.82.0", executablePath: "/test/tailscale")
        )
    }

    func waitUntilEvaluating() async {
        if evaluationContinuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        evaluationContinuation?.resume()
        evaluationContinuation = nil
    }
}

private actor DeterministicCredentialStore: AccessCredentialStoring {
    private var credential: String?
    let operations: OperationLog
    let failAt: String?
    init(existing: String?, operations: OperationLog, failAt: String? = nil) {
        credential = existing; self.operations = operations; self.failAt = failAt
    }
    func load() async throws -> String? {
        await operations.append("credential.load"); if failAt == "credential.load" { throw InjectedFailure() }; return credential
    }
    func save(_ credential: String) async throws {
        await operations.append("credential.save"); if failAt == "credential.save" { throw InjectedFailure() }; self.credential = credential
    }
    func delete() async throws {
        await operations.append("credential.delete")
        credential = nil
    }
    var storedCredential: String? { credential }
}

private actor RecordingSettingsStore: DependencySettingsPersisting {
    private(set) var saved: [DependencySettings] = []
    func save(_ settings: DependencySettings) async { saved.append(settings) }
}

private actor DeterministicRuntimeRecordStore: ManagedServerRecordStoring {
    private(set) var record: ManagedServerRecord?
    let operations: OperationLog

    init(record: ManagedServerRecord? = nil, operations: OperationLog) {
        self.record = record
        self.operations = operations
    }

    func load() async throws -> ManagedServerRecord? {
        await operations.append("runtime.load")
        return record
    }

    func save(_ record: ManagedServerRecord) async throws {
        await operations.append("runtime.save")
        self.record = record
    }

    func clear() async throws {
        await operations.append("runtime.clear")
        record = nil
    }
}

private struct FixedPassphraseGenerator: PassphraseGenerating {
    let value: String
    init(_ value: String) { self.value = value }
    func generate() throws -> String { value }
}

private actor DeterministicServer: ManagedServerControlling {
    let operations: OperationLog
    private(set) var launchConfiguration: ManagedServerConfiguration?
    private(set) var gracefulTimeout: Duration?
    let gracefulResult: Bool
    let ownershipVerified: Bool
    let failAt: String?
    init(
        operations: OperationLog,
        gracefulResult: Bool = true,
        ownershipVerified: Bool = true,
        failAt: String? = nil
    ) {
        self.operations = operations
        self.gracefulResult = gracefulResult
        self.ownershipVerified = ownershipVerified
        self.failAt = failAt
    }
    func launch(_ configuration: ManagedServerConfiguration) async throws -> Bool {
        launchConfiguration = configuration; await operations.append("server.launch")
        if failAt == "server.launch" { throw InjectedFailure() }; return true
    }
    func runtimeRecord() async throws -> ManagedServerRecord? {
        ManagedServerRecord(
            processIdentifier: 4242,
            executablePath: "/test/opencode",
            backendPort: 4096,
            executableFingerprint: "test-fingerprint"
        )
    }
    func verifyLocalHealth(authentication: AccessAuthentication) async throws {
        await operations.append("server.verifyLocal"); if failAt == "server.verifyLocal" { throw InjectedFailure() }
    }
    func stopGracefully(timeout: Duration) async -> Bool {
        gracefulTimeout = timeout; await operations.append("server.stopGracefully"); return gracefulResult
    }
    func ownershipIsVerified() async -> Bool {
        await operations.append("server.ownership"); return ownershipVerified
    }
    func forceStop() async { await operations.append("server.forceStop") }
}

private actor DeterministicRoute: ManagedRouteControlling {
    let operations: OperationLog
    let failAt: String?
    let inspection: ManagedRouteInspection
    let endpoint: URL
    private(set) var verifiedAuthentication: AccessAuthentication?
    private(set) var inspectionPorts: PortPair?
    private(set) var creationPorts: PortPair?
    init(
        operations: OperationLog,
        failAt: String? = nil,
        inspection: ManagedRouteInspection = .available,
        endpoint: URL = URL(string: "https://test.tailnet.ts.net")!
    ) {
        self.operations = operations; self.failAt = failAt; self.inspection = inspection; self.endpoint = endpoint
    }
    func inspect(httpsPort: Int, backendPort: Int) async throws -> ManagedRouteInspection {
        inspectionPorts = PortPair(https: httpsPort, backend: backendPort)
        await operations.append("route.inspect"); if failAt == "route.inspect" { throw InjectedFailure() }; return inspection
    }
    func create(tailscalePath: String, httpsPort: Int, backendPort: Int) async throws {
        creationPorts = PortPair(https: httpsPort, backend: backendPort)
        await operations.append("route.create")
        if failAt == "route.create" { throw InjectedFailure() }
    }
    func discoverEndpoint(httpsPort: Int) async throws -> URL {
        await operations.append("route.discoverEndpoint")
        if failAt == "route.discoverEndpoint" { throw InjectedFailure() }; return endpoint
    }
    func verifyEndpoint(_ endpoint: URL, authentication: AccessAuthentication) async throws {
        verifiedAuthentication = authentication
        await operations.append("route.verifyEndpoint"); if failAt == "route.verifyEndpoint" { throw InjectedFailure() }
    }
    func removeIfMatching(httpsPort: Int, backendPort: Int) async throws { await operations.append("route.remove") }
}

private struct PortPair: Equatable, Sendable {
    let https: Int
    let backend: Int
}

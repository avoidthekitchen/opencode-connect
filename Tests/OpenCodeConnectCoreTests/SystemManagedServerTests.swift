import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("Managed Server waits through transient connection failures until authenticated health succeeds")
func managedServerWaitsForReadiness() async throws {
    let http = DelayedReadinessHTTPChecker(failuresBeforeSuccess: 2)
    let server = SystemManagedServer(http: http)
    let configuration = ManagedServerConfiguration(
        executablePath: "/bin/sh",
        arguments: ["-c", "sleep 5", "opencode-test", "--port", "4096"],
        environment: [
            "OPENCODE_SERVER_USERNAME": "opencode",
            "OPENCODE_SERVER_PASSWORD": "test-secret",
        ],
        workingDirectory: URL(fileURLWithPath: "/private/tmp")
    )
    _ = try await server.launch(configuration)

    var verificationError: Error?
    do {
        try await server.verifyLocalHealth(authentication: .basic(username: "opencode", credential: "test-secret"))
    } catch {
        verificationError = error
    }
    _ = await server.stopGracefully(timeout: .seconds(1))

    #expect(verificationError == nil)
    #expect(await http.attempts == 3)
}

@Test("Managed Server health fails promptly when the launched process exits")
func managedServerReportsEarlyExit() async throws {
    let server = SystemManagedServer(
        http: DelayedReadinessHTTPChecker(failuresBeforeSuccess: .max),
        healthTimeout: .seconds(2),
        healthRetryDelay: .milliseconds(25)
    )
    _ = try await server.launch(ManagedServerConfiguration(
        executablePath: "/usr/bin/false",
        arguments: ["--port", "4096"],
        environment: [
            "OPENCODE_SERVER_USERNAME": "opencode",
            "OPENCODE_SERVER_PASSWORD": "test-secret",
        ],
        workingDirectory: URL(fileURLWithPath: "/private/tmp")
    ))
    let started = ContinuousClock.now

    var message = ""
    do {
        try await server.verifyLocalHealth(authentication: .basic(username: "opencode", credential: "test-secret"))
    } catch {
        message = error.localizedDescription
    }

    #expect(message.contains("exited before becoming healthy"))
    #expect(started.duration(to: .now) < .milliseconds(500))
}

@Test("Managed Server health retries remain bounded")
func managedServerReadinessTimeoutIsBounded() async throws {
    let server = SystemManagedServer(
        http: DelayedReadinessHTTPChecker(failuresBeforeSuccess: .max),
        healthTimeout: .milliseconds(125),
        healthRetryDelay: .milliseconds(25)
    )
    _ = try await server.launch(ManagedServerConfiguration(
        executablePath: "/bin/sh",
        arguments: ["-c", "sleep 5", "opencode-test", "--port", "4096"],
        environment: [
            "OPENCODE_SERVER_USERNAME": "opencode",
            "OPENCODE_SERVER_PASSWORD": "test-secret",
        ],
        workingDirectory: URL(fileURLWithPath: "/private/tmp")
    ))
    let started = ContinuousClock.now

    var failed = false
    do {
        try await server.verifyLocalHealth(authentication: .basic(username: "opencode", credential: "test-secret"))
    } catch {
        failed = true
    }
    _ = await server.stopGracefully(timeout: .seconds(1))

    #expect(failed)
    #expect(started.duration(to: .now) < .milliseconds(500))
}

@Test("Managed Server adoption requires PID, executable, port, fingerprint, and authenticated health to agree")
func managedServerAdoptionRequiresCompleteEvidence() async {
    let record = ManagedServerRecord(
        processIdentifier: 4242,
        executablePath: "/test/opencode",
        backendPort: 4096,
        executableFingerprint: "expected-fingerprint"
    )
    let configuration = ManagedServerConfiguration(
        executablePath: "/test/opencode",
        arguments: ["serve", "--hostname", "127.0.0.1", "--port", "4096"],
        environment: [:],
        workingDirectory: URL(fileURLWithPath: "/private/tmp")
    )
    let scenarios: [(ManagedServerRecord?, ManagedProcessSnapshot?, Bool, String?)] = [
        (record, ManagedProcessSnapshot(executablePath: "/test/opencode", executableFingerprint: "expected-fingerprint"), false, nil),
        (record, nil, false, "no longer running"),
        (record, ManagedProcessSnapshot(executablePath: "/other/process", executableFingerprint: "expected-fingerprint"), false, "different executable"),
        (record, ManagedProcessSnapshot(executablePath: "/test/opencode", executableFingerprint: "changed-fingerprint"), false, "changed on disk"),
        (ManagedServerRecord(processIdentifier: 4242, executablePath: "/test/opencode", backendPort: 5000, executableFingerprint: "expected-fingerprint"), ManagedProcessSnapshot(executablePath: "/test/opencode", executableFingerprint: "expected-fingerprint"), false, "recorded backend port"),
        (nil, nil, true, "occupied"),
    ]

    for (storedRecord, snapshot, portOccupied, expectedConflict) in scenarios {
        let server = SystemManagedServer(
            http: DelayedReadinessHTTPChecker(failuresBeforeSuccess: 0),
            processes: FixedManagedProcessInspector(snapshot: snapshot, portOccupied: portOccupied)
        )
        let inspection = await server.inspect(
            record: storedRecord,
            expectedConfiguration: configuration,
            authentication: .basic(username: "opencode", credential: "secret")
        )

        if let expectedConflict {
            guard case let .conflict(evidence) = inspection else {
                Issue.record("Expected Conflict for \(expectedConflict), got \(inspection)")
                continue
            }
            #expect(evidence.contains(expectedConflict))
        } else {
            #expect(inspection == .verified(record))
        }
    }
}

private actor DelayedReadinessHTTPChecker: AuthenticatedHTTPChecking {
    private let failuresBeforeSuccess: Int
    private(set) var attempts = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func verify(url: URL, authentication: AccessAuthentication) async throws {
        attempts += 1
        if attempts <= failuresBeforeSuccess {
            throw URLError(.cannotConnectToHost)
        }
    }
}

private struct FixedManagedProcessInspector: ManagedProcessInspecting {
    let snapshot: ManagedProcessSnapshot?
    let portOccupied: Bool

    func snapshot(processIdentifier: Int32) -> ManagedProcessSnapshot? { snapshot }
    func isLoopbackPortOccupied(_ port: Int) -> Bool { portOccupied }
}

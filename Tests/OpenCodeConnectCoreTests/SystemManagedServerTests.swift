import Foundation
import Darwin
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
    let http = DelayedReadinessHTTPChecker(failuresBeforeSuccess: .max)
    let server = SystemManagedServer(
        http: http,
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
    #expect(started.duration(to: .now) < .seconds(3))
}

@Test("Managed Server health retries remain bounded")
func managedServerReadinessTimeoutIsBounded() async throws {
    let http = DelayedReadinessHTTPChecker(failuresBeforeSuccess: .max)
    let server = SystemManagedServer(
        http: http,
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
    #expect(started.duration(to: .now) < .seconds(3))
    #expect(await http.attempts >= 2)
    #expect(await http.attempts <= 10)
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
        (record, ManagedProcessSnapshot(executablePath: "/other/process", executableFingerprint: "expected-fingerprint"), false, "different executable"),
        (record, ManagedProcessSnapshot(executablePath: "/test/opencode", executableFingerprint: "changed-fingerprint"), false, "changed on disk"),
        (ManagedServerRecord(processIdentifier: 4242, executablePath: "/test/opencode", backendPort: 5000, executableFingerprint: "expected-fingerprint"), ManagedProcessSnapshot(executablePath: "/test/opencode", executableFingerprint: "expected-fingerprint"), false, "recorded backend port"),
        (nil, nil, true, "occupied"),
        (record, nil, true, "remains occupied"),
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

@Test("an exited Managed Server with a free backend port is safely treated as missing")
func exitedManagedServerCanBeRecreated() async {
    let server = SystemManagedServer(
        http: DelayedReadinessHTTPChecker(failuresBeforeSuccess: 0),
        processes: FixedManagedProcessInspector(snapshot: nil, portOccupied: false)
    )
    let inspection = await server.inspect(
        record: ManagedServerRecord(
            processIdentifier: 4242,
            executablePath: "/test/opencode",
            backendPort: 4096,
            executableFingerprint: "expected-fingerprint"
        ),
        expectedConfiguration: ManagedServerConfiguration(
            executablePath: "/test/opencode",
            arguments: ["serve", "--hostname", "127.0.0.1", "--port", "4096"],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/private/tmp")
        ),
        authentication: .basic(username: "opencode", credential: "secret")
    )

    #expect(inspection == .missing)
}

@Test("Loopback port inspection detects listeners without opening a connection")
func loopbackPortInspectionDoesNotConnectToTheListener() throws {
    let listener = try LoopbackTestListener()
    defer { listener.close() }

    let occupied = SystemManagedProcessInspector().isLoopbackPortOccupied(listener.port)
    let acceptedDescriptor = listener.acceptPendingConnection()
    if acceptedDescriptor >= 0 {
        Darwin.close(acceptedDescriptor)
    }

    #expect(occupied)
    #expect(acceptedDescriptor < 0)
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

private final class LoopbackTestListener {
    let descriptor: Int32
    private(set) var port: Int = 0

    init() throws {
        descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        port = Int(in_port_t(bigEndian: boundAddress.sin_port))

        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    }

    func acceptPendingConnection() -> Int32 {
        Darwin.accept(descriptor, nil, nil)
    }

    func close() {
        Darwin.close(descriptor)
    }
}

import Darwin
import Foundation
import Security

public struct KeychainAccessCredentialStore: AccessCredentialStoring {
    private let service: String
    private let account: String

    public init(service: String = "com.avoidthekitchen.OpenCodeConnect", account: String = "protected-access") {
        self.service = service
        self.account = account
    }

    public func load() async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let credential = String(data: data, encoding: .utf8) else {
            throw KeychainCredentialError(status: status)
        }
        return credential
    }

    public func save(_ credential: String) async throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(credential.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainCredentialError(status: updateStatus) }
        var item = identity
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainCredentialError(status: addStatus) }
    }

    public func delete() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialError(status: status)
        }
    }
}

private struct KeychainCredentialError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Keychain operation failed (\(status))." }
}

public protocol AuthenticatedHTTPChecking: Sendable {
    func verify(url: URL, authentication: AccessAuthentication) async throws
}

public struct URLSessionAuthenticatedHTTPChecker: AuthenticatedHTTPChecking {
    public init() {}

    public func verify(url: URL, authentication: AccessAuthentication) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if case let .basic(username, credential) = authentication {
            let token = Data("\(username):\(credential)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw HTTPHealthError.invalidResponse
        }
    }
}

private enum HTTPHealthError: LocalizedError {
    case invalidResponse
    var errorDescription: String? { "Authenticated health verification failed." }
}

public struct SystemManagedProcessInspector: ManagedProcessInspecting {
    public init() {}

    public func snapshot(processIdentifier: Int32) -> ManagedProcessSnapshot? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN * 4))
        let length = proc_pidpath(processIdentifier, &pathBuffer, UInt32(pathBuffer.count))
        guard length > 0 else { return nil }
        let bytes = pathBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return Self.snapshot(atPath: String(decoding: bytes, as: UTF8.self))
    }

    public func isLoopbackPortOccupied(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    static func snapshot(atPath path: String) -> ManagedProcessSnapshot? {
        let executableURL = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard let values = try? executableURL.resourceValues(forKeys: [
            .fileResourceIdentifierKey, .fileSizeKey, .contentModificationDateKey,
        ]) else { return nil }
        let fingerprint = [
            values.fileResourceIdentifier.map { String(describing: $0) } ?? "unknown",
            String(values.fileSize ?? -1),
            String(values.contentModificationDate?.timeIntervalSince1970 ?? -1),
        ].joined(separator: ":")
        return ManagedProcessSnapshot(
            executablePath: executableURL.path,
            executableFingerprint: fingerprint
        )
    }
}

public actor SystemManagedServer: ManagedServerControlling {
    private let http: any AuthenticatedHTTPChecking
    private let healthTimeout: Duration
    private let healthRetryDelay: Duration
    private let processes: any ManagedProcessInspecting
    private var process: Process?
    private var configuration: ManagedServerConfiguration?
    private var adoptedRecord: ManagedServerRecord?

    public init(
        http: any AuthenticatedHTTPChecking = URLSessionAuthenticatedHTTPChecker(),
        processes: any ManagedProcessInspecting = SystemManagedProcessInspector(),
        healthTimeout: Duration = .seconds(5),
        healthRetryDelay: Duration = .milliseconds(100)
    ) {
        self.http = http
        self.processes = processes
        self.healthTimeout = healthTimeout
        self.healthRetryDelay = healthRetryDelay
    }

    public func launch(_ configuration: ManagedServerConfiguration) async throws -> Bool {
        if process?.isRunning == true { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.executablePath)
        process.arguments = configuration.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, supplied in supplied }
        process.currentDirectoryURL = configuration.workingDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        self.configuration = configuration
        return true
    }

    public func runtimeRecord() async throws -> ManagedServerRecord? {
        guard let process, process.isRunning, let configuration,
              let portIndex = configuration.arguments.firstIndex(of: "--port"),
              configuration.arguments.indices.contains(configuration.arguments.index(after: portIndex)),
              let backendPort = Int(configuration.arguments[configuration.arguments.index(after: portIndex)])
        else { return nil }
        guard let snapshot = SystemManagedProcessInspector.snapshot(atPath: configuration.executablePath)
        else { return nil }
        let record = ManagedServerRecord(
            processIdentifier: process.processIdentifier,
            executablePath: snapshot.executablePath,
            backendPort: backendPort,
            executableFingerprint: snapshot.executableFingerprint
        )
        adoptedRecord = record
        return record
    }

    public func inspect(
        record: ManagedServerRecord?,
        expectedConfiguration: ManagedServerConfiguration,
        authentication: AccessAuthentication
    ) async -> ManagedServerInspection {
        guard let expectedPort = Self.backendPort(from: expectedConfiguration) else {
            return .conflict("The expected Managed Server backend port is invalid.")
        }
        guard let record else {
            return processes.isLoopbackPortOccupied(expectedPort)
                ? .conflict("Backend port \(expectedPort) is occupied without a verifiable runtime record.")
                : .missing
        }
        guard record.backendPort == expectedPort else {
            return .conflict("The recorded backend port \(record.backendPort) does not match the expected port \(expectedPort).")
        }
        let expectedPath = URL(fileURLWithPath: expectedConfiguration.executablePath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        guard record.executablePath == expectedPath else {
            return .conflict("The recorded executable path does not match the configured OpenCode executable.")
        }
        guard let snapshot = processes.snapshot(processIdentifier: record.processIdentifier) else {
            return processes.isLoopbackPortOccupied(expectedPort)
                ? .conflict("The recorded PID \(record.processIdentifier) is unavailable while backend port \(expectedPort) remains occupied.")
                : .missing
        }
        guard snapshot.executablePath == record.executablePath else {
            return .conflict("PID \(record.processIdentifier) now belongs to a different executable.")
        }
        guard snapshot.executableFingerprint == record.executableFingerprint else {
            return .conflict("The recorded OpenCode executable changed on disk.")
        }
        do {
            try await http.verify(
                url: URL(string: "http://127.0.0.1:\(expectedPort)")!,
                authentication: authentication
            )
        } catch {
            return .conflict("The recorded process did not pass authenticated OpenCode health verification.")
        }
        configuration = expectedConfiguration
        adoptedRecord = record
        return .verified(record)
    }

    public func verifyLocalHealth(authentication: AccessAuthentication) async throws {
        guard let configuration,
              let portIndex = configuration.arguments.firstIndex(of: "--port"),
              configuration.arguments.indices.contains(configuration.arguments.index(after: portIndex)),
              let url = URL(string: "http://127.0.0.1:\(configuration.arguments[configuration.arguments.index(after: portIndex)])")
        else { throw HTTPHealthError.invalidResponse }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: healthTimeout)
        while true {
            do {
                try await http.verify(url: url, authentication: authentication)
                return
            } catch {
                guard process?.isRunning == true else {
                    throw ManagedServerHealthError.exitedBeforeHealthy
                }
                guard clock.now < deadline else { throw error }
                try await Task.sleep(for: healthRetryDelay)
            }
        }
    }

    public func stopGracefully(timeout: Duration) async -> Bool {
        if process == nil, let adoptedRecord {
            guard await ownershipIsVerified() else { return false }
            Darwin.kill(adoptedRecord.processIdentifier, SIGTERM)
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while processes.snapshot(processIdentifier: adoptedRecord.processIdentifier) != nil,
                  clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
            return processes.snapshot(processIdentifier: adoptedRecord.processIdentifier) == nil
        }
        guard let process, process.isRunning else { return true }
        process.terminate()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while process.isRunning, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        return !process.isRunning
    }

    public func ownershipIsVerified() async -> Bool {
        if let adoptedRecord {
            return processes.snapshot(processIdentifier: adoptedRecord.processIdentifier) == ManagedProcessSnapshot(
                executablePath: adoptedRecord.executablePath,
                executableFingerprint: adoptedRecord.executableFingerprint
            )
        }
        guard let process, process.isRunning, let configuration else { return false }
        return process.executableURL?.standardizedFileURL.path == URL(fileURLWithPath: configuration.executablePath).standardizedFileURL.path
    }

    public func forceStop() async {
        if let adoptedRecord, await ownershipIsVerified() {
            Darwin.kill(adoptedRecord.processIdentifier, SIGKILL)
            return
        }
        guard let process, process.isRunning else { return }
        Darwin.kill(process.processIdentifier, SIGKILL)
    }

    private static func backendPort(from configuration: ManagedServerConfiguration) -> Int? {
        guard let portIndex = configuration.arguments.firstIndex(of: "--port"),
              configuration.arguments.indices.contains(configuration.arguments.index(after: portIndex))
        else { return nil }
        return Int(configuration.arguments[configuration.arguments.index(after: portIndex)])
    }
}

private enum ManagedServerHealthError: LocalizedError {
    case exitedBeforeHealthy

    var errorDescription: String? {
        "The Managed Server exited before becoming healthy."
    }
}

public actor SystemManagedRoute: ManagedRouteControlling {
    private var tailscalePath: String
    private var environment: [String: String]
    private let commands: any CommandRunning
    private let http: any AuthenticatedHTTPChecking
    private let endpointTimeout: Duration
    private let endpointRetryDelay: Duration

    public init(
        tailscalePath: String,
        commands: any CommandRunning,
        http: any AuthenticatedHTTPChecking = URLSessionAuthenticatedHTTPChecker(),
        endpointTimeout: Duration = .seconds(10),
        endpointRetryDelay: Duration = .milliseconds(250)
    ) {
        self.tailscalePath = tailscalePath
        self.environment = tailscalePath.contains(".app/Contents/MacOS/") ? ["TS_MAC_CLIENT_USE_CLI": "1"] : [:]
        self.commands = commands
        self.http = http
        self.endpointTimeout = endpointTimeout
        self.endpointRetryDelay = endpointRetryDelay
    }

    public func configure(tailscalePath: String) async {
        self.tailscalePath = tailscalePath
        environment = Self.environment(for: tailscalePath)
    }

    public func inspect(httpsPort: Int, backendPort: Int) async throws -> ManagedRouteInspection {
        let status = try await serveStatus()
        guard let inspection = CLIOutputParser.managedRouteInspection(
            status,
            httpsPort: httpsPort,
            backendPort: backendPort
        ) else {
            throw RouteCommandError(
                operation: "parsing Tailscale Serve status", timeoutSeconds: 5,
                output: "Tailscale returned an invalid Serve status response", timedOut: false
            )
        }
        return inspection
    }

    public func create(tailscalePath: String, httpsPort: Int, backendPort: Int) async throws {
        await configure(tailscalePath: tailscalePath)
        let result = await commands.run(request([
            "serve", "--bg", "--yes", "--https=\(httpsPort)", "http://127.0.0.1:\(backendPort)",
        ], timeout: .seconds(30)))
        guard result.exitCode == 0, !result.timedOut else {
            throw RouteCommandError(
                operation: "creating the Managed Route",
                timeoutSeconds: 30,
                output: result.standardError,
                timedOut: result.timedOut
            )
        }
    }

    public func discoverEndpoint(httpsPort: Int) async throws -> URL {
        let status = try await serveStatus()
        guard let endpoint = CLIOutputParser.serveEndpoint(status, httpsPort: httpsPort) else {
            throw RouteCommandError(
                operation: "discovering the Endpoint", timeoutSeconds: 5,
                output: "Endpoint missing", timedOut: false
            )
        }
        return endpoint
    }

    public func verifyEndpoint(_ endpoint: URL, authentication: AccessAuthentication) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: endpointTimeout)
        while true {
            do {
                try await http.verify(url: endpoint, authentication: authentication)
                return
            } catch {
                guard clock.now < deadline else { throw error }
                try await Task.sleep(for: endpointRetryDelay)
            }
        }
    }

    public func removeIfMatching(httpsPort: Int, backendPort: Int) async throws {
        guard try await inspect(httpsPort: httpsPort, backendPort: backendPort) == .matching else { return }
        let result = await commands.run(request(
            ["serve", "--yes", "--https=\(httpsPort)", "off"],
            timeout: .seconds(30)
        ))
        guard result.exitCode == 0, !result.timedOut else {
            throw RouteCommandError(
                operation: "removing the Managed Route",
                timeoutSeconds: 30,
                output: result.standardError,
                timedOut: result.timedOut
            )
        }
    }

    private func serveStatus() async throws -> String {
        let result = await commands.run(request(["serve", "status", "--json"]))
        guard result.exitCode == 0, !result.timedOut else {
            throw RouteCommandError(
                operation: "reading Tailscale Serve status",
                timeoutSeconds: 5,
                output: result.standardError,
                timedOut: result.timedOut
            )
        }
        return result.standardOutput
    }

    private func request(_ arguments: [String], timeout: Duration = .seconds(5)) -> CommandRequest {
        CommandRequest(executablePath: tailscalePath, arguments: arguments, environment: environment, timeout: timeout)
    }

    private static func environment(for tailscalePath: String) -> [String: String] {
        tailscalePath.contains(".app/Contents/MacOS/") ? ["TS_MAC_CLIENT_USE_CLI": "1"] : [:]
    }
}

private struct RouteCommandError: LocalizedError {
    let operation: String
    let timeoutSeconds: Int
    let output: String
    let timedOut: Bool

    var errorDescription: String? {
        if timedOut {
            return "Tailscale timed out after \(timeoutSeconds) seconds while \(operation)."
        }
        return output.isEmpty ? "Tailscale failed while \(operation)." : "Tailscale failed while \(operation): \(output)"
    }
}

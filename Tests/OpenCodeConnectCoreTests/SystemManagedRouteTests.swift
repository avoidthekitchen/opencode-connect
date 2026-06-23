import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("system route adapter uses bounded non-interactive private Tailscale Serve commands")
func systemRouteUsesTargetedPrivateCommands() async throws {
    let status = #"{"Web":{"device.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"}}}}}"#
    let commands = RouteCommandRunner(results: [
        CommandResult(exitCode: 0, standardOutput: #"{"Web":{}}"#, standardError: "", timedOut: false),
        CommandResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: false),
        CommandResult(exitCode: 0, standardOutput: status, standardError: "", timedOut: false),
        CommandResult(exitCode: 0, standardOutput: status, standardError: "", timedOut: false),
        CommandResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: false),
    ])
    let http = RecordingHTTPChecker()
    let route = SystemManagedRoute(tailscalePath: "/test/tailscale", commands: commands, http: http)

    #expect(try await route.inspect(httpsPort: 443, backendPort: 4096) == .available)
    try await route.create(tailscalePath: "/test/tailscale", httpsPort: 443, backendPort: 4096)
    let endpoint = try await route.discoverEndpoint(httpsPort: 443)
    try await route.verifyEndpoint(endpoint, authentication: .basic(username: "opencode", credential: "secret"))
    try await route.removeIfMatching(httpsPort: 443, backendPort: 4096)

    let arguments = await commands.requests.map(\.arguments)
    #expect(arguments == [
        ["serve", "status", "--json"],
        ["serve", "--bg", "--yes", "--https=443", "http://127.0.0.1:4096"],
        ["serve", "status", "--json"],
        ["serve", "status", "--json"],
        ["serve", "--yes", "--https=443", "off"],
    ])
    #expect(arguments.joined().allSatisfy { !$0.contains("funnel") && !$0.contains("reset") })
    let requests = await commands.requests
    #expect(requests[1].timeout == .seconds(30))
    #expect(requests[4].timeout == .seconds(30))
    #expect(await http.verifications == ["https://device.example.ts.net|opencode|secret"])
}

@Test("Managed Route waits through transient Endpoint propagation failures")
func managedRouteWaitsForEndpointReadiness() async {
    let http = DelayedEndpointHTTPChecker(failuresBeforeSuccess: 2)
    let route = SystemManagedRoute(
        tailscalePath: "/test/tailscale",
        commands: RouteCommandRunner(results: []),
        http: http
    )

    var verificationError: Error?
    do {
        try await route.verifyEndpoint(
            URL(string: "https://device.example.ts.net")!,
            authentication: .basic(username: "opencode", credential: "secret")
        )
    } catch {
        verificationError = error
    }

    #expect(verificationError == nil)
    #expect(await http.attempts == 3)
}

@Test("Managed Route Endpoint retries remain bounded")
func managedRouteEndpointTimeoutIsBounded() async {
    let http = DelayedEndpointHTTPChecker(failuresBeforeSuccess: .max)
    let route = SystemManagedRoute(
        tailscalePath: "/test/tailscale",
        commands: RouteCommandRunner(results: []),
        http: http,
        endpointTimeout: .milliseconds(125),
        endpointRetryDelay: .milliseconds(25)
    )
    let started = ContinuousClock.now

    var failed = false
    do {
        try await route.verifyEndpoint(
            URL(string: "https://device.example.ts.net")!,
            authentication: .basic(username: "opencode", credential: "secret")
        )
    } catch {
        failed = true
    }

    #expect(failed)
    #expect(started.duration(to: .now) < .seconds(3))
    #expect(await http.attempts >= 2)
    #expect(await http.attempts <= 10)
}

@Test("Tailscale route creation timeout identifies its stage and deadline")
func routeCreationTimeoutIsSpecific() async {
    let commands = RouteCommandRunner(results: [
        CommandResult(exitCode: -1, standardOutput: "", standardError: "Command timed out", timedOut: true),
    ])
    let route = SystemManagedRoute(tailscalePath: "/test/tailscale", commands: commands)

    var message = ""
    do {
        try await route.create(tailscalePath: "/test/tailscale", httpsPort: 443, backendPort: 4096)
    } catch {
        message = error.localizedDescription
    }

    #expect(message.contains("creating the Managed Route"))
    #expect(message.contains("30 seconds"))
}

@Test("Managed Route inspection fails closed when Serve status is malformed")
func malformedServeStatusFailsClosed() async {
    let commands = RouteCommandRunner(results: [
        CommandResult(exitCode: 0, standardOutput: "not-json", standardError: "", timedOut: false),
    ])
    let route = SystemManagedRoute(tailscalePath: "/test/tailscale", commands: commands)

    await #expect(throws: Error.self) {
        try await route.inspect(httpsPort: 443, backendPort: 4096)
    }
    #expect(await commands.requests.count == 1)
}

@Test("Managed Route discovers only the configured HTTPS listener")
func endpointDiscoveryUsesConfiguredPort() async throws {
    let status = #"{"Web":{"wrong.example.ts.net:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9000"}}},"right.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"}}}}}"#
    let route = SystemManagedRoute(
        tailscalePath: "/test/tailscale",
        commands: RouteCommandRunner(results: [
            CommandResult(exitCode: 0, standardOutput: status, standardError: "", timedOut: false),
        ])
    )

    #expect(try await route.discoverEndpoint(httpsPort: 443) == URL(string: "https://right.example.ts.net"))
}

@Test("Managed Route switches every operation to the currently resolved Tailscale executable")
func managedRouteUsesCurrentExecutable() async throws {
    let commands = RouteCommandRunner(results: [
        CommandResult(exitCode: 0, standardOutput: #"{"Web":{}}"#, standardError: "", timedOut: false),
    ])
    let route = SystemManagedRoute(tailscalePath: "/old/tailscale", commands: commands)

    await route.configure(tailscalePath: "/Applications/Tailscale.app/Contents/MacOS/Tailscale")
    _ = try await route.inspect(httpsPort: 443, backendPort: 4096)

    let request = try #require(await commands.requests.first)
    #expect(request.executablePath == "/Applications/Tailscale.app/Contents/MacOS/Tailscale")
    #expect(request.environment["TS_MAC_CLIENT_USE_CLI"] == "1")
}

private actor RouteCommandRunner: CommandRunning {
    private var results: [CommandResult]
    private(set) var requests: [CommandRequest] = []
    init(results: [CommandResult]) { self.results = results }
    func run(_ request: CommandRequest) async -> CommandResult {
        requests.append(request)
        return results.removeFirst()
    }
}

private actor RecordingHTTPChecker: AuthenticatedHTTPChecking {
    private(set) var verifications: [String] = []
    func verify(url: URL, authentication: AccessAuthentication) async throws {
        if case let .basic(username, credential) = authentication {
            verifications.append("\(url.absoluteString)|\(username)|\(credential)")
        }
    }
}

private actor DelayedEndpointHTTPChecker: AuthenticatedHTTPChecking {
    private let failuresBeforeSuccess: Int
    private(set) var attempts = 0
    init(failuresBeforeSuccess: Int) { self.failuresBeforeSuccess = failuresBeforeSuccess }
    func verify(url: URL, authentication: AccessAuthentication) async throws {
        attempts += 1
        if attempts <= failuresBeforeSuccess { throw URLError(.cannotFindHost) }
    }
}

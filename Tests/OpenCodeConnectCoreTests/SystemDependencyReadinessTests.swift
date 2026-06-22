import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("Homebrew OpenCode is discovered and validated with a bounded version command")
func discoversHomebrewOpenCode() async throws {
    let files = StubExecutableFiles(executablePaths: ["/opt/homebrew/bin/opencode"])
    let commands = QueueCommandRunner(results: [
        CommandResult(exitCode: 0, standardOutput: "1.1.25\n", standardError: "", timedOut: false),
    ])
    let checker = SystemDependencyReadiness(
        files: files,
        commands: commands,
        homeDirectory: URL(fileURLWithPath: "/Users/test")
    )

    let result = await checker.evaluate(settings: DependencySettings())

    #expect(result.openCode == .ready(version: "1.1.25", executablePath: "/opt/homebrew/bin/opencode"))
    let requests = await commands.requests
    #expect(requests.first?.arguments == ["--version"])
    #expect(try #require(requests.first).timeout <= .seconds(5))
}

@Test("App Store Tailscale is validated in CLI mode")
func discoversAppStoreTailscaleInCLIMode() async {
    let tailscalePath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    let files = StubExecutableFiles(executablePaths: ["/opt/homebrew/bin/opencode", tailscalePath])
    let commands = QueueCommandRunner(results: [
        CommandResult(exitCode: 0, standardOutput: "1.1.25\n", standardError: "", timedOut: false),
        CommandResult(exitCode: 0, standardOutput: "1.82.5\n", standardError: "", timedOut: false),
        CommandResult(exitCode: 0, standardOutput: #"{"BackendState":"Running"}"#, standardError: "", timedOut: false),
        CommandResult(exitCode: 0, standardOutput: "{}", standardError: "", timedOut: false),
    ])
    let checker = SystemDependencyReadiness(
        files: files,
        commands: commands,
        homeDirectory: URL(fileURLWithPath: "/Users/test")
    )

    let result = await checker.evaluate(settings: DependencySettings())

    #expect(result.tailscale == .ready(version: "1.82.5", executablePath: tailscalePath))
    let tailscaleRequests = await commands.requests.filter { $0.executablePath == tailscalePath }
    #expect(tailscaleRequests.map(\.arguments) == [
        ["version"], ["status", "--json"], ["serve", "status", "--json"],
    ])
    #expect(tailscaleRequests.allSatisfy { $0.environment["TS_MAC_CLIENT_USE_CLI"] == "1" })
}

private struct StubExecutableFiles: ExecutableFileChecking {
    let executablePaths: Set<String>

    func executableStatus(atPath path: String) -> ExecutableFileStatus {
        executablePaths.contains(path) ? .executable : .missing
    }
}

private actor QueueCommandRunner: CommandRunning {
    private var results: [CommandResult]
    private(set) var requests: [CommandRequest] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(_ request: CommandRequest) async -> CommandResult {
        requests.append(request)
        return results.isEmpty
            ? CommandResult(exitCode: 1, standardOutput: "", standardError: "No result", timedOut: false)
            : results.removeFirst()
    }
}

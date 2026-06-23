import Foundation
import Darwin

public enum ExecutableFileStatus: Equatable, Sendable {
    case executable
    case missing
    case notExecutable
}

public protocol ExecutableFileChecking: Sendable {
    func executableStatus(atPath path: String) -> ExecutableFileStatus
}

public struct FileManagerExecutableChecker: ExecutableFileChecking {
    public init() {}

    public func executableStatus(atPath path: String) -> ExecutableFileStatus {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .missing
        }
        return FileManager.default.isExecutableFile(atPath: path) ? .executable : .notExecutable
    }
}

public struct CommandRequest: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]
    public let timeout: Duration

    public init(
        executablePath: String,
        arguments: [String],
        environment: [String: String] = [:],
        timeout: Duration
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
    }
}

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let timedOut: Bool

    public init(exitCode: Int32, standardOutput: String, standardError: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
    }
}

public protocol CommandRunning: Sendable {
    func run(_ request: CommandRequest) async -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ request: CommandRequest) async -> CommandResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = URL(fileURLWithPath: request.executablePath)
            process.arguments = request.arguments
            process.environment = ProcessInfo.processInfo.environment.merging(request.environment) { _, override in override }
            process.standardOutput = standardOutput
            process.standardError = standardError

            do {
                try process.run()
            } catch {
                return CommandResult(
                    exitCode: -1,
                    standardOutput: "",
                    standardError: error.localizedDescription,
                    timedOut: false
                )
            }

            let processID = process.processIdentifier
            let ownsProcessGroup = setpgid(processID, processID) == 0
            standardOutput.fileHandleForWriting.closeFile()
            standardError.fileHandleForWriting.closeFile()
            let outputReader = Task.detached { drainBoundedString(from: standardOutput.fileHandleForReading) }
            let errorReader = Task.detached { drainBoundedString(from: standardError.fileHandleForReading) }

            let timeout = request.timeout.components
            let deadline = Date().addingTimeInterval(
                Double(timeout.seconds) + Double(timeout.attoseconds) / 1_000_000_000_000_000_000
            )
            while process.isRunning, Date() < deadline {
                usleep(10_000)
            }

            let timedOut = process.isRunning
            if timedOut {
                if ownsProcessGroup {
                    Darwin.kill(-processID, SIGTERM)
                } else {
                    process.terminate()
                }
                let terminationDeadline = Date().addingTimeInterval(0.25)
                while process.isRunning, Date() < terminationDeadline {
                    usleep(10_000)
                }
                if process.isRunning {
                    if ownsProcessGroup {
                        Darwin.kill(-processID, SIGKILL)
                    } else {
                        Darwin.kill(processID, SIGKILL)
                    }
                }
            }

            process.waitUntilExit()
            let capturedOutput = await outputReader.value
            let capturedError = await errorReader.value
            return CommandResult(
                exitCode: timedOut ? -1 : process.terminationStatus,
                standardOutput: capturedOutput,
                standardError: timedOut ? "Command timed out" : capturedError,
                timedOut: timedOut
            )
        }.value
    }
}

private func drainBoundedString(from handle: FileHandle) -> String {
    let limit = 64 * 1024
    var captured = Data()
    while true {
        let chunk = handle.readData(ofLength: 16 * 1024)
        guard !chunk.isEmpty else { break }
        if captured.count < limit {
            captured.append(chunk.prefix(limit - captured.count))
        }
    }
    return String(decoding: captured, as: UTF8.self)
}

public struct SystemDependencyReadiness: DependencyReadinessChecking {
    private let files: any ExecutableFileChecking
    private let commands: any CommandRunning
    private let homeDirectory: URL

    public init(
        files: any ExecutableFileChecking,
        commands: any CommandRunning,
        homeDirectory: URL
    ) {
        self.files = files
        self.commands = commands
        self.homeDirectory = homeDirectory
    }

    public func evaluate(settings: DependencySettings) async -> ReadinessEvaluation {
        let openCode = await evaluateOpenCode(customPath: settings.customOpenCodePath)
        let tailscale = await evaluateTailscale(customPath: settings.customTailscalePath)
        return ReadinessEvaluation(openCode: openCode, tailscale: tailscale)
    }

    private func evaluateTailscale(customPath: String?) async -> DependencyReadiness {
        guard let path = TailscaleExecutableResolver.resolve(customPath: customPath, checking: files) else {
            if let customPath {
                return .invalidCustomPath(path: customPath, reason: reasonForInvalidPath(customPath))
            }
            return .missing
        }
        let environment = TailscaleExecutableResolver.environment(for: path)
        let versionResult = await commands.run(CommandRequest(
            executablePath: path,
            arguments: ["version"],
            environment: environment,
            timeout: .seconds(5)
        ))
        guard !versionResult.timedOut,
              versionResult.exitCode == 0,
              let version = CLIOutputParser.tailscaleVersion(versionResult.standardOutput)
        else {
            return customPath == nil
                ? .missing
                : .invalidCustomPath(path: path, reason: "Version validation failed")
        }

        let statusResult = await commands.run(CommandRequest(
            executablePath: path,
            arguments: ["status", "--json"],
            environment: environment,
            timeout: .seconds(5)
        ))
        if statusResult.timedOut {
            return .unavailable("status validation timed out")
        }
        if statusResult.exitCode != 0 {
            let reason = statusResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unavailable(reason.isEmpty ? "the CLI did not report status" : reason)
        }
        switch CLIOutputParser.tailscaleConnection(statusResult.standardOutput) {
        case .signedOut:
            return .signedOut
        case .disconnected:
            return .disconnected
        case .unknown:
            return .unavailable("the CLI returned an invalid status response")
        case .connected:
            break
        }

        let serveResult = await commands.run(CommandRequest(
            executablePath: path,
            arguments: ["serve", "status", "--json"],
            environment: environment,
            timeout: .seconds(5)
        ))
        if serveResult.timedOut {
            return .serveUnavailable("validation timed out")
        }
        if serveResult.exitCode != 0 {
            let combinedOutput = serveResult.standardOutput + "\n" + serveResult.standardError
            if let approvalURL = CLIOutputParser.tailscaleApprovalURL(combinedOutput) {
                return .serveApprovalRequired(approvalURL)
            }
            let reason = serveResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return .serveUnavailable(reason.isEmpty ? "the CLI did not report Serve status" : reason)
        }

        return .ready(version: version, executablePath: path)
    }

    private func evaluateOpenCode(customPath: String?) async -> DependencyReadiness {
        let knownPaths = [
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            homeDirectory.appending(path: ".opencode/bin/opencode").path,
            homeDirectory.appending(path: ".local/bin/opencode").path,
        ]
        guard let path = resolve(customPath: customPath, knownPaths: knownPaths) else {
            if let customPath {
                return .invalidCustomPath(path: customPath, reason: reasonForInvalidPath(customPath))
            }
            return .missing
        }
        let result = await commands.run(CommandRequest(
            executablePath: path,
            arguments: ["--version"],
            timeout: .seconds(5)
        ))
        guard !result.timedOut,
              result.exitCode == 0,
              let version = CLIOutputParser.openCodeVersion(result.standardOutput)
        else {
            return customPath == nil
                ? .missing
                : .invalidCustomPath(path: path, reason: "Version validation failed")
        }
        return .ready(version: version, executablePath: path)
    }

    private func resolve(customPath: String?, knownPaths: [String]) -> String? {
        if let customPath {
            return files.executableStatus(atPath: customPath) == .executable ? customPath : nil
        }
        return knownPaths.first { files.executableStatus(atPath: $0) == .executable }
    }

    private func reasonForInvalidPath(_ path: String) -> String {
        switch files.executableStatus(atPath: path) {
        case .missing: "File does not exist"
        case .notExecutable: "File is not executable"
        case .executable: "Version validation failed"
        }
    }
}

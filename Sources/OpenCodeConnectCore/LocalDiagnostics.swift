import Foundation

public struct DiagnosticsMetadata: Equatable, Sendable {
    public let appVersion: String
    public let osVersion: String

    public init(appVersion: String, osVersion: String) {
        self.appVersion = appVersion
        self.osVersion = osVersion
    }

    public static var current: DiagnosticsMetadata {
        DiagnosticsMetadata(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

public struct DiagnosticsReview: Equatable, Sendable {
    public let warning: String
    public let text: String

    public init(warning: String, text: String) {
        self.warning = warning
        self.text = text
    }
}

public struct DiagnosticsContext: Sendable {
    public let metadata: DiagnosticsMetadata
    public let openCodeVersion: String
    public let openCodePath: String
    public let tailscaleVersion: String
    public let tailscalePath: String
    public let desiredState: DesiredState
    public let observedState: ObservedState
    public let components: [ComponentReadiness]
    public let routeTarget: String
    public let failureStage: FailureStage?

    public init(
        metadata: DiagnosticsMetadata,
        openCodeVersion: String,
        openCodePath: String,
        tailscaleVersion: String,
        tailscalePath: String,
        desiredState: DesiredState,
        observedState: ObservedState,
        components: [ComponentReadiness],
        routeTarget: String,
        failureStage: FailureStage?
    ) {
        self.metadata = metadata
        self.openCodeVersion = openCodeVersion
        self.openCodePath = openCodePath
        self.tailscaleVersion = tailscaleVersion
        self.tailscalePath = tailscalePath
        self.desiredState = desiredState
        self.observedState = observedState
        self.components = components
        self.routeTarget = routeTarget
        self.failureStage = failureStage
    }
}

public actor LocalDiagnostics {
    private let capacity: Int
    private let maximumEntryLength: Int
    private var entries: [String] = []

    public init(capacity: Int = 100, maximumEntryLength: Int = 2_048) {
        self.capacity = max(1, capacity)
        self.maximumEntryLength = max(1, maximumEntryLength)
    }

    public func recordLifecycle(_ event: String, sensitiveValues: [String] = []) {
        append(sanitize(event, sensitiveValues: sensitiveValues))
    }

    public func recordCommandOutput(_ output: String, sensitiveValues: [String] = []) {
        append(sanitize(output, sensitiveValues: sensitiveValues))
    }

    public func recentEntries() -> [String] { entries }

    public func sanitizedText(_ value: String, sensitiveValues: [String] = []) -> String {
        sanitize(value, sensitiveValues: sensitiveValues)
    }

    public func makeReview(context: DiagnosticsContext) -> DiagnosticsReview {
        let componentLines = context.components.map { "- \($0.name): \($0.detail)" }.joined(separator: "\n")
        let events = entries.map { "- \($0)" }.joined(separator: "\n")
        let desired = context.desiredState == .enabled ? "Enabled" : "Disabled"
        let observed = String(describing: context.observedState).capitalized
        let stage = context.failureStage?.rawValue ?? "None"
        let text = """
        OpenCode Connect Diagnostics
        App: \(context.metadata.appVersion)
        OS: \(context.metadata.osVersion)
        OpenCode: \(context.openCodeVersion) (\(context.openCodePath))
        Tailscale: \(context.tailscaleVersion) (\(context.tailscalePath))
        Desired State: \(desired)
        Observed State: \(observed)
        Failure Stage: \(stage)
        Route Target: \(context.routeTarget)
        Component Health:
        \(componentLines)
        Recent Lifecycle Events:
        \(events)
        """
        return DiagnosticsReview(
            warning: "Review before copying: local paths may be sensitive.",
            text: text
        )
    }

    private func append(_ entry: String) {
        entries.append(String(entry.prefix(maximumEntryLength)))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    private func sanitize(_ value: String, sensitiveValues: [String]) -> String {
        var sanitized = value
        for sensitiveValue in sensitiveValues where !sensitiveValue.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: sensitiveValue, with: "[REDACTED]")
        }
        let patterns = [
            #"(?im)authorization\s*:\s*[^\r\n]+"#,
            #"(?im)(opencode_server_password|qr_payload|complete_env|environment)\s*[:=]\s*[^\r\n]+"#,
        ]
        for pattern in patterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: .regularExpression
            )
        }
        return sanitized
    }
}

public struct DiagnosticsCommandRunner: CommandRunning {
    private let base: any CommandRunning
    private let diagnostics: LocalDiagnostics

    public init(base: any CommandRunning, diagnostics: LocalDiagnostics) {
        self.base = base
        self.diagnostics = diagnostics
    }

    public func run(_ request: CommandRequest) async -> CommandResult {
        let result = await base.run(request)
        await diagnostics.recordCommandOutput(
            result.standardOutput + "\n" + result.standardError,
            sensitiveValues: Array(request.environment.values)
        )
        return result
    }
}

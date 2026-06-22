import Foundation
import Observation

public enum DesiredState: Equatable, Sendable {
    case disabled
    case enabled
}

public protocol DesiredStatePersisting: Sendable {
    func load() -> DesiredState
    func save(_ desiredState: DesiredState) async
}

public struct NoopDesiredStateStore: DesiredStatePersisting {
    public init() {}
    public func load() -> DesiredState { .disabled }
    public func save(_ desiredState: DesiredState) async {}
}

public enum ObservedState: Equatable, Sendable {
    case stopped
    case needsSetup
    case starting
    case available
    case degraded
    case stopping
    case conflict
    case error
}

public enum PrimaryAction: Equatable, Sendable {
    case start
    case stop
    case retry
    case retryReadiness
    case retryConflict
    case completeTailscaleSetup(URL)
}

public enum FailureStage: String, Equatable, Sendable {
    case configuration
    case dependencies
    case credential
    case serverInspection
    case serverLaunch
    case localHealth
    case routeInspection
    case routeCreation
    case endpointDiscovery
    case endpointVerification
}

public struct ComponentReadiness: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case ready
        case needsSetup
    }

    public let name: String
    public let status: Status
    public let detail: String

    public init(name: String, status: Status, detail: String) {
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public struct EnrollmentViewState: Equatable, Sendable {
    public let endpoint: URL?
    public let qrPayload: String?
    public let username: String?
    public let revealedCredential: String?
    public let endpointChangeWarning: String?
    public let guidance: [String]

    public static let unavailable = EnrollmentViewState(
        endpoint: nil,
        qrPayload: nil,
        username: nil,
        revealedCredential: nil,
        endpointChangeWarning: nil,
        guidance: []
    )

    public init(
        endpoint: URL?,
        qrPayload: String?,
        username: String?,
        revealedCredential: String? = nil,
        endpointChangeWarning: String? = nil,
        guidance: [String] = []
    ) {
        self.endpoint = endpoint
        self.qrPayload = qrPayload
        self.username = username
        self.revealedCredential = revealedCredential
        self.endpointChangeWarning = endpointChangeWarning
        self.guidance = guidance
    }
}

public struct AccessViewModel: Equatable, Sendable {
    public let desiredState: DesiredState
    public let observedState: ObservedState
    public let explanation: String
    public let components: [ComponentReadiness]
    public let primaryAction: PrimaryAction
    public let endpoint: URL?
    public let enrollment: EnrollmentViewState
    public let failedStage: FailureStage?
    public let remediation: String?
    public let diagnosticsReview: DiagnosticsReview?
    public let availabilityWarning: String?

    public init(
        desiredState: DesiredState,
        observedState: ObservedState,
        explanation: String,
        components: [ComponentReadiness],
        primaryAction: PrimaryAction,
        endpoint: URL? = nil,
        enrollment: EnrollmentViewState = .unavailable,
        failedStage: FailureStage? = nil,
        remediation: String? = nil,
        diagnosticsReview: DiagnosticsReview? = nil,
        availabilityWarning: String? = nil
    ) {
        self.desiredState = desiredState
        self.observedState = observedState
        self.explanation = explanation
        self.components = components
        self.primaryAction = primaryAction
        self.endpoint = endpoint
        self.enrollment = enrollment
        self.failedStage = failedStage
        self.remediation = remediation
        self.diagnosticsReview = diagnosticsReview
        self.availabilityWarning = availabilityWarning
    }
}

public struct ManagedServerConfiguration: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL

    public init(executablePath: String, arguments: [String], environment: [String: String], workingDirectory: URL) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

public enum AccessMode: String, CaseIterable, Equatable, Sendable {
    case protected
    case tailnetOnly
}

public enum AvailabilityPolicy: String, CaseIterable, Equatable, Sendable {
    case onExternalPower
    case always
    case never
}

public enum PowerSource: Equatable, Sendable { case external, battery }

public protocol PowerAssertionControlling: Sendable {
    func currentSource() async -> PowerSource
    func setIdleSleepPreventionRequired(_ required: Bool) async throws
}

public actor NoopPowerAssertionController: PowerAssertionControlling {
    public init() {}
    public func currentSource() async -> PowerSource { .external }
    public func setIdleSleepPreventionRequired(_ required: Bool) async throws {}
}

public protocol LaunchAtLoginControlling: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) async throws
}

public struct NoopLaunchAtLoginController: LaunchAtLoginControlling {
    public init() {}
    public func isEnabled() -> Bool { false }
    public func setEnabled(_ enabled: Bool) async throws {}
}

public enum AccessAuthentication: Equatable, Sendable {
    case basic(username: String, credential: String)
    case none
}

public protocol AccessCredentialStoring: Sendable {
    func load() async throws -> String?
    func save(_ credential: String) async throws
    func delete() async throws
}

public protocol PassphraseGenerating: Sendable { func generate() throws -> String }

public protocol ManagedServerControlling: Sendable {
    /// Returns true when this call created the Managed Server.
    func launch(_ configuration: ManagedServerConfiguration) async throws -> Bool
    func runtimeRecord() async throws -> ManagedServerRecord?
    func inspect(
        record: ManagedServerRecord?,
        expectedConfiguration: ManagedServerConfiguration,
        authentication: AccessAuthentication
    ) async -> ManagedServerInspection
    func verifyLocalHealth(authentication: AccessAuthentication) async throws
    func stopGracefully(timeout: Duration) async -> Bool
    func ownershipIsVerified() async -> Bool
    func forceStop() async
}

public extension ManagedServerControlling {
    func inspect(
        record: ManagedServerRecord?,
        expectedConfiguration: ManagedServerConfiguration,
        authentication: AccessAuthentication
    ) async -> ManagedServerInspection { .missing }
}

public enum ManagedRouteInspection: Equatable, Sendable { case available, matching, occupied }

public protocol ManagedRouteControlling: Sendable {
    func configure(tailscalePath: String) async
    func inspect(httpsPort: Int, backendPort: Int) async throws -> ManagedRouteInspection
    func create(tailscalePath: String, httpsPort: Int, backendPort: Int) async throws
    func discoverEndpoint(httpsPort: Int) async throws -> URL
    func verifyEndpoint(_ endpoint: URL, authentication: AccessAuthentication) async throws
    func removeIfMatching(httpsPort: Int, backendPort: Int) async throws
}

public extension ManagedRouteControlling {
    func configure(tailscalePath: String) async {}
}

public struct DependencySettings: Equatable, Sendable {
    public var customOpenCodePath: String?
    public var customTailscalePath: String?
    public var accessUsername: String
    public var accessMode: AccessMode
    public var backendPort: Int
    public var httpsPort: Int
    public var availabilityPolicy: AvailabilityPolicy

    public init(
        customOpenCodePath: String? = nil,
        customTailscalePath: String? = nil,
        accessUsername: String = "opencode",
        accessMode: AccessMode = .protected,
        backendPort: Int = 4096,
        httpsPort: Int = 443,
        availabilityPolicy: AvailabilityPolicy = .onExternalPower
    ) {
        self.customOpenCodePath = customOpenCodePath
        self.customTailscalePath = customTailscalePath
        self.accessUsername = accessUsername
        self.accessMode = accessMode
        self.backendPort = backendPort
        self.httpsPort = httpsPort
        self.availabilityPolicy = availabilityPolicy
    }
}

public struct SettingsViewModel: Equatable, Sendable {
    public let accessMode: AccessMode
    public let accessUsername: String
    public let tailnetOnlyWarningPending: Bool
    public let backendPort: Int
    public let httpsPort: Int
    public let availabilityPolicy: AvailabilityPolicy
    public let launchAtLogin: Bool
    public let message: String?

    public init(
        accessMode: AccessMode,
        accessUsername: String,
        tailnetOnlyWarningPending: Bool = false,
        backendPort: Int = 4096,
        httpsPort: Int = 443,
        availabilityPolicy: AvailabilityPolicy = .onExternalPower,
        launchAtLogin: Bool = false,
        message: String? = nil
    ) {
        self.accessMode = accessMode
        self.accessUsername = accessUsername
        self.tailnetOnlyWarningPending = tailnetOnlyWarningPending
        self.backendPort = backendPort
        self.httpsPort = httpsPort
        self.availabilityPolicy = availabilityPolicy
        self.launchAtLogin = launchAtLogin
        self.message = message
    }
}

public enum DependencyReadiness: Equatable, Sendable {
    case ready(version: String, executablePath: String)
    case missing
    case invalidCustomPath(path: String, reason: String)
    case disconnected
    case signedOut
    case serveApprovalRequired(URL)
    case serveUnavailable(String)
    case unavailable(String)
}

public struct ReadinessEvaluation: Equatable, Sendable {
    public let openCode: DependencyReadiness
    public let tailscale: DependencyReadiness

    public init(openCode: DependencyReadiness, tailscale: DependencyReadiness) {
        self.openCode = openCode
        self.tailscale = tailscale
    }
}

public protocol DependencyReadinessChecking: Sendable {
    func evaluate(settings: DependencySettings) async -> ReadinessEvaluation
}

public protocol ExternalURLOpening: Sendable {
    func open(_ url: URL) async
}

public protocol ClipboardWriting: Sendable {
    func write(_ value: String) async
}

public protocol LastVerifiedEndpointPersisting: Sendable {
    func load() async -> URL?
    func save(_ endpoint: URL) async
}

public protocol RetryScheduling: Sendable {
    func sleep(for duration: Duration) async
}

public protocol UserNotifying: Sendable {
    func notifyFailure(state: ObservedState, explanation: String) async
}

public struct NoopUserNotifier: UserNotifying {
    public init() {}
    public func notifyFailure(state: ObservedState, explanation: String) async {}
}

public struct SystemRetryScheduler: RetryScheduling {
    public init() {}

    public func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

public struct RetryPolicy: Equatable, Sendable {
    public let maximumAttempts: Int
    public let delays: [Duration]

    public init(maximumAttempts: Int = 3, delays: [Duration] = [.seconds(1), .seconds(2)]) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.delays = delays
    }

    func delay(afterAttempt attemptIndex: Int) -> Duration? {
        guard attemptIndex < maximumAttempts - 1, attemptIndex < delays.count else { return nil }
        return delays[attemptIndex]
    }
}

public protocol DependencySettingsPersisting: Sendable {
    func save(_ settings: DependencySettings) async
}

public struct NoopDependencySettingsStore: DependencySettingsPersisting {
    public init() {}
    public func save(_ settings: DependencySettings) async {}
}

public struct NoopURLOpener: ExternalURLOpening {
    public init() {}
    public func open(_ url: URL) async {}
}

public struct NoopClipboard: ClipboardWriting {
    public init() {}
    public func write(_ value: String) async {}
}

public struct NoopLastVerifiedEndpointStore: LastVerifiedEndpointPersisting {
    public init() {}
    public func load() async -> URL? { nil }
    public func save(_ endpoint: URL) async {}
}

public enum AccessEvent: Sendable {
    case login
    case sleep
    case wake
    case logoutOrShutdown
    case reconcile
    case checkHealth
    case retry
    case retryConflict
    case evaluateReadiness
    case selectCustomOpenCodePath(String)
    case selectCustomTailscalePath(String)
    case completeTailscaleSetup
    case openEndpoint
    case copyEndpoint
    case revealCredential
    case copyCredential
    case reviewDiagnostics
    case copyDiagnostics
    case requestAccessMode(AccessMode)
    case confirmTailnetOnlyAccess
    case updatePorts(backend: Int, https: Int)
    case updateUsername(String)
    case rotateCredential
    case deleteCredential
    case updateAvailabilityPolicy(AvailabilityPolicy)
    case updateLaunchAtLogin(Bool)
    case powerSourceChanged
    case resetToDefaults
    case start
    case stop
    case quit
}

@MainActor
@Observable
public final class AccessCoordinator {
    public private(set) var viewModel = AccessViewModel(
        desiredState: .disabled,
        observedState: .needsSetup,
        explanation: "Checking dependencies…",
        components: [],
        primaryAction: .retryReadiness
    )
    public private(set) var settingsViewModel: SettingsViewModel

    @ObservationIgnored private let dependencies: any DependencyReadinessChecking
    @ObservationIgnored private let urlOpener: any ExternalURLOpening
    @ObservationIgnored private let clipboard: any ClipboardWriting
    @ObservationIgnored private let endpointStore: any LastVerifiedEndpointPersisting
    @ObservationIgnored private let settingsStore: any DependencySettingsPersisting
    @ObservationIgnored private var settings: DependencySettings
    @ObservationIgnored private var pendingApprovalURL: URL?
    @ObservationIgnored private let credentialStore: (any AccessCredentialStoring)?
    @ObservationIgnored private let passphraseGenerator: (any PassphraseGenerating)?
    @ObservationIgnored private let server: (any ManagedServerControlling)?
    @ObservationIgnored private let route: (any ManagedRouteControlling)?
    @ObservationIgnored private let runtimeRecordStore: any ManagedServerRecordStoring
    @ObservationIgnored private let desiredStateStore: any DesiredStatePersisting
    @ObservationIgnored private let retryScheduler: any RetryScheduling
    @ObservationIgnored private let retryPolicy: RetryPolicy
    @ObservationIgnored private let notifier: any UserNotifying
    @ObservationIgnored private let diagnostics: LocalDiagnostics
    @ObservationIgnored private let diagnosticsMetadata: DiagnosticsMetadata
    @ObservationIgnored private var automaticRetriesExhausted = false
    @ObservationIgnored private let homeDirectory: URL
    @ObservationIgnored private let loginItem: any LaunchAtLoginControlling
    @ObservationIgnored private var launchAtLoginEnabled: Bool
    @ObservationIgnored private let power: any PowerAssertionControlling
    @ObservationIgnored private var eventTail: Task<Void, Never>?
    @ObservationIgnored private var eventSequence = 0

    public init(
        dependencies: any DependencyReadinessChecking,
        initialDesiredState: DesiredState = .disabled,
        urlOpener: any ExternalURLOpening = NoopURLOpener(),
        clipboard: any ClipboardWriting = NoopClipboard(),
        endpointStore: any LastVerifiedEndpointPersisting = NoopLastVerifiedEndpointStore(),
        settingsStore: any DependencySettingsPersisting = NoopDependencySettingsStore(),
        settings: DependencySettings = DependencySettings(),
        credentialStore: (any AccessCredentialStoring)? = nil,
        passphraseGenerator: (any PassphraseGenerating)? = nil,
        server: (any ManagedServerControlling)? = nil,
        route: (any ManagedRouteControlling)? = nil,
        runtimeRecordStore: any ManagedServerRecordStoring = NoopManagedServerRecordStore(),
        desiredStateStore: any DesiredStatePersisting = NoopDesiredStateStore(),
        retryScheduler: any RetryScheduling = SystemRetryScheduler(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        notifier: any UserNotifying = NoopUserNotifier(),
        diagnostics: LocalDiagnostics = LocalDiagnostics(),
        diagnosticsMetadata: DiagnosticsMetadata = .current,
        loginItem: any LaunchAtLoginControlling = NoopLaunchAtLoginController(),
        power: any PowerAssertionControlling = NoopPowerAssertionController(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.dependencies = dependencies
        self.urlOpener = urlOpener
        self.clipboard = clipboard
        self.endpointStore = endpointStore
        self.settingsStore = settingsStore
        self.settings = settings
        self.credentialStore = credentialStore
        self.passphraseGenerator = passphraseGenerator
        self.server = server
        self.route = route
        self.runtimeRecordStore = runtimeRecordStore
        self.desiredStateStore = desiredStateStore
        self.retryScheduler = retryScheduler
        self.retryPolicy = retryPolicy
        self.notifier = notifier
        self.diagnostics = diagnostics
        self.diagnosticsMetadata = diagnosticsMetadata
        self.homeDirectory = homeDirectory
        self.loginItem = loginItem
        self.launchAtLoginEnabled = loginItem.isEnabled()
        self.power = power
        self.settingsViewModel = SettingsViewModel(
            accessMode: settings.accessMode,
            accessUsername: settings.accessUsername,
            backendPort: settings.backendPort,
            httpsPort: settings.httpsPort,
            availabilityPolicy: settings.availabilityPolicy,
            launchAtLogin: launchAtLoginEnabled
        )
        self.viewModel = AccessViewModel(
            desiredState: initialDesiredState,
            observedState: initialDesiredState == .enabled ? .starting : .needsSetup,
            explanation: initialDesiredState == .enabled ? "Reconnecting private access…" : "Checking dependencies…",
            components: [],
            primaryAction: initialDesiredState == .enabled ? .stop : .retryReadiness
        )
    }

    public func handle(_ event: AccessEvent) async {
        eventSequence += 1
        let sequence = eventSequence
        let previous = eventTail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await self.process(event)
        }
        eventTail = task
        await task.value
        if eventSequence == sequence {
            eventTail = nil
        }
    }

    private func process(_ event: AccessEvent) async {
        switch event {
        case .logoutOrShutdown:
            guard !launchAtLoginEnabled else { return }
            await stop()
            return
        case .sleep:
            guard viewModel.desiredState == .enabled else { return }
            try? await power.setIdleSleepPreventionRequired(false)
            viewModel = AccessViewModel(
                desiredState: .enabled,
                observedState: .degraded,
                explanation: "The Mac is sleeping; Endpoint availability is not guaranteed.",
                components: viewModel.components.filter { $0.name != "Endpoint" },
                primaryAction: .stop,
                availabilityWarning: "Opening the Mac and waking it will trigger verified recovery."
            )
            return
        case .wake:
            guard viewModel.desiredState == .enabled else {
                await evaluateReadiness()
                return
            }
            automaticRetriesExhausted = false
            await start(recoveringRuntime: true)
            return
        case .login:
            if viewModel.desiredState == .enabled {
                await start()
            } else {
                await evaluateReadiness()
            }
            return
        case .reconcile:
            if viewModel.desiredState == .enabled {
                guard !automaticRetriesExhausted else { return }
                await start()
            } else {
                await evaluateReadiness()
            }
            return
        case .checkHealth:
            guard viewModel.desiredState == .enabled,
                  viewModel.observedState == .available || viewModel.observedState == .degraded
            else { return }
            await start(recoveringRuntime: true)
            return
        case .retry:
            guard viewModel.observedState == .error else { return }
            automaticRetriesExhausted = false
            await start(notifyFailure: true)
            return
        case .retryConflict:
            guard viewModel.observedState == .conflict else { return }
            if viewModel.desiredState == .enabled {
                await start(notifyFailure: true)
            } else {
                await stop()
            }
            return
        case .start:
            automaticRetriesExhausted = false
            await start(notifyFailure: true)
            return
        case .stop, .quit:
            if viewModel.observedState == .conflict {
                await disableIntentDuringConflict()
                return
            }
            await stop()
            return
        case .evaluateReadiness:
            guard viewModel.desiredState == .disabled else { return }
        case let .selectCustomOpenCodePath(path):
            guard viewModel.desiredState == .disabled else { return }
            var candidate = settings
            candidate.customOpenCodePath = path
            let evaluation = await dependencies.evaluate(settings: candidate)
            guard case .ready = evaluation.openCode else {
                publishSettings(message: "The selected OpenCode executable is invalid.")
                publishInvalidExecutableSelection(
                    dependency: "OpenCode",
                    readiness: evaluation.openCode,
                    other: evaluation.tailscale
                )
                return
            }
            settings = candidate
            await settingsStore.save(settings)
        case let .selectCustomTailscalePath(path):
            guard viewModel.desiredState == .disabled else { return }
            var candidate = settings
            candidate.customTailscalePath = path
            let evaluation = await dependencies.evaluate(settings: candidate)
            guard isValidTailscaleSelection(evaluation.tailscale) else {
                publishSettings(message: "The selected Tailscale executable is invalid.")
                publishInvalidExecutableSelection(
                    dependency: "Tailscale",
                    readiness: evaluation.tailscale,
                    other: evaluation.openCode
                )
                return
            }
            settings = candidate
            await settingsStore.save(settings)
        case .completeTailscaleSetup:
            if let pendingApprovalURL {
                await urlOpener.open(pendingApprovalURL)
            }
            return
        case .openEndpoint:
            if let endpoint = viewModel.enrollment.endpoint {
                await urlOpener.open(endpoint)
            }
            return
        case .copyEndpoint:
            if let endpoint = viewModel.enrollment.endpoint {
                await clipboard.write(endpoint.absoluteString)
            }
            return
        case .revealCredential:
            await revealCredential()
            return
        case .copyCredential:
            if settings.accessMode == .protected,
               viewModel.enrollment.endpoint != nil,
               let credentialStore,
               let credential = try? await credentialStore.load()
            {
                await clipboard.write(credential)
            }
            return
        case .reviewDiagnostics:
            await reviewDiagnostics()
            return
        case .copyDiagnostics:
            if let review = viewModel.diagnosticsReview {
                await clipboard.write(review.text)
            }
            return
        case let .requestAccessMode(mode):
            guard viewModel.desiredState == .disabled else { return }
            if mode == .tailnetOnly {
                settingsViewModel = SettingsViewModel(
                    accessMode: settings.accessMode,
                    accessUsername: settings.accessUsername,
                    tailnetOnlyWarningPending: true,
                    backendPort: settings.backendPort,
                    httpsPort: settings.httpsPort,
                    availabilityPolicy: settings.availabilityPolicy,
                    launchAtLogin: launchAtLoginEnabled,
                    message: "Tailnet-Only Access removes OpenCode Basic Auth. Tailnet policy becomes the only access check."
                )
            } else {
                settings.accessMode = .protected
                await settingsStore.save(settings)
                publishSettings()
            }
            return
        case .confirmTailnetOnlyAccess:
            guard viewModel.desiredState == .disabled,
                  settingsViewModel.tailnetOnlyWarningPending
            else { return }
            settings.accessMode = .tailnetOnly
            await settingsStore.save(settings)
            publishSettings(message: "Tailnet-Only Access enabled. OpenCode remains loopback-only.")
            return
        case let .updatePorts(backend, https):
            guard viewModel.desiredState == .disabled else { return }
            guard (1...65_535).contains(backend), (1...65_535).contains(https) else {
                publishSettings(message: "Backend and Serve HTTPS ports must be between 1 and 65535.")
                return
            }
            settings.backendPort = backend
            settings.httpsPort = https
            await settingsStore.save(settings)
            publishSettings()
            return
        case let .updateUsername(username):
            guard viewModel.desiredState == .disabled else { return }
            let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                publishSettings(message: "The Protected Access username must not be empty.")
                return
            }
            settings.accessUsername = normalized
            await settingsStore.save(settings)
            publishSettings()
            return
        case .rotateCredential:
            guard viewModel.desiredState == .disabled,
                  let credentialStore,
                  let passphraseGenerator
            else { return }
            do {
                try await credentialStore.save(passphraseGenerator.generate())
                publishSettings(
                    message: "Access Credential rotated. Update the saved login on your iPhone."
                )
            } catch {
                publishSettings(message: "The Access Credential could not be rotated.")
            }
            return
        case .deleteCredential:
            guard viewModel.desiredState == .disabled, let credentialStore else { return }
            do {
                try await credentialStore.delete()
                publishSettings(message: "The Access Credential was deleted.")
            } catch {
                publishSettings(message: "The Access Credential could not be deleted.")
            }
            return
        case let .updateAvailabilityPolicy(policy):
            settings.availabilityPolicy = policy
            await settingsStore.save(settings)
            publishSettings()
            await reconcilePowerAssertion()
            return
        case let .updateLaunchAtLogin(enabled):
            do {
                try await loginItem.setEnabled(enabled)
                launchAtLoginEnabled = enabled
                publishSettings()
            } catch {
                publishSettings(message: "Launch at Login could not be changed.")
            }
            return
        case .powerSourceChanged:
            await reconcilePowerAssertion()
            return
        case .resetToDefaults:
            guard viewModel.desiredState == .disabled else { return }
            settings = DependencySettings()
            await settingsStore.save(settings)
            publishSettings(message: "Settings were reset to defaults.")
            return
        }
        await evaluateReadiness()
    }

    private func evaluateReadiness() async {
        let evaluation = await dependencies.evaluate(settings: settings)
        if case let .invalidCustomPath(path, reason) = evaluation.openCode {
            viewModel = AccessViewModel(
                desiredState: .disabled,
                observedState: .needsSetup,
                explanation: "The custom OpenCode path \(path) is invalid: \(reason.lowercased()). Choose an executable file.",
                components: [
                    ComponentReadiness(name: "OpenCode", status: .needsSetup, detail: "Invalid custom path"),
                    component(for: evaluation.tailscale, name: "Tailscale"),
                ],
                primaryAction: .retryReadiness
            )
            return
        }
        guard case let .ready(openCodeVersion, _) = evaluation.openCode else {
            viewModel = AccessViewModel(
                desiredState: .disabled,
                observedState: .needsSetup,
                explanation: "OpenCode was not found. Install OpenCode or choose its executable in Settings.",
                components: [
                    ComponentReadiness(name: "OpenCode", status: .needsSetup, detail: "Not found"),
                    component(for: evaluation.tailscale, name: "Tailscale"),
                ],
                primaryAction: .retryReadiness
            )
            return
        }
        if case let .invalidCustomPath(path, reason) = evaluation.tailscale {
            viewModel = AccessViewModel(
                desiredState: .disabled,
                observedState: .needsSetup,
                explanation: "The custom Tailscale path \(path) is invalid: \(reason.lowercased()). Choose an executable file.",
                components: [
                    component(for: evaluation.openCode, name: "OpenCode"),
                    ComponentReadiness(name: "Tailscale", status: .needsSetup, detail: "Invalid custom path"),
                ],
                primaryAction: .retryReadiness
            )
            return
        }
        if case .disconnected = evaluation.tailscale {
            viewModel = AccessViewModel(
                desiredState: .disabled,
                observedState: .needsSetup,
                explanation: "Tailscale is installed but disconnected. Connect it on this Mac and ensure it is installed, signed in, and connected on the iPhone.",
                components: [
                    component(for: evaluation.openCode, name: "OpenCode"),
                    ComponentReadiness(name: "Tailscale", status: .needsSetup, detail: "Disconnected"),
                ],
                primaryAction: .retryReadiness
            )
            return
        }
        if case .signedOut = evaluation.tailscale {
            viewModel = AccessViewModel(
                desiredState: .disabled,
                observedState: .needsSetup,
                explanation: "Tailscale is signed out. Sign in and connect on this Mac, then retry readiness.",
                components: [
                    component(for: evaluation.openCode, name: "OpenCode"),
                    ComponentReadiness(name: "Tailscale", status: .needsSetup, detail: "Signed out"),
                ],
                primaryAction: .retryReadiness
            )
            return
        }
        if case let .serveApprovalRequired(url) = evaluation.tailscale {
            pendingApprovalURL = url
            viewModel = AccessViewModel(
                desiredState: .disabled,
                observedState: .needsSetup,
                explanation: "Tailscale requires one-time Serve HTTPS approval. Complete setup explicitly, then retry readiness.",
                components: [
                    component(for: evaluation.openCode, name: "OpenCode"),
                    ComponentReadiness(name: "Tailscale", status: .needsSetup, detail: "HTTPS approval required"),
                ],
                primaryAction: .completeTailscaleSetup(url)
            )
            return
        }
        if case let .serveUnavailable(reason) = evaluation.tailscale {
            viewModel = AccessViewModel(
                desiredState: .disabled,
                observedState: .needsSetup,
                explanation: "Tailscale Serve HTTPS is unavailable: \(reason). Update or configure Tailscale, then retry readiness.",
                components: [
                    component(for: evaluation.openCode, name: "OpenCode"),
                    ComponentReadiness(name: "Tailscale", status: .needsSetup, detail: "Serve HTTPS unavailable"),
                ],
                primaryAction: .retryReadiness
            )
            return
        }
        if case let .unavailable(reason) = evaluation.tailscale {
            viewModel = AccessViewModel(
                desiredState: .disabled,
                observedState: .needsSetup,
                explanation: "Tailscale could not be validated: \(reason). Check the installation and retry readiness.",
                components: [
                    component(for: evaluation.openCode, name: "OpenCode"),
                    ComponentReadiness(name: "Tailscale", status: .needsSetup, detail: "Validation failed"),
                ],
                primaryAction: .retryReadiness
            )
            return
        }
        guard case let .ready(tailscaleVersion, _) = evaluation.tailscale else {
            viewModel = AccessViewModel(
                desiredState: .disabled,
                observedState: .needsSetup,
                explanation: "Tailscale was not found. Install, sign in, and connect Tailscale on this Mac and on the iPhone.",
                components: [
                    component(for: evaluation.openCode, name: "OpenCode"),
                    ComponentReadiness(name: "Tailscale", status: .needsSetup, detail: "Not found"),
                ],
                primaryAction: .retryReadiness
            )
            return
        }
        viewModel = AccessViewModel(
            desiredState: .disabled,
            observedState: .stopped,
            explanation: "OpenCode Connect is ready to start private access.",
            components: [
                ComponentReadiness(name: "OpenCode", status: .ready, detail: openCodeVersion),
                ComponentReadiness(name: "Tailscale", status: .ready, detail: tailscaleVersion),
            ],
            primaryAction: .start
        )
    }

    private func start(recoveringRuntime: Bool = false, notifyFailure: Bool = false) async {
        await diagnostics.recordLifecycle(recoveringRuntime ? "Runtime recovery started" : "Start requested")
        await desiredStateStore.save(.enabled)
        let modeName = settings.accessMode == .protected ? "protected" : "tailnet-only"
        viewModel = AccessViewModel(
            desiredState: .enabled, observedState: .starting,
            explanation: "Starting \(modeName) access…", components: viewModel.components,
            primaryAction: .stop,
            endpoint: recoveringRuntime ? viewModel.endpoint : nil,
            enrollment: recoveringRuntime ? viewModel.enrollment : .unavailable
        )
        guard let server, let route else {
            await publishError("Access lifecycle adapters are unavailable.", notify: notifyFailure)
            return
        }
        let username = settings.accessUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.accessMode != .protected || !username.isEmpty else {
            await publishError("The Protected Access username must not be empty.", notify: notifyFailure)
            return
        }
        let evaluation = await dependencies.evaluate(settings: settings)
        guard case let .ready(openCodeVersion, openCodePath) = evaluation.openCode,
              case let .ready(tailscaleVersion, tailscalePath) = evaluation.tailscale
        else {
            await publishError("Dependencies are not ready.", stage: .dependencies, notify: notifyFailure)
            return
        }
        for attemptIndex in 0..<retryPolicy.maximumAttempts {
            var createdServer = false
            var createdRoute = false
            var failedStage = FailureStage.credential
            var sensitiveValues: [String] = []
            do {
            let authentication: AccessAuthentication
            let environment: [String: String]
            switch settings.accessMode {
            case .protected:
                guard let credentialStore, let passphraseGenerator else {
                    throw AccessLifecycleError.credentialInfrastructureUnavailable
                }
                let credential: String
                if let existing = try await credentialStore.load() {
                    credential = existing
                } else {
                    credential = try passphraseGenerator.generate()
                    try await credentialStore.save(credential)
                }
                authentication = .basic(username: username, credential: credential)
                sensitiveValues = [username, credential]
                environment = [
                    "OPENCODE_SERVER_USERNAME": username,
                    "OPENCODE_SERVER_PASSWORD": credential,
                ]
            case .tailnetOnly:
                authentication = .none
                environment = [:]
            }
            let configuration = ManagedServerConfiguration(
                executablePath: openCodePath,
                arguments: ["serve", "--hostname", "127.0.0.1", "--port", "\(settings.backendPort)"],
                environment: environment,
                workingDirectory: homeDirectory
            )
            await route.configure(tailscalePath: tailscalePath)
            failedStage = .routeInspection
            let routeInspection = try await route.inspect(
                httpsPort: settings.httpsPort,
                backendPort: settings.backendPort
            )
            if routeInspection == .occupied {
                await publishConflict(
                    "The Tailscale HTTPS listener or root route has a different target. " +
                    "OpenCode Connect will not replace or remove it automatically.",
                    notify: notifyFailure
                )
                return
            }
            failedStage = .serverInspection
            switch await server.inspect(
                record: try await runtimeRecordStore.load(),
                expectedConfiguration: configuration,
                authentication: authentication
            ) {
            case .missing:
                failedStage = .serverLaunch
                createdServer = try await server.launch(configuration)
                if createdServer, let record = try await server.runtimeRecord() {
                    try await runtimeRecordStore.save(record)
                }
                failedStage = .localHealth
                try await server.verifyLocalHealth(authentication: authentication)
            case .verified:
                failedStage = .localHealth
                try await server.verifyLocalHealth(authentication: authentication)
            case let .conflict(evidence):
                await publishConflict(evidence, notify: notifyFailure)
                return
            }
            switch routeInspection {
            case .available:
                createdRoute = true
                failedStage = .routeCreation
                try await route.create(
                    tailscalePath: tailscalePath,
                    httpsPort: settings.httpsPort,
                    backendPort: settings.backendPort
                )
            case .matching:
                break
            case .occupied:
                return
            }
            failedStage = .endpointDiscovery
            let endpoint = try await route.discoverEndpoint(httpsPort: settings.httpsPort)
            let enrollment = try await enrollmentState(for: endpoint, username: username)
            failedStage = .endpointVerification
            try await route.verifyEndpoint(endpoint, authentication: authentication)
            await endpointStore.save(endpoint)
            viewModel = AccessViewModel(
                desiredState: .enabled, observedState: .available,
                explanation: settings.accessMode == .protected
                    ? "Protected access is available."
                    : "Tailnet-only access is available.",
                components: [
                    ComponentReadiness(name: "OpenCode", status: .ready, detail: openCodeVersion),
                    ComponentReadiness(name: "Tailscale", status: .ready, detail: tailscaleVersion),
                    ComponentReadiness(name: "Endpoint", status: .ready, detail: endpoint.absoluteString),
                    ComponentReadiness(name: "Keep Awake", status: .ready, detail: keepAwakeDetail),
                ],
                primaryAction: .stop,
                endpoint: endpoint,
                enrollment: enrollment
            )
                await reconcilePowerAssertion()
                await diagnostics.recordLifecycle("Access became Available")
                return
            } catch {
                if createdRoute {
                    try? await route.removeIfMatching(
                        httpsPort: settings.httpsPort,
                        backendPort: settings.backendPort
                    )
                }
                if createdServer {
                    _ = await server.stopGracefully(timeout: .seconds(5))
                    try? await runtimeRecordStore.clear()
                }
                if isTransient(error: error, at: failedStage),
                   let delay = retryPolicy.delay(afterAttempt: attemptIndex)
                {
                    if recoveringRuntime {
                        publishDegraded(stage: failedStage)
                    }
                    await retryScheduler.sleep(for: delay)
                    continue
                }
                automaticRetriesExhausted = true
                let sanitizedError = await diagnostics.sanitizedText(
                    error.localizedDescription,
                    sensitiveValues: sensitiveValues
                )
                await publishError(
                    "Protected access failed to start during \(failedStage.rawValue): \(sanitizedError)",
                    stage: failedStage,
                    remediation: "Retry to run a fresh ownership-safe reconciliation, or Stop to disable access.",
                    notify: notifyFailure
                )
                return
            }
        }
    }

    private func stop() async {
        await desiredStateStore.save(.disabled)
        guard let server, let route else {
            viewModel = stoppedViewModel()
            await reconcilePowerAssertion()
            return
        }
        let routeInspection: ManagedRouteInspection
        do {
            routeInspection = try await route.inspect(
                httpsPort: settings.httpsPort,
                backendPort: settings.backendPort
            )
        } catch {
            await publishConflict("The Managed Route could not be verified for safe cleanup.", desiredState: .disabled)
            return
        }
        guard routeInspection != .occupied else {
            await publishConflict(
                "The Tailscale HTTPS listener or root route changed to a different target. No cleanup was performed.",
                desiredState: .disabled
            )
            return
        }
        guard await server.ownershipIsVerified() else {
            await publishConflict(
                "The Managed Server identity no longer matches its runtime record. No cleanup was performed.",
                desiredState: .disabled
            )
            return
        }
        viewModel = AccessViewModel(
            desiredState: .disabled, observedState: .stopping,
            explanation: "Stopping protected access…", components: viewModel.components,
            primaryAction: .stop, endpoint: viewModel.endpoint
        )
        try? await route.removeIfMatching(
            httpsPort: settings.httpsPort,
            backendPort: settings.backendPort
        )
        if !(await server.stopGracefully(timeout: .seconds(5))) {
            guard await server.ownershipIsVerified() else {
                await publishConflict(
                    "The Managed Server identity changed while stopping. Forced termination was blocked.",
                    desiredState: .disabled
                )
                return
            }
            await server.forceStop()
        }
        try? await runtimeRecordStore.clear()
        viewModel = stoppedViewModel()
        await reconcilePowerAssertion()
    }

    private func disableIntentDuringConflict() async {
        await desiredStateStore.save(.disabled)
        viewModel = AccessViewModel(
            desiredState: .disabled,
            observedState: .conflict,
            explanation: viewModel.explanation,
            components: viewModel.components,
            primaryAction: .retryConflict,
            endpoint: viewModel.endpoint,
            enrollment: viewModel.enrollment,
            failedStage: viewModel.failedStage,
            remediation: viewModel.remediation,
            diagnosticsReview: viewModel.diagnosticsReview,
            availabilityWarning: viewModel.availabilityWarning
        )
        await reconcilePowerAssertion()
        await diagnostics.recordLifecycle("Access disabled; Conflict cleanup deferred")
    }

    private func stoppedViewModel() -> AccessViewModel {
        AccessViewModel(
            desiredState: .disabled, observedState: .stopped,
            explanation: "OpenCode Connect is ready to start private access.",
            components: viewModel.components.filter { $0.name != "Endpoint" }, primaryAction: .start
        )
    }

    private var keepAwakeDetail: String {
        switch settings.availabilityPolicy {
        case .onExternalPower: "On external power"
        case .always: "Always requested"
        case .never: "Not requested"
        }
    }

    private func reconcilePowerAssertion() async {
        let source = await power.currentSource()
        let active = viewModel.desiredState == .enabled && viewModel.observedState == .available
        let policyRequiresAssertion = switch settings.availabilityPolicy {
        case .always: true
        case .onExternalPower: source == .external
        case .never: false
        }
        let required = active && policyRequiresAssertion
        let assertionFailure: String?
        do {
            try await power.setIdleSleepPreventionRequired(required)
            assertionFailure = nil
        } catch {
            assertionFailure = error.localizedDescription
        }
        let assertionUnavailable = required && assertionFailure != nil
        let observedState = assertionUnavailable && viewModel.observedState == .available
            ? ObservedState.degraded
            : viewModel.observedState
        let warning: String?
        if let assertionFailure {
            warning = required
                ? "The Mac could not be kept awake: \(assertionFailure)"
                : "The idle-sleep assertion could not be released: \(assertionFailure)"
        } else if active && source == .battery && !required {
            warning = "The Mac is on battery power and may become unavailable when it sleeps."
        } else {
            warning = nil
        }
        viewModel = AccessViewModel(
            desiredState: viewModel.desiredState,
            observedState: observedState,
            explanation: assertionUnavailable
                ? "Access is available, but idle-sleep prevention could not be enabled."
                : viewModel.explanation,
            components: viewModel.components.map { component in
                guard component.name == "Keep Awake", assertionUnavailable else { return component }
                return ComponentReadiness(name: component.name, status: .needsSetup, detail: "Assertion unavailable")
            },
            primaryAction: viewModel.primaryAction,
            endpoint: viewModel.endpoint,
            enrollment: viewModel.enrollment,
            failedStage: viewModel.failedStage,
            remediation: viewModel.remediation,
            diagnosticsReview: viewModel.diagnosticsReview,
            availabilityWarning: warning
        )
    }

    private func isTransient(error: Error, at stage: FailureStage) -> Bool {
        if error is AccessLifecycleError { return false }
        return switch stage {
        case .serverLaunch, .localHealth, .routeInspection, .routeCreation,
             .endpointDiscovery, .endpointVerification:
            true
        case .configuration, .dependencies, .credential, .serverInspection:
            false
        }
    }

    private func enrollmentState(for endpoint: URL, username: String) async throws -> EnrollmentViewState {
        guard endpoint.scheme?.lowercased() == "https",
              endpoint.host != nil,
              endpoint.user == nil,
              endpoint.password == nil,
              endpoint.query == nil,
              endpoint.fragment == nil
        else {
            throw AccessLifecycleError.unsafeEndpoint
        }
        let previousEndpoint = await endpointStore.load()
        let warning = previousEndpoint.flatMap { previous in
            previous == endpoint
                ? nil
                : "The Endpoint changed. An existing iPhone bookmark may be stale."
        }
        return EnrollmentViewState(
            endpoint: endpoint,
            qrPayload: endpoint.absoluteString,
            username: settings.accessMode == .protected ? username : nil,
            endpointChangeWarning: warning,
            guidance: [
                "Ensure Tailscale is connected on the iPhone.",
                "Scan the QR code to open the Endpoint in Safari.",
                "Enter the username and six-word passphrase once.",
                "Allow Safari and iCloud Passwords to save the login.",
                "Idle-sleep prevention does not keep a closed-lid MacBook available.",
            ]
        )
    }

    private func revealCredential() async {
        guard settings.accessMode == .protected,
              viewModel.enrollment.endpoint != nil,
              let credentialStore,
              let credential = try? await credentialStore.load()
        else { return }
        let enrollment = viewModel.enrollment
        viewModel = AccessViewModel(
            desiredState: viewModel.desiredState,
            observedState: viewModel.observedState,
            explanation: viewModel.explanation,
            components: viewModel.components,
            primaryAction: viewModel.primaryAction,
            endpoint: viewModel.endpoint,
            enrollment: EnrollmentViewState(
                endpoint: enrollment.endpoint,
                qrPayload: enrollment.qrPayload,
                username: enrollment.username,
                revealedCredential: credential,
                endpointChangeWarning: enrollment.endpointChangeWarning,
                guidance: enrollment.guidance
            )
        )
    }

    private func reviewDiagnostics() async {
        let evaluation = await dependencies.evaluate(settings: settings)
        let openCode: (String, String)
        if case let .ready(version, path) = evaluation.openCode {
            openCode = (version, path)
        } else {
            openCode = ("Unavailable", settings.customOpenCodePath ?? "Not detected")
        }
        let tailscale: (String, String)
        if case let .ready(version, path) = evaluation.tailscale {
            tailscale = (version, path)
        } else {
            tailscale = ("Unavailable", settings.customTailscalePath ?? "Not detected")
        }
        let review = await diagnostics.makeReview(context: DiagnosticsContext(
            metadata: diagnosticsMetadata,
            openCodeVersion: openCode.0,
            openCodePath: openCode.1,
            tailscaleVersion: tailscale.0,
            tailscalePath: tailscale.1,
            desiredState: viewModel.desiredState,
            observedState: viewModel.observedState,
            components: viewModel.components,
            routeTarget: "https:\(settings.httpsPort) -> http://127.0.0.1:\(settings.backendPort)",
            failureStage: viewModel.failedStage
        ))
        viewModel = AccessViewModel(
            desiredState: viewModel.desiredState,
            observedState: viewModel.observedState,
            explanation: viewModel.explanation,
            components: viewModel.components,
            primaryAction: viewModel.primaryAction,
            endpoint: viewModel.endpoint,
            enrollment: viewModel.enrollment,
            failedStage: viewModel.failedStage,
            remediation: viewModel.remediation,
            diagnosticsReview: review,
            availabilityWarning: viewModel.availabilityWarning
        )
    }

    private func publishSettings(message: String? = nil) {
        settingsViewModel = SettingsViewModel(
            accessMode: settings.accessMode,
            accessUsername: settings.accessUsername,
            backendPort: settings.backendPort,
            httpsPort: settings.httpsPort,
            availabilityPolicy: settings.availabilityPolicy,
            launchAtLogin: launchAtLoginEnabled,
            message: message
        )
    }

    private func isValidTailscaleSelection(_ readiness: DependencyReadiness) -> Bool {
        switch readiness {
        case .missing, .invalidCustomPath:
            false
        case .ready, .disconnected, .signedOut, .serveApprovalRequired, .serveUnavailable, .unavailable:
            true
        }
    }

    private func publishInvalidExecutableSelection(
        dependency: String,
        readiness: DependencyReadiness,
        other: DependencyReadiness
    ) {
        let detail: String
        if case let .invalidCustomPath(path, reason) = readiness {
            detail = "The custom \(dependency) path \(path) is invalid: \(reason.lowercased()). Choose an executable file."
        } else {
            detail = "The selected \(dependency) executable is invalid. Choose an executable file."
        }
        let otherName = dependency == "OpenCode" ? "Tailscale" : "OpenCode"
        viewModel = AccessViewModel(
            desiredState: .disabled,
            observedState: .needsSetup,
            explanation: detail,
            components: [
                ComponentReadiness(name: dependency, status: .needsSetup, detail: "Invalid custom path"),
                component(for: other, name: otherName),
            ],
            primaryAction: .retryReadiness
        )
    }

    private func publishError(
        _ explanation: String,
        stage: FailureStage = .configuration,
        remediation: String = "Retry after correcting the problem, or Stop to disable access.",
        notify: Bool = false
    ) async {
        viewModel = AccessViewModel(
            desiredState: .enabled, observedState: .error, explanation: explanation,
            components: viewModel.components, primaryAction: .retry,
            failedStage: stage, remediation: remediation
        )
        await reconcilePowerAssertion()
        await diagnostics.recordLifecycle("Error at \(stage.rawValue): \(explanation)")
        if notify { await notifier.notifyFailure(state: .error, explanation: explanation) }
    }

    private func publishDegraded(stage: FailureStage) {
        viewModel = AccessViewModel(
            desiredState: .enabled,
            observedState: .degraded,
            explanation: "Private access is temporarily unreachable while OpenCode Connect retries.",
            components: viewModel.components.map { component in
                component.name == "Endpoint"
                    ? ComponentReadiness(name: component.name, status: .needsSetup, detail: "Temporarily unreachable")
                    : component
            },
            primaryAction: .stop,
            endpoint: viewModel.endpoint,
            enrollment: viewModel.enrollment,
            failedStage: stage,
            remediation: "OpenCode Connect is retrying automatically. Stop to disable access."
        )
    }

    private func publishConflict(
        _ evidence: String,
        desiredState: DesiredState = .enabled,
        notify: Bool = false
    ) async {
        viewModel = AccessViewModel(
            desiredState: desiredState,
            observedState: .conflict,
            explanation: evidence,
            components: viewModel.components,
            primaryAction: .retryConflict
        )
        await reconcilePowerAssertion()
        await diagnostics.recordLifecycle("Conflict: \(evidence)")
        if notify { await notifier.notifyFailure(state: .conflict, explanation: evidence) }
    }

    private func component(for readiness: DependencyReadiness, name: String) -> ComponentReadiness {
        switch readiness {
        case let .ready(version, executablePath):
            _ = executablePath
            return ComponentReadiness(name: name, status: .ready, detail: version)
        case .missing:
            return ComponentReadiness(name: name, status: .needsSetup, detail: "Not found")
        case .invalidCustomPath:
            return ComponentReadiness(name: name, status: .needsSetup, detail: "Invalid custom path")
        case .disconnected:
            return ComponentReadiness(name: name, status: .needsSetup, detail: "Disconnected")
        case .signedOut:
            return ComponentReadiness(name: name, status: .needsSetup, detail: "Signed out")
        case .serveApprovalRequired:
            return ComponentReadiness(name: name, status: .needsSetup, detail: "HTTPS approval required")
        case .serveUnavailable:
            return ComponentReadiness(name: name, status: .needsSetup, detail: "Serve HTTPS unavailable")
        case .unavailable:
            return ComponentReadiness(name: name, status: .needsSetup, detail: "Validation failed")
        }
    }
}

private enum AccessLifecycleError: LocalizedError {
    case routeOccupied
    case unsafeEndpoint
    case credentialInfrastructureUnavailable

    var errorDescription: String? {
        switch self {
        case .routeOccupied:
            "The Tailscale HTTPS root route is already occupied."
        case .unsafeEndpoint:
            "Tailscale reported an unsafe Endpoint that cannot be used for enrollment."
        case .credentialInfrastructureUnavailable:
            "Protected Access credential infrastructure is unavailable."
        }
    }
}

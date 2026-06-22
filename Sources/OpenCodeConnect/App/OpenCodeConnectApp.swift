import AppKit
import IOKit.ps
import OpenCodeConnectCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: AccessCoordinator?
    private var powerSource: CFRunLoopSource?
    private var monitoringTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var powerObserver: NSObjectProtocol?
    private var didFinishLaunching = false

    func configure(coordinator: AccessCoordinator) {
        self.coordinator = coordinator
        if powerSource == nil,
           let source = IOPSNotificationCreateRunLoopSource({ _ in
               NotificationCenter.default.post(name: .openCodeConnectPowerSourceDidChange, object: nil)
           }, nil)?.takeRetainedValue()
        {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        if didFinishLaunching { startMonitoring() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        didFinishLaunching = true
        startMonitoring()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        monitoringTask?.cancel()
        Task { @MainActor in
            await coordinator.handle(.quit)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func startMonitoring() {
        guard monitoringTask == nil, let coordinator else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor [weak self] in await self?.coordinator?.handle(.sleep) }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor [weak self] in await self?.coordinator?.handle(.wake) }
            },
            workspace.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
                Task { @MainActor [weak self] in await self?.coordinator?.handle(.logoutOrShutdown) }
            },
            workspace.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor [weak self] in await self?.coordinator?.handle(.logoutOrShutdown) }
            },
        ]
        powerObserver = NotificationCenter.default.addObserver(
            forName: .openCodeConnectPowerSourceDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in await self?.coordinator?.handle(.powerSourceChanged) }
        }
        monitoringTask = Task { @MainActor [weak self, weak coordinator] in
            guard let coordinator else { return }
            await coordinator.handle(.login)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
                guard self != nil else { return }
                await coordinator.handle(.powerSourceChanged)
                await coordinator.handle(.checkHealth)
            }
        }
    }

}

@main
struct OpenCodeConnectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator: AccessCoordinator

    init() {
        let settingsStore = UserDefaultsDependencySettingsStore()
        let desiredStateStore = UserDefaultsDesiredStateStore()
        let settings = settingsStore.load()
        let tailscalePath = settings.customTailscalePath ?? [
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ].first(where: FileManager.default.isExecutableFile(atPath:)) ?? "/opt/homebrew/bin/tailscale"
        let diagnostics = LocalDiagnostics()
        let commandRunner = DiagnosticsCommandRunner(base: ProcessCommandRunner(), diagnostics: diagnostics)
        let coordinator = AccessCoordinator(
            dependencies: SystemDependencyReadiness(
                files: FileManagerExecutableChecker(),
                commands: commandRunner,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            ),
            initialDesiredState: desiredStateStore.load(),
            urlOpener: WorkspaceURLOpener(),
            clipboard: SystemClipboard(),
            endpointStore: UserDefaultsLastVerifiedEndpointStore(),
            settingsStore: settingsStore,
            settings: settings,
            credentialStore: KeychainAccessCredentialStore(),
            passphraseGenerator: SecureReadablePassphraseGenerator(),
            server: SystemManagedServer(),
            route: SystemManagedRoute(tailscalePath: tailscalePath, commands: commandRunner),
            runtimeRecordStore: UserDefaultsManagedServerRecordStore(),
            desiredStateStore: desiredStateStore,
            notifier: SystemUserNotifier(),
            diagnostics: diagnostics,
            loginItem: SystemLaunchAtLoginController(),
            power: SystemPowerAssertionController(),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        _coordinator = State(initialValue: coordinator)
        appDelegate.configure(coordinator: coordinator)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView(coordinator: coordinator)
        } label: {
            Label("OpenCode Connect", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(coordinator: coordinator)
        }
    }

    private var menuBarIcon: String {
        switch coordinator.viewModel.observedState {
        case .stopped: "bolt.horizontal.circle"
        case .starting, .stopping: "hourglass"
        case .available: "bolt.horizontal.circle.fill"
        case .degraded: "exclamationmark.triangle"
        case .needsSetup, .conflict, .error: "exclamationmark.triangle"
        }
    }
}

private extension Notification.Name {
    static let openCodeConnectPowerSourceDidChange = Notification.Name("OpenCodeConnectPowerSourceDidChange")
}

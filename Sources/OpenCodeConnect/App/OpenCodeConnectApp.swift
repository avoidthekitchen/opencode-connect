import AppKit
import IOKit.ps
import OpenCodeConnectCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: AccessCoordinator?
    private var powerSource: CFRunLoopSource?

    func configure(coordinator: AccessCoordinator) {
        self.coordinator = coordinator
        guard powerSource == nil,
              let source = IOPSNotificationCreateRunLoopSource({ _ in
                  NotificationCenter.default.post(name: .openCodeConnectPowerSourceDidChange, object: nil)
              }, nil)?.takeRetainedValue()
        else { return }
        powerSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        Task { @MainActor in
            await coordinator.handle(.quit)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
        _coordinator = State(initialValue: AccessCoordinator(
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
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView(coordinator: coordinator)
                .task {
                    appDelegate.configure(coordinator: coordinator)
                    await coordinator.handle(.login)
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        await coordinator.handle(.powerSourceChanged)
                        await coordinator.handle(.checkHealth)
                    }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                    Task { await coordinator.handle(.sleep) }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    Task { await coordinator.handle(.wake) }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willPowerOffNotification)) { _ in
                    Task { await coordinator.handle(.logoutOrShutdown) }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in
                    Task { await coordinator.handle(.logoutOrShutdown) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openCodeConnectPowerSourceDidChange)) { _ in
                    Task { await coordinator.handle(.powerSourceChanged) }
                }
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

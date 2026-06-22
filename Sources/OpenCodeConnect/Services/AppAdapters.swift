import AppKit
import Foundation
import IOKit.pwr_mgt
import IOKit.ps
import OpenCodeConnectCore
import ServiceManagement
import UserNotifications

struct WorkspaceURLOpener: ExternalURLOpening {
    func open(_ url: URL) async {
        _ = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }
}

struct SystemLaunchAtLoginController: LaunchAtLoginControlling {
    func isEnabled() -> Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }
}

actor SystemPowerAssertionController: PowerAssertionControlling {
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)

    func currentSource() async -> PowerSource {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return .battery }
        return (source as String) == kIOPSACPowerValue ? .external : .battery
    }

    func setIdleSleepPreventionRequired(_ required: Bool) async {
        if required, assertionID == kIOPMNullAssertionID {
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "OpenCode Connect is keeping Enabled access available" as CFString,
                &assertionID
            )
        } else if !required, assertionID != kIOPMNullAssertionID {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        }
    }

    deinit {
        if assertionID != kIOPMNullAssertionID { IOPMAssertionRelease(assertionID) }
    }
}

struct SystemUserNotifier: UserNotifying {
    func notifyFailure(state: ObservedState, explanation: String) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert])
        let content = UNMutableNotificationContent()
        content.title = state == .conflict ? "OpenCode Connect Conflict" : "OpenCode Connect Error"
        content.body = explanation
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

struct SystemClipboard: ClipboardWriting, @unchecked Sendable {
    func write(_ value: String) async {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }
}

struct UserDefaultsLastVerifiedEndpointStore: LastVerifiedEndpointPersisting, @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let key = "lastVerifiedEndpoint"

    func load() async -> URL? {
        defaults.string(forKey: key).flatMap(URL.init(string:))
    }

    func save(_ endpoint: URL) async {
        defaults.set(endpoint.absoluteString, forKey: key)
    }
}

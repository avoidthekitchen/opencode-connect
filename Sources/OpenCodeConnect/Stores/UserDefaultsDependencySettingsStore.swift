import Foundation
import OpenCodeConnectCore

struct UserDefaultsDependencySettingsStore: DependencySettingsPersisting, @unchecked Sendable {
    private let defaults = UserDefaults.standard

    func load() -> DependencySettings {
        DependencySettings(
            customOpenCodePath: defaults.string(forKey: "customOpenCodePath"),
            customTailscalePath: defaults.string(forKey: "customTailscalePath"),
            accessUsername: defaults.string(forKey: "accessUsername") ?? "opencode",
            accessMode: defaults.string(forKey: "accessMode").flatMap(AccessMode.init(rawValue:)) ?? .protected,
            backendPort: defaults.object(forKey: "backendPort") as? Int ?? 4096,
            httpsPort: defaults.object(forKey: "httpsPort") as? Int ?? 443,
            availabilityPolicy: defaults.string(forKey: "availabilityPolicy")
                .flatMap(AvailabilityPolicy.init(rawValue:)) ?? .onExternalPower
        )
    }

    func save(_ settings: DependencySettings) async {
        defaults.set(settings.customOpenCodePath, forKey: "customOpenCodePath")
        defaults.set(settings.customTailscalePath, forKey: "customTailscalePath")
        defaults.set(settings.accessUsername, forKey: "accessUsername")
        defaults.set(settings.accessMode.rawValue, forKey: "accessMode")
        defaults.set(settings.backendPort, forKey: "backendPort")
        defaults.set(settings.httpsPort, forKey: "httpsPort")
        defaults.set(settings.availabilityPolicy.rawValue, forKey: "availabilityPolicy")
    }
}

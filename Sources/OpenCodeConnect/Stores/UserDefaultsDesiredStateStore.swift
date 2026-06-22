import Foundation
import OpenCodeConnectCore

struct UserDefaultsDesiredStateStore: DesiredStatePersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "desiredStateEnabled") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> DesiredState {
        defaults.bool(forKey: key) ? .enabled : .disabled
    }

    func save(_ desiredState: DesiredState) async {
        defaults.set(desiredState == .enabled, forKey: key)
    }
}

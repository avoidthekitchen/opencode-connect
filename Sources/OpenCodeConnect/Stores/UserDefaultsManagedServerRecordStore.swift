import Foundation
import OpenCodeConnectCore

struct UserDefaultsManagedServerRecordStore: ManagedServerRecordStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "managedServerRecord") {
        self.defaults = defaults
        self.key = key
    }

    func load() async throws -> ManagedServerRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(ManagedServerRecord.self, from: data)
    }

    func save(_ record: ManagedServerRecord) async throws {
        defaults.set(try JSONEncoder().encode(record), forKey: key)
    }

    func clear() async throws {
        defaults.removeObject(forKey: key)
    }
}

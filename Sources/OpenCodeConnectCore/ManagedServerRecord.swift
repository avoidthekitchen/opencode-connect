import Foundation

/// Non-secret identity persisted after OpenCode Connect launches a Managed Server.
/// Authentication material deliberately has no representation in this record.
public struct ManagedServerRecord: Codable, Equatable, Sendable {
    public let processIdentifier: Int32
    public let executablePath: String
    public let backendPort: Int
    public let executableFingerprint: String

    public init(
        processIdentifier: Int32,
        executablePath: String,
        backendPort: Int,
        executableFingerprint: String
    ) {
        self.processIdentifier = processIdentifier
        self.executablePath = executablePath
        self.backendPort = backendPort
        self.executableFingerprint = executableFingerprint
    }
}

public enum ManagedServerInspection: Equatable, Sendable {
    case missing
    case verified(ManagedServerRecord)
    case conflict(String)
}

public struct ManagedProcessSnapshot: Equatable, Sendable {
    public let executablePath: String
    public let executableFingerprint: String

    public init(executablePath: String, executableFingerprint: String) {
        self.executablePath = executablePath
        self.executableFingerprint = executableFingerprint
    }
}

public protocol ManagedProcessInspecting: Sendable {
    func snapshot(processIdentifier: Int32) -> ManagedProcessSnapshot?
    func isLoopbackPortOccupied(_ port: Int) -> Bool
}

public protocol ManagedServerRecordStoring: Sendable {
    func load() async throws -> ManagedServerRecord?
    func save(_ record: ManagedServerRecord) async throws
    func clear() async throws
}

public struct NoopManagedServerRecordStore: ManagedServerRecordStoring {
    public init() {}
    public func load() async throws -> ManagedServerRecord? { nil }
    public func save(_ record: ManagedServerRecord) async throws {}
    public func clear() async throws {}
}

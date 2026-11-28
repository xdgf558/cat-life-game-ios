import Foundation

public enum SaveRepositoryError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidSnapshot
    case unreadableSave
}

public enum SaveLoadDisposition: Equatable, Sendable {
    case created
    case loaded
    case recoveredBackup
}

/// Durable atomic file storage for the new Cat Diary save format.
/// Uses dedicated filenames (`cat-diary-save-v1.json`) so legacy `cat-life-native-v1.json`
/// files on existing TestFlight devices are preserved untouched.
public actor DiarySaveRepository {
    static let backupInterval: TimeInterval = 5 * 60
    public nonisolated let directory: URL
    public nonisolated let saveURL: URL
    public nonisolated let backupURL: URL
    public private(set) var lastLoadDisposition: SaveLoadDisposition = .loaded
    public private(set) var lastSavedAt: Date?

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    public init(directory: URL) {
        self.directory = directory
        self.saveURL = directory.appendingPathComponent("cat-diary-save-v1.json")
        self.backupURL = directory.appendingPathComponent("cat-diary-save-v1.backup.json")
    }

    public func loadOrCreate(now: Date = Date(), calendar: Calendar = .current) async throws -> DiaryGameState {
        try ensureDirectory()
        let fm = FileManager.default
        if fm.fileExists(atPath: saveURL.path) {
            let primaryData = try Data(contentsOf: saveURL)
            do {
                var state = try decode(primaryData)
                DiaryLedger.recoverPendingOnStartup(&state)
                lastLoadDisposition = .loaded
                lastSavedAt = fileModificationDate(at: saveURL) ?? DayClock.date(fromEpochMs: state.updatedAt)
                return state
            } catch SaveRepositoryError.unsupportedSchemaVersion(let version) {
                throw SaveRepositoryError.unsupportedSchemaVersion(version)
            } catch {
                return try recoverBackup()
            }
        }
        if fm.fileExists(atPath: backupURL.path) {
            return try recoverBackup()
        }
        let fresh = DiaryGameState.fresh(now: DayClock.epochMs(now), calendar: calendar)
        try await save(fresh, now: now)
        lastLoadDisposition = .created
        return fresh
    }

    public func save(_ state: DiaryGameState, now: Date = Date()) async throws {
        guard state.schemaVersion == DiaryGameState.currentSchemaVersion else {
            throw SaveRepositoryError.unsupportedSchemaVersion(state.schemaVersion)
        }
        guard state.isValid else { throw SaveRepositoryError.invalidSnapshot }
        let candidate = try encode(state)
        _ = try decode(candidate)
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: saveURL.path) {
            let previous = try Data(contentsOf: saveURL)
            if previous == candidate {
                lastSavedAt = fileModificationDate(at: saveURL) ?? lastSavedAt ?? DayClock.date(fromEpochMs: state.updatedAt)
                return
            }
            if (try? decode(previous)) != nil, shouldRotateBackup(now: now) {
                try previous.write(to: backupURL, options: .atomic)
                try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: backupURL.path)
            }
        }
        try candidate.write(to: saveURL, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: saveURL.path)
        lastSavedAt = now
    }

    private func recoverBackup() throws -> DiaryGameState {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw SaveRepositoryError.unreadableSave
        }
        let backupSavedAt = fileModificationDate(at: backupURL)
        let data = try Data(contentsOf: backupURL)
        var state = try decode(data)
        DiaryLedger.recoverPendingOnStartup(&state)
        let persistedAt = backupSavedAt ?? DayClock.date(fromEpochMs: state.updatedAt)
        try encode(state).write(to: saveURL, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: persistedAt], ofItemAtPath: saveURL.path)
        lastLoadDisposition = .recoveredBackup
        lastSavedAt = persistedAt
        return state
    }

    private func fileModificationDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func shouldRotateBackup(now: Date) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: backupURL.path),
              let modified = attrs[.modificationDate] as? Date else {
            return true
        }
        return now.timeIntervalSince(modified) >= Self.backupInterval
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func encode(_ state: DiaryGameState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    private func decode(_ data: Data) throws -> DiaryGameState {
        if let header = try? JSONDecoder().decode(SchemaHeader.self, from: data),
           header.schemaVersion > DiaryGameState.currentSchemaVersion {
            throw SaveRepositoryError.unsupportedSchemaVersion(header.schemaVersion)
        }
        guard let state = try? JSONDecoder().decode(DiaryGameState.self, from: data), state.isValid else {
            throw SaveRepositoryError.invalidSnapshot
        }
        return state
    }
}

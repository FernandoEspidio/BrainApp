import Foundation

/// Storage for the local document. The app never makes network requests for its data.
/// Behind this protocol you can switch to SwiftData or SQLite without touching the views.
protocol SnapshotStore: AnyObject {
    func load() throws -> AppSnapshot?
    func save(_ snapshot: AppSnapshot) throws
    func erase() throws
}

enum SnapshotCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder { JSONDecoder() }
}

/// JSON in Application Support, with atomic writes and system data protection.
final class FileSnapshotStore: SnapshotStore {
    let url: URL

    init(url: URL = FileSnapshotStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("LocalEntries", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    func load() throws -> AppSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try SnapshotCoding.decoder().decode(AppSnapshot.self, from: data)
    }

    func save(_ snapshot: AppSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try SnapshotCoding.encoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func erase() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// If the file can't be read, it is moved aside instead of overwritten so no data is lost.
    @discardableResult
    func quarantineUnreadableFile() -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = url.deletingLastPathComponent().appendingPathComponent("snapshot-unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

/// In-memory store: used by demo mode (never touches disk) and by tests.
final class InMemorySnapshotStore: SnapshotStore {
    private var stored: AppSnapshot?

    init(initial: AppSnapshot? = nil) {
        stored = initial
    }

    func load() throws -> AppSnapshot? { stored }
    func save(_ snapshot: AppSnapshot) throws { stored = snapshot }
    func erase() throws { stored = nil }
}

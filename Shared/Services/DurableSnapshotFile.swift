import Foundation
import Darwin

/// Synchronous atomic snapshots for mutations that must survive process exit.
/// Failures occur before replacement, leaving the previous complete file intact.
public struct DurableSnapshotFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static func defaultURL(name: String) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("CiggyDurableState", isDirectory: true)
            .appendingPathComponent(name).appendingPathExtension("json")
    }

    public func load() throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) { return nil }
    }

    public func write(_ data: Data) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        #if os(iOS) || os(watchOS)
        try data.write(to: temporary, options: .completeFileProtectionUntilFirstUserAuthentication)
        #else
        try data.write(to: temporary)
        #endif
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        // Synchronize BEFORE rename. Nothing may throw after replacement: callers
        // must never roll back memory while the new journal is already on disk.
        guard rename(temporary.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let descriptor = open(directory.path, O_RDONLY)
        if descriptor >= 0 { _ = fsync(descriptor); _ = close(descriptor) }
    }
}

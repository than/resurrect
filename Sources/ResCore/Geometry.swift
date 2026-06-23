import Foundation

/// A persisted window frame for one session.
public struct WindowFrame: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// Persistent window-geometry store: {sessionId: WindowFrame}.
///
/// File: ${XDG_STATE_HOME:-~/.local/state}/res/geometry.json — alongside
/// last-live.json. Pure JSON I/O; no AX here (capture/restore live in
/// GhosttyAccessibility behind the permission gate). Best-effort: every error
/// degrades to "no saved frame" and never throws to callers.
public enum Geometry {
    public static var file: String {
        (Snapshot.stateDir as NSString).appendingPathComponent("geometry.json")
    }

    /// Read the whole map. [] / unreadable -> empty.
    public static func readAll(fileOverride: String? = nil) -> [String: WindowFrame] {
        let path = fileOverride ?? file
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
        return (try? JSONDecoder().decode([String: WindowFrame].self, from: data)) ?? [:]
    }

    /// The saved frame for one session, if any.
    public static func frame(for sessionId: String, fileOverride: String? = nil) -> WindowFrame? {
        readAll(fileOverride: fileOverride)[sessionId]
    }

    /// Persist the whole map atomically. Returns true on success.
    @discardableResult
    public static func writeAll(_ map: [String: WindowFrame], fileOverride: String? = nil) -> Bool {
        let path = fileOverride ?? file
        let dir = (path as NSString).deletingLastPathComponent
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(map) else { return false }
        do {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
            let tmp = path + ".tmp"
            try data.write(to: URL(fileURLWithPath: tmp))
            _ = try? FileManager.default.removeItem(atPath: path)
            try FileManager.default.moveItem(atPath: tmp, toPath: path)
            return true
        } catch {
            return false
        }
    }

    /// Merge one frame into the persisted map (read-modify-write). Best-effort.
    @discardableResult
    public static func update(
        sessionId: String, frame: WindowFrame, fileOverride: String? = nil
    ) -> Bool {
        var map = readAll(fileOverride: fileOverride)
        map[sessionId] = frame
        return writeAll(map, fileOverride: fileOverride)
    }
}

import Foundation

/// Snapshot / restore (no daemon).
///
/// State dir = ${XDG_STATE_HOME:-~/.local/state}/res ; file last-live.json.
/// Deliberately NOT under ~/.claude — res is multi-agent.
public enum Snapshot {
    public static var stateDir: String {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_STATE_HOME"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".local/state")
        return (base as NSString).appendingPathComponent("res")
    }

    public static var lastLive: String {
        (stateDir as NSString).appendingPathComponent("last-live.json")
    }

    /// One persisted entry in the snapshot.
    public struct Entry: Sendable {
        public let agent: String
        public let id: String
        public let title: String
        public let cwd: String
        public let name: String?

        public init(agent: String, id: String, title: String, cwd: String, name: String?) {
            self.agent = agent
            self.id = id
            self.title = title
            self.cwd = cwd
            self.name = name
        }
    }

    /// Persist the current LIVE set so `res restore` can resurrect it after a
    /// reboot or an accidental "quit all windows". Never writes an empty set, so
    /// a reboot (0 live) can't clobber the last good snapshot. Returns count.
    @discardableResult
    public static func write(_ sessions: [Session], stateDirOverride: String? = nil) -> Int {
        let dir = stateDirOverride ?? stateDir
        let file = (dir as NSString).appendingPathComponent("last-live.json")
        let live = sessions.filter { $0.live }
        if live.isEmpty { return 0 }

        var entries: [[String: Any]] = []
        for s in live {
            entries.append([
                "agent": s.agent,
                "id": s.id,
                "title": s.title,
                "cwd": s.cwd,
                "name": s.name as Any? ?? NSNull(),
            ])
        }
        let payload: [String: Any] = [
            "saved_at": Date().timeIntervalSince1970,
            "sessions": entries,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted]) else {
            return 0
        }
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let tmp = file + ".tmp"
        do {
            try data.write(to: URL(fileURLWithPath: tmp))
            // os.replace == atomic rename
            _ = try? FileManager.default.removeItem(atPath: file)
            try FileManager.default.moveItem(atPath: tmp, toPath: file)
        } catch {
            return 0
        }
        return live.count
    }

    /// Returns the raw saved entries (id/agent/title/cwd/name) or [] on any error.
    public static func read(stateDirOverride: String? = nil) -> [Entry] {
        let dir = stateDirOverride ?? stateDir
        let file = (dir as NSString).appendingPathComponent("last-live.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["sessions"] as? [[String: Any]] else {
            return []
        }
        return arr.map { e in
            Entry(
                agent: (e["agent"] as? String) ?? "claude-code",
                id: (e["id"] as? String) ?? "",
                title: (e["title"] as? String) ?? ((e["id"] as? String) ?? ""),
                cwd: (e["cwd"] as? String) ?? NSHomeDirectory(),
                name: e["name"] as? String
            )
        }
    }
}

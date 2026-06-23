import Foundation

/// One resumable coding-agent conversation. Agent-neutral.
public struct Session: Sendable, Hashable, Identifiable {
    public let id: String
    public let agent: String          // adapter name, e.g. "claude-code"
    public let title: String
    public let name: String?          // manual rename, if the agent supports it
    public let aiTitle: String?       // auto-generated title, if any
    public let branch: String
    public let cwd: String
    public let project: String
    public let messages: Int
    public let mtime: Double
    public let status: String?        // "busy" | "idle" | nil (only when live)
    public let pid: Int?
    public let live: Bool

    public init(
        id: String,
        agent: String,
        title: String,
        name: String?,
        aiTitle: String?,
        branch: String,
        cwd: String,
        project: String,
        messages: Int,
        mtime: Double,
        status: String?,
        pid: Int?,
        live: Bool
    ) {
        self.id = id
        self.agent = agent
        self.title = title
        self.name = name
        self.aiTitle = aiTitle
        self.branch = branch
        self.cwd = cwd
        self.project = project
        self.messages = messages
        self.mtime = mtime
        self.status = status
        self.pid = pid
        self.live = live
    }

    /// Seconds since last touch, never negative.
    public func age() -> Double {
        max(0.0, Date().timeIntervalSince1970 - mtime)
    }
}

// MARK: - Rendering helpers

/// Minutes window for "recently active". Mirrors RES_ACTIVE_WINDOW (default 10).
public var activeWindowMinutes: Int {
    if let raw = ProcessInfo.processInfo.environment["RES_ACTIVE_WINDOW"],
       let v = Int(raw) {
        return v
    }
    return 10
}

public func humanAge(_ secs: Double) -> String {
    if secs < 60 { return "\(Int(secs))s" }
    if secs < 3600 { return "\(Int(secs / 60))m" }
    if secs < 86400 { return "\(Int(secs / 3600))h" }
    return "\(Int(secs / 86400))d"
}

public func statusGlyph(_ s: Session) -> String {
    if s.status == "busy" { return "\u{25C9}" }   // ◉ running, working
    if s.status == "idle" { return "\u{25CB}" }   // ○ running, waiting on you
    if s.age() <= Double(activeWindowMinutes) * 60 { return "\u{25CF}" }  // ● touched recently
    return " "
}

// MARK: - JSON serialization (snake_case, matching the Python `session_dict`)

extension Session {
    /// A JSON-encodable dict with snake_case keys plus `age` (int seconds).
    public func jsonObject() -> [String: Any] {
        var d: [String: Any] = [:]
        d["id"] = id
        d["agent"] = agent
        d["title"] = title
        d["name"] = name as Any? ?? NSNull()
        d["ai_title"] = aiTitle as Any? ?? NSNull()
        d["branch"] = branch
        d["cwd"] = cwd
        d["project"] = project
        d["messages"] = messages
        d["mtime"] = mtime
        d["status"] = status as Any? ?? NSNull()
        d["pid"] = pid as Any? ?? NSNull()
        d["live"] = live
        d["age"] = Int(age().rounded())
        return d
    }
}

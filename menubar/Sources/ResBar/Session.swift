import Foundation

/// One coding-agent session as reported by `res list --json`.
/// Decoded with `.convertFromSnakeCase`, so `ai_title` maps to `aiTitle`.
struct Session: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let agent: String
    let title: String
    let name: String?
    let aiTitle: String?
    let branch: String
    let cwd: String
    let project: String
    let messages: Int
    let mtime: Double
    let status: String?      // "busy" | "idle" | nil
    let pid: Int?
    let live: Bool
    let age: Int             // seconds

    /// Preferred human label for a row.
    var displayTitle: String {
        if let t = aiTitle, !t.isEmpty { return t }
        if let n = name, !n.isEmpty { return n }
        if !title.isEmpty { return title }
        return id
    }

    /// Leading glyph per the approved mockup.
    /// ◉ busy, ○ idle, ● recently active (<=600s), else none.
    var glyph: String {
        switch status {
        case "busy": return "\u{25C9}"  // ◉
        case "idle": return "\u{25CB}"  // ○
        default:
            return age <= 600 ? "\u{25CF}" : ""  // ●
        }
    }
}

import Foundation

/// Claude Code adapter.
///
/// Sessions are reconstructed by joining two on-disk sources on `sessionId`:
///  * ~/.claude/projects/<slug>/<uuid>.jsonl — transcripts (ai-title, per-message
///    cwd/gitBranch/counts).
///  * ~/.claude/sessions/<pid>.json — the live registry (status, pid, manual name).
///
/// Title precedence: manual name → auto aiTitle → first non-`<…>` user prompt.
/// Liveness requires registry status AND a running pid (rejects stale records).
public struct ClaudeCodeAgent: CodingAgent {
    public let name = "claude-code"
    public let display = "Claude Code"

    /// Injectable for tests. Default to ~/.claude/{projects,sessions}.
    public let projectsDir: String
    public let sessionsDir: String

    public init(projectsDir: String? = nil, sessionsDir: String? = nil) {
        let claude = (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        self.projectsDir = projectsDir
            ?? (claude as NSString).appendingPathComponent("projects")
        self.sessionsDir = sessionsDir
            ?? (claude as NSString).appendingPathComponent("sessions")
    }

    public func available() -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: projectsDir, isDirectory: &isDir)
            && isDir.boolValue
    }

    // MARK: - discovery

    public func discover() -> [Session] {
        let reg = loadRegistry()
        var out: [Session] = []
        for path in transcriptPaths() {
            guard let t = scanTranscript(path) else { continue }
            let entry = reg[t.id]
            let name = entry?.name
            let live = Self.isLive(entry)

            let firstLine = (t.firstPrompt ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
            let truncatedPrompt = String(firstLine.prefix(60))

            let title: String
            if let n = name, !n.isEmpty {
                title = n
            } else if let ai = t.aiTitle, !ai.isEmpty {
                title = ai
            } else if !truncatedPrompt.isEmpty {
                title = truncatedPrompt
            } else {
                title = "(untitled)"
            }

            let proj: String
            if t.cwd != "-" {
                let trimmed = t.cwd.hasSuffix("/") ? String(t.cwd.dropLast()) : t.cwd
                proj = (trimmed as NSString).lastPathComponent
            } else {
                proj = "-"
            }

            out.append(Session(
                id: t.id,
                agent: self.name,
                title: title,
                name: name,
                aiTitle: t.aiTitle,
                branch: t.branch,
                cwd: t.cwd,
                project: proj,
                messages: t.messages,
                mtime: t.mtime,
                status: live ? entry?.status : nil,
                pid: live ? entry?.pid : nil,
                live: live
            ))
        }
        return out
    }

    // MARK: - resume

    public func resumeCommand(_ sessionId: String, name: String?) -> String {
        var cmd = "claude --resume \(shellQuote(sessionId))"
        if let name, !name.isEmpty {
            cmd += " --name \(shellQuote(name))"
        }
        return cmd
    }

    // MARK: - internals

    private struct RegEntry {
        let sessionId: String
        let pid: Int?
        let status: String?
        let name: String?
        let updatedAt: Double
        let cwd: String?
    }

    private struct TranscriptInfo {
        let id: String
        let aiTitle: String?
        let firstPrompt: String?
        let branch: String
        let cwd: String
        let messages: Int
        let mtime: Double
    }

    private static func isLive(_ entry: RegEntry?) -> Bool {
        guard let entry else { return false }
        guard let status = entry.status, status == "busy" || status == "idle" else { return false }
        guard let pid = entry.pid else { return false }
        return pidAlive(pid)
    }

    private func transcriptPaths() -> [String] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(atPath: projectsDir) else { return [] }
        var paths: [String] = []
        for proj in projects {
            let projPath = (projectsDir as NSString).appendingPathComponent(proj)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projPath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let files = try? fm.contentsOfDirectory(atPath: projPath) else { continue }
            for f in files where f.hasSuffix(".jsonl") {
                paths.append((projPath as NSString).appendingPathComponent(f))
            }
        }
        return paths
    }

    private func loadRegistry() -> [String: RegEntry] {
        let fm = FileManager.default
        var reg: [String: RegEntry] = [:]
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return reg }
        for f in files where f.hasSuffix(".json") {
            let path = (sessionsDir as NSString).appendingPathComponent(f)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sid = d["sessionId"] as? String else {
                continue
            }
            let updated = (d["updatedAt"] as? NSNumber)?.doubleValue ?? 0
            let entry = RegEntry(
                sessionId: sid,
                pid: (d["pid"] as? NSNumber)?.intValue,
                status: d["status"] as? String,
                name: d["name"] as? String,
                updatedAt: updated,
                cwd: d["cwd"] as? String
            )
            if let prev = reg[sid] {
                if updated >= prev.updatedAt { reg[sid] = entry }
            } else {
                reg[sid] = entry
            }
        }
        return reg
    }

    private func scanTranscript(_ path: String) -> TranscriptInfo? {
        let fm = FileManager.default
        guard let mtimeDate = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date else {
            return nil
        }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }

        var aiTitle: String? = nil
        var branch: String? = nil
        var cwd: String? = nil
        var firstPrompt: String? = nil
        var msgs = 0

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let d = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            let typ = d["type"] as? String
            if typ == "ai-title" {
                aiTitle = d["aiTitle"] as? String
            } else if typ == "user" || typ == "assistant" {
                msgs += 1
                if let b = d["gitBranch"] as? String, !b.isEmpty { branch = b }
                if let c = d["cwd"] as? String, !c.isEmpty { cwd = c }
                if typ == "user", firstPrompt == nil {
                    if let txt = Self.textOf(d["message"]) {
                        let lead = txt.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
                        if !txt.isEmpty && !lead.hasPrefix("<") {
                            firstPrompt = txt
                        }
                    }
                }
            }
        }

        let id = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return TranscriptInfo(
            id: id,
            aiTitle: aiTitle,
            firstPrompt: firstPrompt,
            branch: branch ?? "-",
            cwd: cwd ?? "-",
            messages: msgs,
            mtime: mtimeDate.timeIntervalSince1970
        )
    }

    private static func textOf(_ message: Any?) -> String? {
        guard let msg = message as? [String: Any] else { return nil }
        let c = msg["content"]
        if let s = c as? String { return s }
        if let arr = c as? [[String: Any]] {
            for blk in arr {
                if blk["type"] as? String == "text" {
                    return blk["text"] as? String
                }
            }
        }
        return nil
    }
}

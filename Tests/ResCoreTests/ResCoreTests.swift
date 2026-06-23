import Testing
import Foundation
@testable import ResCore

/// Per-test fixture environment: temp projects/sessions/state dirs.
/// swift-testing constructs a fresh instance per test method, giving us
/// the same isolation XCTest's setUp/tearDown provided.
struct Fixture {
    let tmp: URL
    let projectsDir: String
    let sessionsDir: String
    let stateDir: String

    init() {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("res-test-\(UUID().uuidString)")
        let fm = FileManager.default
        projectsDir = tmp.appendingPathComponent("projects").path
        sessionsDir = tmp.appendingPathComponent("sessions").path
        stateDir = tmp.appendingPathComponent("state").path
        try? fm.createDirectory(
            atPath: (projectsDir as NSString).appendingPathComponent("proj"),
            withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func agent() -> ClaudeCodeAgent {
        ClaudeCodeAgent(projectsDir: projectsDir, sessionsDir: sessionsDir)
    }

    func discover() -> [String: Session] {
        Dictionary(agent().discover().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func writeTranscript(
        _ sid: String,
        aiTitle: String? = nil,
        firstPrompt: String? = nil,
        cwd: String = "/Users/dev/proj",
        branch: String = "main",
        msgs: Int = 1
    ) {
        var lines: [[String: Any]] = []
        if let aiTitle {
            lines.append(["type": "ai-title", "sessionId": sid, "aiTitle": aiTitle])
        }
        var remaining = msgs
        if let firstPrompt {
            lines.append([
                "type": "user", "sessionId": sid, "cwd": cwd, "gitBranch": branch,
                "message": ["content": firstPrompt],
            ])
            remaining = max(0, msgs - 1)
        }
        for _ in 0..<remaining {
            lines.append([
                "type": "assistant", "sessionId": sid, "cwd": cwd, "gitBranch": branch,
                "message": ["content": "ok"],
            ])
        }
        let jsonLines = lines.map { obj -> String in
            let d = try! JSONSerialization.data(withJSONObject: obj)
            return String(data: d, encoding: .utf8)!
        }
        let text = jsonLines.joined(separator: "\n") + "\n"
        let path = ((projectsDir as NSString).appendingPathComponent("proj") as NSString)
            .appendingPathComponent("\(sid).jsonl")
        try! text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func writeRegistry(
        _ sid: String,
        pid: Int,
        status: String = "idle",
        name: String? = nil,
        updated: Int = 1000
    ) {
        var entry: [String: Any] = [
            "sessionId": sid, "pid": pid, "status": status,
            "updatedAt": updated, "cwd": "/Users/dev/proj",
        ]
        if let name { entry["name"] = name }
        let d = try! JSONSerialization.data(withJSONObject: entry)
        let path = (sessionsDir as NSString).appendingPathComponent("\(pid).json")
        try! d.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - liveness

@Test func liveWhenPidAlive() {
    let f = Fixture(); defer { f.cleanup() }
    f.writeTranscript("live", aiTitle: "Live")
    f.writeRegistry("live", pid: Int(getpid()), status: "busy")
    let s = f.discover()["live"]
    #expect(s?.live == true)
    #expect(s?.status == "busy")
    #expect(s?.agent == "claude-code")
}

@Test func notLiveWhenPidDead() {
    let f = Fixture(); defer { f.cleanup() }
    f.writeTranscript("stale", aiTitle: "Stale")
    f.writeRegistry("stale", pid: 999999, status: "idle")
    let s = f.discover()["stale"]
    #expect(s?.live == false)
    #expect(s?.status == nil)
}

@Test func notLiveWithoutRegistry() {
    let f = Fixture(); defer { f.cleanup() }
    f.writeTranscript("orphan", aiTitle: "Orphan")
    #expect(f.discover()["orphan"]?.live == false)
}

// MARK: - title precedence

@Test func manualNameWins() {
    let f = Fixture(); defer { f.cleanup() }
    f.writeTranscript("s1", aiTitle: "Auto", firstPrompt: "hi")
    f.writeRegistry("s1", pid: Int(getpid()), name: "Manual 🏒")
    #expect(f.discover()["s1"]?.title == "Manual 🏒")
}

@Test func aiTitleThenPrompt() {
    let f = Fixture(); defer { f.cleanup() }
    f.writeTranscript("s2", aiTitle: "Auto", firstPrompt: "hi")
    f.writeTranscript("s3", firstPrompt: "real first prompt")
    let d = f.discover()
    #expect(d["s2"]?.title == "Auto")
    #expect(d["s3"]?.title == "real first prompt")
}

@Test func skipsSystemReminder() {
    let f = Fixture(); defer { f.cleanup() }
    f.writeTranscript("s4", firstPrompt: "<system-reminder>noise</system-reminder>")
    #expect(f.discover()["s4"]?.title == "(untitled)")
}

// MARK: - resume command (adapter)

@Test func resumeCommandBasic() {
    #expect(ClaudeCodeAgent().resumeCommand("abc-123") == "claude --resume abc-123")
}

@Test func resumeCommandWithName() {
    let cmd = ClaudeCodeAgent().resumeCommand("abc-123", name: "Westside 🏒")
    #expect(cmd == "claude --resume abc-123 --name 'Westside 🏒'")
}

// MARK: - snapshot / restore (core)

@Test func snapshotRoundTrip() {
    let f = Fixture(); defer { f.cleanup() }
    f.writeTranscript("l1", aiTitle: "L1")
    f.writeRegistry("l1", pid: Int(getpid()), status: "busy")
    let count = Snapshot.write(f.agent().discover(), stateDirOverride: f.stateDir)
    #expect(count == 1)
    let saved = Snapshot.read(stateDirOverride: f.stateDir)
    #expect(saved.first?.id == "l1")
    #expect(saved.first?.agent == "claude-code")
}

@Test func snapshotNoClobberOnEmpty() throws {
    let f = Fixture(); defer { f.cleanup() }
    f.writeTranscript("d1", aiTitle: "Dead")
    f.writeRegistry("d1", pid: 999999, status: "idle")
    try FileManager.default.createDirectory(atPath: f.stateDir, withIntermediateDirectories: true)
    let seed: [String: Any] = [
        "sessions": [["id": "earlier", "agent": "claude-code", "cwd": "/x"]],
    ]
    let data = try JSONSerialization.data(withJSONObject: seed)
    let file = (f.stateDir as NSString).appendingPathComponent("last-live.json")
    try data.write(to: URL(fileURLWithPath: file))

    let count = Snapshot.write(f.agent().discover(), stateDirOverride: f.stateDir)
    #expect(count == 0)
    #expect(Snapshot.read(stateDirOverride: f.stateDir).first?.id == "earlier")
}

// MARK: - launch argv (Ghostty)

@Test func launchArgv() throws {
    let term = GhosttyTerminal(app: "Ghostty.app")
    let argv = term.launchArgv(cwd: "/Users/dev/proj", command: "claude --resume abc-123")
    #expect(Array(argv.prefix(5)) == ["open", "-na", "Ghostty.app", "--args", "-e"])
    #expect(argv[5] == "zsh")
    #expect(argv[6] == "-ilc")   // interactive+login so ~/.zshrc (PATH) is sourced
    let last = try #require(argv.last)
    #expect(last.contains("cd /Users/dev/proj"))
    #expect(last.hasSuffix("exec zsh -il"))
}

@Test func launchArgvQuotesSpaceyCwd() throws {
    let term = GhosttyTerminal(app: "Ghostty.app")
    let argv = term.launchArgv(cwd: "/Users/dev/My Deals", command: "claude --resume x")
    let last = try #require(argv.last)
    #expect(last.contains("'/Users/dev/My Deals'"))
}

// MARK: - pid liveness helper

@Test func pidAliveSelf() {
    #expect(pidAlive(Int(getpid())) == true)
}

@Test func pidAliveDead() {
    #expect(pidAlive(999999) == false)
}

@Test func pidAliveNonPositive() {
    #expect(pidAlive(0) == false)
    #expect(pidAlive(-1) == false)
}

// MARK: - registry dedup

@Test func registryDedupKeepsHighestUpdatedAt() {
    let f = Fixture(); defer { f.cleanup() }
    f.writeTranscript("dup", aiTitle: "Dup")
    f.writeRegistry("dup", pid: 999998, status: "idle", name: "Old", updated: 100)
    f.writeRegistry("dup", pid: 999999, status: "idle", name: "New", updated: 200)
    #expect(f.discover()["dup"]?.name == "New")
}

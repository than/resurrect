import Foundation
import ArgumentParser
import ResCore

// MARK: - Filtering shared by list/pick

struct Filters {
    var here: Bool
    var active: Bool
    var n: Int?
}

func filtered(_ sessions: [Session], _ f: Filters) -> [Session] {
    var rows = sessions
    if f.here {
        let cwd = FileManager.default.currentDirectoryPath
        rows = rows.filter { $0.cwd == cwd }
    }
    if f.active {
        let window = Double(activeWindowMinutes) * 60
        rows = rows.filter { $0.live || $0.age() <= window }
    }
    if let n = f.n, n > 0 {
        rows = Array(rows.prefix(n))
    }
    return rows
}

func resumeFor(_ session: Session) -> String {
    if let agent = AgentRegistry.agent(byName: session.agent) {
        return agent.resumeCommand(session.id, name: session.name)
    }
    return "# unknown agent \(session.agent)"
}

func prefixMatch(_ index: [String: Session], _ prefix: String) -> Session? {
    let hits = index.filter { $0.key.hasPrefix(prefix) }
    return hits.count == 1 ? hits.values.first : nil
}

// MARK: - Root

struct ResCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "res",
        abstract: "Resurrect your coding-agent sessions",
        subcommands: [
            List.self, Pick.self, Open.self, Snapshot.self,
            Restore.self, Agents.self, Terminals.self, Menubar.self,
        ]
    )
}

// MARK: - list

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "list sessions (table or --json)")

    @Flag(name: .long) var json = false
    @Flag(name: .long, help: "only live/recent") var active = false
    @Flag(name: .long, help: "only this directory") var here = false
    @Option(name: .customShort("n"), help: "max rows") var n: Int = 30

    func run() throws {
        let sessions = AgentRegistry.discoverAll()
        ResCore.Snapshot.write(sessions)  // opportunistic
        let rows = filtered(sessions, Filters(here: here, active: active, n: n))
        if json {
            let objs = rows.map { $0.jsonObject() }
            let data = try JSONSerialization.data(
                withJSONObject: objs, options: [.prettyPrinted, .withoutEscapingSlashes])
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            renderTable(rows)
        }
    }
}

func renderTable(_ rows: [Session]) {
    let live = rows.filter { $0.live }.count
    let df = DateFormatter()
    df.dateFormat = "HH:mm:ss"
    let now = df.string(from: Date())
    print("")
    print("  Coding-agent sessions — \(rows.count) shown, \(live) live  \(now)")
    print("")
    let header = "   " + pad("AGE", 4, right: true) + "  " + pad("MSGS", 4, right: true)
        + "  " + pad("BRANCH", 16) + "  " + pad("PROJECT", 20) + "  TITLE"
    print(header)
    print("  " + String(repeating: "-", count: 92))
    for s in rows {
        let tag = s.name != nil ? "*" : " "
        let ageStr = pad(humanAge(s.age()), 4, right: true)
        let msgStr = pad("\(s.messages)", 4, right: true)
        let branch = pad(String(s.branch.prefix(16)), 16)
        let proj = pad(String(s.project.prefix(20)), 20)
        let title = String(s.title.prefix(46))
        print("\(statusGlyph(s))\(tag)\(ageStr)  \(msgStr)  \(branch)  \(proj)  \(title)")
    }
    print("")
}

private func pad(_ s: String, _ width: Int, right: Bool = false) -> String {
    if s.count >= width { return s }
    let padding = String(repeating: " ", count: width - s.count)
    return right ? padding + s : s + padding
}

// MARK: - pick

struct Pick: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "interactive multiselect -> resurrect")

    @Flag(name: .long) var here = false
    @Flag(name: .long) var active = false
    @Option(name: .customShort("n")) var n: Int = 30

    func run() throws {
        let sessions = AgentRegistry.discoverAll()
        ResCore.Snapshot.write(sessions)
        let rows = filtered(sessions, Filters(here: here, active: active, n: n))
        if rows.isEmpty {
            print("No sessions found.")
            return
        }
        let chosen = Picker.run(rows)
        if chosen.isEmpty {
            print("Nothing selected.")
            return
        }
        let index = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        for sid in chosen {
            if let s = index[sid] {
                Launcher.open(cwd: s.cwd, resume: resumeFor(s))
            }
        }
        print("Resurrected \(chosen.count) session(s).")
    }
}

// MARK: - open

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "resurrect session(s) by id")

    @Argument(help: "session id(s) (unique prefix accepted)") var ids: [String]
    @Flag(name: .long) var dryRun = false

    func run() throws {
        let index = Dictionary(
            AgentRegistry.discoverAll().map { ($0.id, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        var rc: Int32 = 0
        for sid in ids {
            guard let s = index[sid] ?? prefixMatch(index, sid) else {
                FileHandle.standardError.write(Data("No session matching '\(sid)'\n".utf8))
                rc = 1
                continue
            }
            Launcher.open(cwd: s.cwd, resume: resumeFor(s), dryRun: dryRun)
        }
        if rc != 0 { throw ExitCode(rc) }
    }
}

// MARK: - snapshot

struct Snapshot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot", abstract: "record current live set")

    func run() throws {
        let n = ResCore.Snapshot.write(AgentRegistry.discoverAll())
        print("Snapshot: \(n) live session(s) -> \(ResCore.Snapshot.lastLive)")
    }
}

// MARK: - restore

struct Restore: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "resurrect the last live set (reboot path)")

    @Flag(name: .long, help: "choose a subset first") var pick = false

    func run() throws {
        var saved = ResCore.Snapshot.read()
        if saved.isEmpty {
            print("No saved live set yet. Run `res snapshot` while sessions are running.")
            throw ExitCode(1)
        }
        if pick {
            // Build placeholder Sessions to reuse the picker.
            let placeholders: [Session] = saved.map { e in
                Session(
                    id: e.id, agent: e.agent, title: e.title, name: e.name,
                    aiTitle: nil, branch: "-", cwd: e.cwd,
                    project: ((e.cwd as NSString).lastPathComponent),
                    messages: 0, mtime: Date().timeIntervalSince1970,
                    status: nil, pid: nil, live: true
                )
            }
            let chosen = Set(Picker.run(placeholders))
            saved = saved.filter { chosen.contains($0.id) }
            if saved.isEmpty {
                print("Nothing selected.")
                return
            }
        }
        for e in saved {
            guard let agent = AgentRegistry.agent(byName: e.agent) else { continue }
            Launcher.open(cwd: e.cwd, resume: agent.resumeCommand(e.id, name: e.name))
        }
        print("Resurrected \(saved.count) session(s).")
    }
}

// MARK: - agents

struct Agents: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "list available agent adapters")

    func run() throws {
        print("Available agents:")
        for a in AgentRegistry.availableAgents() {
            let name = a.name.padding(toLength: 14, withPad: " ", startingAt: 0)
            print("  \u{2022} \(name) \(a.display)")
        }
    }
}

// MARK: - terminals

struct Terminals: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "list available terminal adapters")

    func run() throws {
        let selected = TerminalRegistry.selectedTerminal()
        print("Available terminals:")
        for t in TerminalRegistry.availableTerminals() {
            let marker = t.name == selected.name ? "*" : " "
            let name = t.name.padding(toLength: 14, withPad: " ", startingAt: 0)
            print("  \(marker) \(name) \(t.display)")
        }
        print("")
        print("Selected: \(selected.display)")
    }
}

// MARK: - menubar (force UI)

struct Menubar: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "launch the menu-bar app")

    func run() throws {
        runMenuBarApp()
    }
}

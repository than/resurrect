import Foundation
import SwiftUI
import AppKit
import ResCore

/// Observable model that polls ResCore.discoverAll() IN-PROCESS on a background
/// task and publishes results on the main actor. MainActor-isolated so all
/// published state is touched on the main thread (Swift 6 safe).
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var available: Bool = true

    private var pollTask: Task<Void, Never>?
    private let pollInterval: UInt64 = 4_000_000_000  // 4s in ns

    var liveSessions: [Session] { sessions.filter { $0.live } }
    var liveCount: Int { liveSessions.count }

    /// Menu-bar title: 🥌 with the live count, or just 🥌 when zero.
    var menuBarTitle: String {
        liveCount > 0 ? "\u{1F94C} \(liveCount)" : "\u{1F94C}"
    }

    /// Rows: all live sessions first (newest), then recent, capped 12.
    var menuRows: [Session] {
        let live = liveSessions.sorted { $0.mtime > $1.mtime }
        let liveIDs = Set(live.map { $0.id })
        let recent = sessions
            .filter { !liveIDs.contains($0.id) }
            .sorted { $0.mtime > $1.mtime }
        return Array((live + recent).prefix(12))
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: self?.pollInterval ?? 4_000_000_000)
            }
        }
    }

    func refresh() {
        Task { await poll() }
    }

    /// Discover off the main actor, then publish.
    private func poll() async {
        let result: [Session]? = await Task.detached(priority: .utility) {
            AgentRegistry.discoverAll()
        }.value
        if let result {
            sessions = result
            ResCore.Snapshot.write(result)  // opportunistic snapshot
            available = true
        } else {
            available = false
        }
    }

    // MARK: - Actions

    func open(_ session: Session) {
        let cwd = session.cwd
        let resume = resumeFor(session)
        Task.detached(priority: .userInitiated) {
            Launcher.open(cwd: cwd, resume: resume)
        }
        Task { await poll() }
    }

    func restore() {
        Task.detached(priority: .userInitiated) {
            let saved = ResCore.Snapshot.read()
            for e in saved {
                guard let agent = AgentRegistry.agent(byName: e.agent) else { continue }
                Launcher.open(cwd: e.cwd, resume: agent.resumeCommand(e.id, name: e.name))
            }
        }
        Task { await poll() }
    }

    /// Open `res pick` in a fresh Ghostty window (TUI needs a real terminal).
    func openPicker() {
        let app = ProcessInfo.processInfo.environment["RES_TERMINAL"] ?? "Ghostty.app"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [
            "-na", app,
            "--args", "-e", "zsh", "-lc", "res pick; exec zsh -l",
        ]
        try? task.run()
    }

    private func resumeFor(_ session: Session) -> String {
        if let agent = AgentRegistry.agent(byName: session.agent) {
            return agent.resumeCommand(session.id, name: session.name)
        }
        return "# unknown agent \(session.agent)"
    }
}

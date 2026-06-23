import Foundation
import SwiftUI

/// Observable model that polls `res list --json` on a background queue and
/// publishes results to the UI on the main actor. MainActor-isolated so all
/// published state is touched on the main thread (Swift 6 safe).
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var available: Bool = true

    private var timer: Timer?
    private let pollInterval: TimeInterval = 4.0

    /// Sessions where live == true.
    var liveSessions: [Session] { sessions.filter { $0.live } }
    var liveCount: Int { liveSessions.count }

    /// Menu-bar title: 🥌 with the live count, or just 🥌 when zero.
    var menuBarTitle: String {
        liveCount > 0 ? "\u{1F94C} \(liveCount)" : "\u{1F94C}"
    }

    /// Rows to render: all live sessions first, then recent ones, capped ~12.
    var menuRows: [Session] {
        let live = liveSessions.sorted { $0.mtime > $1.mtime }
        let liveIDs = Set(live.map { $0.id })
        let recent = sessions
            .filter { !liveIDs.contains($0.id) }
            .sorted { $0.mtime > $1.mtime }
        return Array((live + recent).prefix(12))
    }

    func start() {
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // Timer fires on main run loop; hop into the actor explicitly.
            Task { @MainActor in self?.refresh() }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// Kick off a poll. Subprocess runs off the main thread; results are
    /// published back on the main actor.
    func refresh() {
        Task.detached(priority: .utility) {
            do {
                let result = try ResCLI.list()
                await MainActor.run {
                    self.sessions = result
                    self.available = true
                }
            } catch {
                await MainActor.run {
                    self.available = false
                }
            }
        }
    }

    // MARK: - Actions (each fires-and-forgets off the main thread)

    func open(_ session: Session) {
        Task.detached(priority: .userInitiated) {
            try? ResCLI.open(id: session.id)
            // Reflect new live state shortly after.
            await MainActor.run { self.refresh() }
        }
    }

    func restore() {
        Task.detached(priority: .userInitiated) {
            try? ResCLI.restore()
            await MainActor.run { self.refresh() }
        }
    }

    func openPicker() {
        ResCLI.openPicker()
    }
}

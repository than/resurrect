import Foundation

/// The adapter contract every coding agent implements.
///
/// To add support for a new agent, create a type conforming to `CodingAgent`
/// and register it in `AgentRegistry`. Everything else — terminal relaunch,
/// liveness rejection, snapshot/restore, the picker, the menu bar — is handled
/// generically by the core.
public protocol CodingAgent: Sendable {
    /// machine-readable id, e.g. "claude-code"
    var name: String { get }
    /// human-readable label, e.g. "Claude Code"
    var display: String { get }

    /// True if this agent is usable on this machine (installed and/or has a
    /// session store present).
    func available() -> Bool

    /// Return all known sessions for this agent, tagged with agent == self.name.
    func discover() -> [Session]

    /// Shell command that resumes `sessionId` in a new terminal window. Must be
    /// safe to drop into a shell line (quote arguments).
    func resumeCommand(_ sessionId: String, name: String?) -> String
}

extension CodingAgent {
    public func resumeCommand(_ sessionId: String) -> String {
        resumeCommand(sessionId, name: nil)
    }
}

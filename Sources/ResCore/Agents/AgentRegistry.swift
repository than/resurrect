import Foundation

/// Agent adapter registry. Register new adapters in `allAgents`.
public enum AgentRegistry {
    public static var allAgents: [CodingAgent] {
        [ClaudeCodeAgent()]
    }

    public static func availableAgents() -> [CodingAgent] {
        allAgents.filter { $0.available() }
    }

    public static func agent(byName name: String) -> CodingAgent? {
        allAgents.first { $0.name == name }
    }

    /// All sessions across every available agent, newest first (by mtime desc).
    public static func discoverAll() -> [Session] {
        var sessions: [Session] = []
        for agent in availableAgents() {
            sessions.append(contentsOf: agent.discover())
        }
        sessions.sort { $0.mtime > $1.mtime }
        return sessions
    }
}

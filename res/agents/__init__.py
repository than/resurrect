"""Agent adapter registry.

Register new adapters here. ``res`` will automatically include any agent whose
``available()`` returns True.
"""
from __future__ import annotations

from ..core import Session
from .base import CodingAgent
from .claude_code import ClaudeCodeAgent

# Add new adapters to this list (e.g. CodexAgent(), GeminiAgent(), AiderAgent()).
ALL_AGENTS: list[CodingAgent] = [
    ClaudeCodeAgent(),
]


def available_agents() -> list[CodingAgent]:
    return [a for a in ALL_AGENTS if a.available()]


def get_agent(name: str) -> CodingAgent | None:
    for a in ALL_AGENTS:
        if a.name == name:
            return a
    return None


def discover_all() -> list[Session]:
    """All sessions across every available agent, newest first."""
    sessions: list[Session] = []
    for agent in available_agents():
        try:
            sessions.extend(agent.discover())
        except Exception:
            continue
    sessions.sort(key=lambda s: s.mtime, reverse=True)
    return sessions

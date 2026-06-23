"""The adapter contract every coding agent implements.

To add support for a new agent (Codex CLI, Gemini CLI, Aider, …), create a
module in this package with a subclass of :class:`CodingAgent` and register it
in ``res/agents/__init__.py``. You implement three things:

* ``available()``  — is this agent installed / does it have any sessions here?
* ``discover()``   — enumerate its sessions as :class:`res.core.Session` objects
                     (set ``status``/``pid``/``live`` using ``core.pid_alive``).
* ``resume_command(session_id, name)`` — the shell command that resumes a
                     session in a fresh terminal (e.g. ``codex resume <id>``).

Everything else — terminal relaunch, liveness rejection, snapshot/restore, the
picker, the menu bar — is handled generically by the core.
"""
from __future__ import annotations

from abc import ABC, abstractmethod

from ..core import Session


class CodingAgent(ABC):
    #: machine-readable id, e.g. "claude-code"
    name: str = ""
    #: human-readable label, e.g. "Claude Code"
    display: str = ""

    @abstractmethod
    def available(self) -> bool:
        """True if this agent is usable on this machine (installed and/or has
        a session store present)."""

    @abstractmethod
    def discover(self) -> list[Session]:
        """Return all known sessions for this agent, tagged with ``agent=self.name``."""

    @abstractmethod
    def resume_command(self, session_id: str, name: str | None = None) -> str:
        """Shell command that resumes ``session_id`` in a new terminal window.
        Must be safe to drop into a shell line (quote arguments)."""

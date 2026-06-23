"""res core — agent-agnostic session model, liveness, snapshot, and launching.

Everything here is independent of which coding agent produced a session. The
per-agent specifics (where sessions live, how to resume one) live in
``res.agents``. Keeping this split is what makes ``res`` pluggable: a new agent
is a new adapter, not a change here.
"""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import time
from dataclasses import asdict, dataclass

HOME = os.path.expanduser("~")

# Agent-neutral state dir (XDG state home). Holds the last-live snapshot used by
# `res restore`. Deliberately NOT under ~/.claude — res is multi-agent.
STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state")), "res"
)
LAST_LIVE = os.path.join(STATE_DIR, "last-live.json")

# Terminal indirection so swapping terminals is a one-line change.
TERMINAL_APP = os.environ.get("RES_TERMINAL", "Ghostty.app")
ACTIVE_WINDOW_MIN = int(os.environ.get("RES_ACTIVE_WINDOW", "10"))  # minutes


@dataclass
class Session:
    """One resumable coding-agent conversation."""
    id: str
    agent: str              # adapter name, e.g. "claude-code"
    title: str
    name: str | None        # manual rename, if the agent supports it
    ai_title: str | None    # auto-generated title, if any
    branch: str
    cwd: str
    project: str
    messages: int
    mtime: float
    status: str | None      # "busy" | "idle" | None (only when live)
    pid: int | None
    live: bool

    def age(self) -> float:
        return max(0.0, time.time() - self.mtime)


# --------------------------------------------------------------------------- #
# Liveness — shared helper used by adapters
# --------------------------------------------------------------------------- #
def pid_alive(pid) -> bool:
    """True if the process is currently running. Lets adapters reject stale
    'running' records left behind by a crash or reboot."""
    if not pid:
        return False
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError):
        return False


# --------------------------------------------------------------------------- #
# Snapshot / restore (no daemon)
# --------------------------------------------------------------------------- #
def write_snapshot(sessions: list[Session]) -> int:
    """Persist the current live set so `res restore` can resurrect it after a
    reboot or an accidental "quit all windows". Never writes an empty set, so a
    reboot (0 live) can't clobber the last good snapshot."""
    live = [s for s in sessions if s.live]
    if not live:
        return 0
    os.makedirs(STATE_DIR, exist_ok=True)
    payload = {
        "saved_at": time.time(),
        "sessions": [
            {"agent": s.agent, "id": s.id, "title": s.title, "cwd": s.cwd, "name": s.name}
            for s in live
        ],
    }
    tmp = LAST_LIVE + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(payload, fh, indent=2)
    os.replace(tmp, LAST_LIVE)
    return len(live)


def read_snapshot() -> list[dict]:
    try:
        with open(LAST_LIVE) as fh:
            return json.load(fh).get("sessions", [])
    except Exception:
        return []


# --------------------------------------------------------------------------- #
# Launcher
# --------------------------------------------------------------------------- #
def launch_argv(cwd: str, resume: str) -> list[str]:
    """argv that opens a new terminal window and runs ``resume`` in ``cwd``.

    ``resume`` is the agent-specific command (e.g. ``claude --resume <id>``)
    supplied by the adapter. Verified primitive on macOS/Ghostty: ``-n`` is
    required to deliver ``-e`` and spawns a separate instance per window (one
    dock icon each) — accepted tradeoff. ``exec zsh -l`` keeps the window alive
    after the conversation exits.
    """
    inner = f"cd {shlex.quote(cwd or HOME)}; {resume}; exec zsh -l"
    return ["open", "-na", TERMINAL_APP, "--args", "-e", "zsh", "-lc", inner]


def open_launch(cwd: str, resume: str, dry_run: bool = False) -> None:
    argv = launch_argv(cwd, resume)
    if dry_run:
        print(" ".join(shlex.quote(a) for a in argv))
        return
    subprocess.run(argv, check=False)


# --------------------------------------------------------------------------- #
# Rendering
# --------------------------------------------------------------------------- #
def human_age(secs: float) -> str:
    if secs < 60:
        return f"{int(secs)}s"
    if secs < 3600:
        return f"{int(secs // 60)}m"
    if secs < 86400:
        return f"{int(secs // 3600)}h"
    return f"{int(secs // 86400)}d"


def status_glyph(s: Session) -> str:
    if s.status == "busy":
        return "◉"   # running, working
    if s.status == "idle":
        return "○"   # running, waiting on you
    if s.age() <= ACTIVE_WINDOW_MIN * 60:
        return "●"   # touched recently, no live process
    return " "


def session_dict(s: Session) -> dict:
    d = asdict(s)
    d["age"] = round(s.age())
    return d

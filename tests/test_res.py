"""Tests for res: Claude adapter discovery/liveness/titles, core snapshot + launch.

Run:  cd ~/res && uv run --with pytest python -m pytest tests/ -q
"""
import json
import os

import pytest

from res import core
from res.agents import claude_code as cc
from res.agents.claude_code import ClaudeCodeAgent


@pytest.fixture
def env(tmp_path, monkeypatch):
    projects = tmp_path / "projects"
    sessions = tmp_path / "sessions"
    state = tmp_path / "state"
    (projects / "proj").mkdir(parents=True)
    sessions.mkdir()
    monkeypatch.setattr(cc, "PROJECTS", str(projects))
    monkeypatch.setattr(cc, "SESSIONS", str(sessions))
    monkeypatch.setattr(core, "STATE_DIR", str(state))
    monkeypatch.setattr(core, "LAST_LIVE", str(state / "last-live.json"))
    return {"projects": projects, "sessions": sessions}


def write_transcript(env, sid, *, ai_title=None, first_prompt=None,
                     cwd="/Users/dev/proj", branch="main", msgs=1):
    lines = []
    if ai_title:
        lines.append({"type": "ai-title", "sessionId": sid, "aiTitle": ai_title})
    if first_prompt is not None:
        lines.append({"type": "user", "sessionId": sid, "cwd": cwd, "gitBranch": branch,
                      "message": {"content": first_prompt}})
        msgs = max(0, msgs - 1)
    for _ in range(msgs):
        lines.append({"type": "assistant", "sessionId": sid, "cwd": cwd, "gitBranch": branch,
                      "message": {"content": "ok"}})
    (env["projects"] / "proj" / f"{sid}.jsonl").write_text(
        "\n".join(json.dumps(x) for x in lines) + "\n")


def write_registry(env, sid, *, pid, status="idle", name=None, updated=1000):
    entry = {"sessionId": sid, "pid": pid, "status": status, "updatedAt": updated,
             "cwd": "/Users/dev/proj"}
    if name:
        entry["name"] = name
    (env["sessions"] / f"{pid}.json").write_text(json.dumps(entry))


def discover(env):
    return {s.id: s for s in ClaudeCodeAgent().discover()}


# --- liveness -------------------------------------------------------------- #
def test_live_when_pid_alive(env):
    write_transcript(env, "live", ai_title="Live")
    write_registry(env, "live", pid=os.getpid(), status="busy")
    s = discover(env)["live"]
    assert s.live and s.status == "busy" and s.agent == "claude-code"


def test_not_live_when_pid_dead(env):
    write_transcript(env, "stale", ai_title="Stale")
    write_registry(env, "stale", pid=999999, status="idle")
    s = discover(env)["stale"]
    assert s.live is False and s.status is None


def test_not_live_without_registry(env):
    write_transcript(env, "orphan", ai_title="Orphan")
    assert discover(env)["orphan"].live is False


# --- title precedence ------------------------------------------------------ #
def test_manual_name_wins(env):
    write_transcript(env, "s1", ai_title="Auto", first_prompt="hi")
    write_registry(env, "s1", pid=os.getpid(), name="Manual 🏒")
    assert discover(env)["s1"].title == "Manual 🏒"


def test_ai_title_then_prompt(env):
    write_transcript(env, "s2", ai_title="Auto", first_prompt="hi")
    write_transcript(env, "s3", first_prompt="real first prompt")
    d = discover(env)
    assert d["s2"].title == "Auto"
    assert d["s3"].title == "real first prompt"


def test_skips_system_reminder(env):
    write_transcript(env, "s4", first_prompt="<system-reminder>noise</system-reminder>")
    assert discover(env)["s4"].title == "(untitled)"


# --- resume command (adapter) --------------------------------------------- #
def test_resume_command_basic():
    assert ClaudeCodeAgent().resume_command("abc-123") == "claude --resume abc-123"


def test_resume_command_with_name():
    cmd = ClaudeCodeAgent().resume_command("abc-123", "Westside 🏒")
    assert cmd == "claude --resume abc-123 --name 'Westside 🏒'"


# --- snapshot / restore (core) -------------------------------------------- #
def test_snapshot_round_trip(env):
    write_transcript(env, "l1", ai_title="L1")
    write_registry(env, "l1", pid=os.getpid(), status="busy")
    assert core.write_snapshot(ClaudeCodeAgent().discover()) == 1
    saved = core.read_snapshot()
    assert saved[0]["id"] == "l1" and saved[0]["agent"] == "claude-code"


def test_snapshot_no_clobber_on_empty(env):
    write_transcript(env, "d1", ai_title="Dead")
    write_registry(env, "d1", pid=999999, status="idle")
    os.makedirs(core.STATE_DIR, exist_ok=True)
    with open(core.LAST_LIVE, "w") as fh:
        json.dump({"sessions": [{"id": "earlier", "agent": "claude-code", "cwd": "/x"}]}, fh)
    assert core.write_snapshot(ClaudeCodeAgent().discover()) == 0
    assert core.read_snapshot()[0]["id"] == "earlier"


# --- launch argv (core) ---------------------------------------------------- #
def test_launch_argv():
    argv = core.launch_argv("/Users/dev/proj", "claude --resume abc-123")
    assert argv[:5] == ["open", "-na", "Ghostty.app", "--args", "-e"]
    assert "cd /Users/dev/proj" in argv[-1]
    assert argv[-1].endswith("exec zsh -l")


def test_launch_argv_quotes_spacey_cwd():
    argv = core.launch_argv("/Users/dev/My Deals", "claude --resume x")
    assert "'/Users/dev/My Deals'" in argv[-1]

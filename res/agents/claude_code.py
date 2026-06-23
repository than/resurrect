"""Claude Code adapter.

Sessions are reconstructed by joining two on-disk sources on ``sessionId``:

* ``~/.claude/projects/<slug>/<uuid>.jsonl`` — transcripts. Carry the auto title
  (``ai-title`` line), and per-message ``cwd`` / ``gitBranch`` / counts.
* ``~/.claude/sessions/<pid>.json`` — the live registry. Carries ``status``
  (busy/idle), ``pid``, and the manual ``/rename`` ``name``.

Title precedence: manual name → auto aiTitle → first non-``<…>`` user prompt.
Liveness requires the registry status AND a running pid (rejects stale records).
"""
from __future__ import annotations

import glob
import json
import os
import shlex

from ..core import HOME, Session, pid_alive

CLAUDE_DIR = os.path.join(HOME, ".claude")
PROJECTS = os.path.join(CLAUDE_DIR, "projects")
SESSIONS = os.path.join(CLAUDE_DIR, "sessions")


class ClaudeCodeAgent:
    name = "claude-code"
    display = "Claude Code"

    def available(self) -> bool:
        return os.path.isdir(PROJECTS)

    # -- discovery --------------------------------------------------------- #
    def discover(self) -> list[Session]:
        reg = self._load_registry()
        out: list[Session] = []
        for path in glob.glob(os.path.join(PROJECTS, "*", "*.jsonl")):
            t = self._scan_transcript(path)
            if not t:
                continue
            entry = reg.get(t["id"])
            name = entry.get("name") if entry else None
            live = self._is_live(entry)
            title = (
                name
                or t["ai_title"]
                or (t["first_prompt"] or "").strip().split("\n")[0][:60]
                or "(untitled)"
            )
            proj = os.path.basename(t["cwd"].rstrip("/")) if t["cwd"] != "-" else "-"
            out.append(Session(
                id=t["id"], agent=self.name, title=title, name=name,
                ai_title=t["ai_title"], branch=t["branch"], cwd=t["cwd"], project=proj,
                messages=t["messages"], mtime=t["mtime"],
                status=(entry.get("status") if live else None),
                pid=(entry.get("pid") if live else None), live=live,
            ))
        return out

    # -- resume ------------------------------------------------------------ #
    def resume_command(self, session_id: str, name: str | None = None) -> str:
        cmd = f"claude --resume {shlex.quote(session_id)}"
        if name:
            cmd += f" --name {shlex.quote(name)}"
        return cmd

    # -- internals --------------------------------------------------------- #
    @staticmethod
    def _is_live(entry: dict | None) -> bool:
        return bool(entry) and entry.get("status") in ("busy", "idle") and pid_alive(entry.get("pid"))

    @staticmethod
    def _load_registry() -> dict[str, dict]:
        reg: dict[str, dict] = {}
        for p in glob.glob(os.path.join(SESSIONS, "*.json")):
            try:
                with open(p) as fh:
                    d = json.load(fh)
            except Exception:
                continue
            sid = d.get("sessionId")
            if not sid:
                continue
            prev = reg.get(sid)
            if prev is None or d.get("updatedAt", 0) >= prev.get("updatedAt", 0):
                reg[sid] = d
        return reg

    @staticmethod
    def _scan_transcript(path: str) -> dict | None:
        title = branch = cwd = first_prompt = None
        msgs = 0
        try:
            with open(path, "r") as fh:
                for line in fh:
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    typ = d.get("type")
                    if typ == "ai-title":
                        title = d.get("aiTitle")
                    elif typ in ("user", "assistant"):
                        msgs += 1
                        branch = d.get("gitBranch") or branch
                        cwd = d.get("cwd") or cwd
                        if typ == "user" and first_prompt is None:
                            txt = _text_of(d.get("message"))
                            if txt and not txt.lstrip().startswith("<"):
                                first_prompt = txt
        except Exception:
            return None
        return {
            "id": os.path.basename(path)[:-6],
            "ai_title": title,
            "first_prompt": first_prompt,
            "branch": branch or "-",
            "cwd": cwd or "-",
            "messages": msgs,
            "mtime": os.path.getmtime(path),
        }


def _text_of(message) -> str | None:
    if not isinstance(message, dict):
        return None
    c = message.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        for blk in c:
            if isinstance(blk, dict) and blk.get("type") == "text":
                return blk.get("text")
    return None

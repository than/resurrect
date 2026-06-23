"""res — resurrect your coding-agent sessions.

Surfaces active / recent AI coding-agent conversations and reopens any of them
in a fresh terminal window, resumed and ready. Agent-agnostic via adapters
(see ``res.agents``); ships with a Claude Code adapter.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile

from . import core
from .agents import available_agents, discover_all, get_agent

# The Laravel Prompts picker (presentation only). Override with RES_PICKER.
PICKER = os.environ.get(
    "RES_PICKER",
    os.path.join(os.path.dirname(os.path.dirname(__file__)), "picker", "pick.php"),
)


# --------------------------------------------------------------------------- #
# Filtering
# --------------------------------------------------------------------------- #
def _filtered(sessions, args):
    rows = sessions
    if getattr(args, "here", False):
        cwd = os.getcwd()
        rows = [s for s in rows if s.cwd == cwd]
    if getattr(args, "active", False):
        rows = [s for s in rows if s.live or s.age() <= core.ACTIVE_WINDOW_MIN * 60]
    n = getattr(args, "n", None)
    if n:
        rows = rows[:n]
    return rows


def _resume_for(session) -> str:
    agent = get_agent(session.agent)
    return agent.resume_command(session.id, session.name) if agent else f"# unknown agent {session.agent}"


# --------------------------------------------------------------------------- #
# Subcommands
# --------------------------------------------------------------------------- #
def cmd_list(args) -> int:
    sessions = discover_all()
    core.write_snapshot(sessions)  # opportunistic: keep last-live fresh
    rows = _filtered(sessions, args)
    if args.json:
        print(json.dumps([core.session_dict(s) for s in rows], indent=2))
    else:
        _render_table(rows)
    return 0


def cmd_open(args) -> int:
    index = {s.id: s for s in discover_all()}
    rc = 0
    for sid in args.ids:
        s = index.get(sid) or _prefix_match(index, sid)
        if not s:
            print(f"No session matching '{sid}'", file=sys.stderr)
            rc = 1
            continue
        core.open_launch(s.cwd, _resume_for(s), dry_run=args.dry_run)
    return rc


def cmd_snapshot(args) -> int:
    n = core.write_snapshot(discover_all())
    print(f"Snapshot: {n} live session(s) -> {core.LAST_LIVE}")
    return 0


def cmd_restore(args) -> int:
    saved = core.read_snapshot()
    if not saved:
        print("No saved live set yet. Run `res snapshot` while sessions are running.")
        return 1
    if args.pick:
        chosen = _run_picker([
            {"id": e["id"], "label": e.get("title", e["id"]),
             "hint": os.path.basename((e.get("cwd") or "-").rstrip("/")), "checked": True}
            for e in saved
        ])
        by_id = {e["id"]: e for e in saved}
        saved = [by_id[c] for c in chosen if c in by_id]
        if not saved:
            print("Nothing selected.")
            return 0
    for e in saved:
        agent = get_agent(e.get("agent", "claude-code"))
        if not agent:
            continue
        core.open_launch(e.get("cwd", core.HOME), agent.resume_command(e["id"], e.get("name")))
    print(f"Resurrected {len(saved)} session(s).")
    return 0


def cmd_pick(args) -> int:
    sessions = discover_all()
    core.write_snapshot(sessions)
    rows = _filtered(sessions, args)
    if not rows:
        print("No sessions found.")
        return 0
    multi = len({s.agent for s in rows}) > 1
    items = []
    for s in rows:
        badge = f"[{s.agent}] " if multi else ""
        items.append({
            "id": s.id,
            "label": f"{core.status_glyph(s)} {badge}{s.title}",
            "hint": f"{s.project} · {core.human_age(s.age())}",
            "checked": s.live,
        })
    chosen = _run_picker(items)
    if not chosen:
        print("Nothing selected.")
        return 0
    index = {s.id: s for s in rows}
    for sid in chosen:
        s = index.get(sid)
        if s:
            core.open_launch(s.cwd, _resume_for(s))
    print(f"Resurrected {len(chosen)} session(s).")
    return 0


def cmd_agents(args) -> int:
    print("Available agents:")
    for a in available_agents():
        print(f"  • {a.name:<14} {a.display}")
    return 0


# --------------------------------------------------------------------------- #
# Picker bridge (PHP / Laravel Prompts; UI on stderr, ids on stdout)
# --------------------------------------------------------------------------- #
def _run_picker(items: list[dict]) -> list[str]:
    """Show the interactive multiselect and return chosen ids.

    Items are passed via a temp file (stdin must stay a TTY so Laravel Prompts
    can read keys). The picker renders its UI to stderr and prints selected ids
    to stdout, which we capture. Falls back to a plain numbered prompt if PHP or
    the picker script isn't available."""
    if _have_php() and os.path.exists(PICKER):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            json.dump(items, fh)
            tmp = fh.name
        try:
            proc = subprocess.run(["php", PICKER, tmp], stdout=subprocess.PIPE)
            out = proc.stdout.decode().strip()
            return [line for line in out.splitlines() if line.strip()]
        finally:
            os.unlink(tmp)
    return _fallback_picker(items)


def _have_php() -> bool:
    from shutil import which
    return which("php") is not None


def _fallback_picker(items: list[dict]) -> list[str]:
    print("(install php for the Laravel Prompts UI — using plain picker)\n", file=sys.stderr)
    for i, it in enumerate(items, 1):
        mark = "x" if it.get("checked") else " "
        print(f"  {i:>2}) [{mark}] {it['label']}  {it.get('hint','')}", file=sys.stderr)
    try:
        raw = input("Numbers to open (space-separated, enter for checked): ").strip()
    except EOFError:
        return []
    if not raw:
        return [it["id"] for it in items if it.get("checked")]
    chosen = []
    for tok in raw.split():
        if tok.isdigit() and 1 <= int(tok) <= len(items):
            chosen.append(items[int(tok) - 1]["id"])
    return chosen


def _render_table(rows) -> None:
    live = sum(1 for s in rows if s.live)
    import time
    print(f"\n  Coding-agent sessions — {len(rows)} shown, {live} live  "
          f"{time.strftime('%H:%M:%S')}\n")
    print(f"   {'AGE':>4}  {'MSGS':>4}  {'BRANCH':<16}  {'PROJECT':<20}  TITLE")
    print("  " + "-" * 92)
    for s in rows:
        tag = "*" if s.name else " "
        print(f"{core.status_glyph(s)}{tag}{core.human_age(s.age()):>4}  {s.messages:>4}  "
              f"{s.branch[:16]:<16}  {s.project[:20]:<20}  {s.title[:46]}")
    print()


def _prefix_match(index, prefix):
    hits = [s for sid, s in index.items() if sid.startswith(prefix)]
    return hits[0] if len(hits) == 1 else None


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="res", description="Resurrect your coding-agent sessions")
    sub = p.add_subparsers(dest="cmd")

    pl = sub.add_parser("list", help="list sessions (table or --json)")
    pl.add_argument("--json", action="store_true")
    pl.add_argument("--active", action="store_true", help="only live/recent")
    pl.add_argument("--here", action="store_true", help="only this directory")
    pl.add_argument("-n", type=int, default=30, help="max rows")
    pl.set_defaults(func=cmd_list)

    pp = sub.add_parser("pick", help="interactive multiselect -> resurrect")
    pp.add_argument("--here", action="store_true")
    pp.add_argument("--active", action="store_true")
    pp.add_argument("-n", type=int, default=30)
    pp.set_defaults(func=cmd_pick)

    po = sub.add_parser("open", help="resurrect session(s) by id")
    po.add_argument("ids", nargs="+")
    po.add_argument("--dry-run", action="store_true")
    po.set_defaults(func=cmd_open)

    ps = sub.add_parser("snapshot", help="record current live set")
    ps.set_defaults(func=cmd_snapshot)

    pr = sub.add_parser("restore", help="resurrect the last live set (reboot path)")
    pr.add_argument("--pick", action="store_true", help="choose a subset first")
    pr.set_defaults(func=cmd_restore)

    pa = sub.add_parser("agents", help="list available agent adapters")
    pa.set_defaults(func=cmd_agents)

    return p


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "func", None):
        return cmd_pick(parser.parse_args(["pick"]))  # bare `res` -> picker
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

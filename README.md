# res — resurrect your coding-agent sessions

`res` surfaces your active and recent AI coding-agent conversations and brings any
of them back to life in a fresh terminal window — resumed and ready. Reboot your
machine, or accidentally quit every terminal, and `res restore` puts your
workspace back the way it was.

It's **agent-agnostic**: a small adapter describes where one coding agent keeps
its sessions and how to resume one. `res` ships with a **Claude Code** adapter;
adding Codex CLI, Gemini CLI, Aider, etc. is a single file (see *Adding an agent*).

The name is three left-hand keys (r-e-s, one-handed) and short for *resume /
restore / resurrect*.

## How it works

For each agent, `res` reconstructs sessions from on-disk data and decides which
are truly live:

- **Title** comes from the agent's metadata (manual rename → auto title → first
  prompt).
- **Liveness** requires both a "running" marker *and* a process that's actually
  alive (`os.kill(pid, 0)`) — so sessions left behind by a crash, a reboot, or
  quitting your terminal are correctly shown as not-live.

Reopening a session launches a new terminal window running the agent's resume
command in the session's original directory.

## Components

| Piece | Tech | Role |
|---|---|---|
| `res` CLI | Python package (stdlib only) | the brain: discovery, liveness, snapshot/restore, launch |
| `picker/` | PHP + [Laravel Prompts](https://laravel.com/docs/13.x/prompts) | the interactive multiselect TUI (presentation only) |
| `menubar/` | Swift `MenuBarExtra` | macOS menu-bar dropdown (thin client over the CLI) |

The picker renders its UI to **stderr** and prints chosen ids to **stdout**, so
the CLI stays the single source of truth for launching.

## Install

`res` is pure-stdlib Python (no runtime deps), but it must be installed so its
command has a **stable, absolute interpreter** — the menu-bar app launches it
without a shell PATH. `uv tool` or `pipx` both provide that; either is fine.

```sh
# from a clone (recommended for now)
uv tool install --editable .       # -> ~/.local/bin/res   (editable: edits take effect live)
# or
pipx install --editable .

# once published to PyPI
uv tool install resurrect          # or:  pipx install resurrect
```

> Avoid a bare `ln -s … python3` symlink: it depends on the *system* Python
> being ≥3.10, and macOS ships 3.9. Use uv/pipx so the shebang pins a good Python.

Picker UI (optional but recommended; needs PHP + Composer). Without it,
`res pick` falls back to a plain numbered prompt:

```sh
cd picker && composer install
```

## Usage

```sh
res list [--json] [--active] [--here] [-n N]   # table or JSON
res pick [--here] [--active]                   # Laravel Prompts multiselect -> launch
res open <id...> [--dry-run]                   # resurrect by id (prefixes ok)
res snapshot                                   # save current live set
res restore [--pick]                           # resurrect the last live set (reboot path)
res agents                                     # list available adapters
```

Status glyphs: `◉` busy · `○` idle (waiting on you) · `●` recently active · ` ` older.
A `*` marks a manually renamed session.

### Resurrect after a reboot

`res` keeps `~/.local/state/res/last-live.json` current (every `list`/`pick` and
every menu-bar poll re-snapshots the live set, but never overwrites it with an
empty set). After restarting:

```sh
res restore          # reopen everything that was live
res restore --pick   # choose a subset first
```

## Adding an agent

Create `res/agents/<agent>.py` with a subclass of `CodingAgent` implementing
three methods, then add it to `ALL_AGENTS` in `res/agents/__init__.py`:

```python
class CodexAgent(CodingAgent):
    name = "codex"
    display = "Codex CLI"

    def available(self) -> bool:
        return os.path.isdir(os.path.expanduser("~/.codex"))

    def discover(self) -> list[Session]:
        # parse this agent's session store; build Session objects tagged
        # agent=self.name; use core.pid_alive(pid) for liveness.
        ...

    def resume_command(self, session_id, name=None) -> str:
        return f"codex resume {shlex.quote(session_id)}"
```

Everything else — terminal relaunch, snapshot/restore, the picker, the menu bar —
works automatically for your agent. PRs welcome.

## Config (env vars)

- `RES_TERMINAL` — terminal app to launch (default `Ghostty.app`).
- `RES_ACTIVE_WINDOW` — minutes a session counts as "recently active" (default 10).
- `RES_PICKER` — path to `pick.php` (defaults to the bundled one).

## Launch primitive (macOS / Ghostty)

```sh
open -na Ghostty.app --args -e zsh -lc 'cd <cwd>; <resume cmd>; exec zsh -l'
```

`-n` is required to deliver `-e` and spawns a separate Ghostty instance per window
(one dock icon each) — accepted as a reliable default; a single-instance variant
may come later. `exec zsh -l` keeps the window alive after the conversation exits.

## Tests

```sh
cd ~/res && uv run --with pytest python -m pytest tests/ -q
```

# Contributing to res

Thanks for your interest! The most valuable contribution is **a new agent
adapter** so `res` can resurrect sessions from another coding agent.

## Add an agent adapter

`res` is agent-agnostic. The core (discovery orchestration, liveness,
snapshot/restore, the picker, the menu bar) is generic; each agent only needs a
small adapter.

1. Create `res/agents/<your_agent>.py` with a subclass of `CodingAgent`
   (`res/agents/base.py`) implementing three methods:
   - `available()` — is this agent installed / does it have a session store here?
   - `discover()` — enumerate sessions as `res.core.Session` objects, tagged
     `agent=self.name`. Use `res.core.pid_alive(pid)` for liveness.
   - `resume_command(session_id, name=None)` — the shell command that resumes a
     session in a fresh terminal (quote your arguments).
2. Register it in `ALL_AGENTS` in `res/agents/__init__.py`.
3. Add a test in `tests/` modeled on `tests/test_res.py` (point your adapter's
   storage paths at a tmp fixture dir via monkeypatch).

That's it — terminal relaunch, snapshot/restore, the picker, and the menu bar
all work for your agent automatically.

## Dev setup

```sh
uv tool install --editable .                         # installs `res`
cd picker && composer install                        # picker UI (optional)
uv run --with pytest python -m pytest tests/ -q      # run tests
```

The macOS menu-bar app builds with SwiftPM (no Xcode needed):

```sh
cd menubar && ./build-app.sh
```

## Guidelines

- Keep the core agent-agnostic — agent-specific logic belongs in an adapter.
- Stdlib-only for the Python core (the picker is the place for richer UI deps).
- Run the test suite before opening a PR.

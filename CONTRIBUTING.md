# Contributing to resurrect

Thanks for your interest! The highest-value contributions are **new adapters** —
either a coding agent or a terminal emulator.

`res` is one Swift package: a `ResCore` library (model, liveness, snapshot,
launcher, adapters) and a `res` executable (CLI + TUI picker + menu-bar app). The
core is generic; adapters are small.

## Add a coding-agent adapter

So `res` can resurrect sessions from another agent (Codex CLI, Gemini CLI, Aider…).

1. Add a type conforming to `CodingAgent` (`Sources/ResCore/Agents/CodingAgent.swift`):
   - `available()` — is the agent installed / does it have a session store?
   - `discover()` — enumerate sessions as `Session` values tagged `agent: name`;
     use `pidAlive(_:)` for liveness.
   - `resumeCommand(_:name:)` — the shell command that resumes a session
     (quote arguments with `shellQuote`).
2. Register it in `AgentRegistry` (`Sources/ResCore/Agents/AgentRegistry.swift`).
3. Add tests in `Tests/ResCoreTests/` (point storage paths at a temp fixture).

## Add a terminal adapter

So `res` can open windows in another terminal (iTerm2, kitty, WezTerm, Terminal.app…).

1. Add a type conforming to `Terminal` (`Sources/ResCore/Terminals/Terminal.swift`):
   - `available()` — is the terminal installed?
   - `launchArgv(cwd:command:)` — the argv that opens a new window running
     `command` in `cwd`.
   - `openWindow(cwd:command:dryRun:)` — run it (or print argv when `dryRun`).
2. Register it in `TerminalRegistry`.

Everything else — discovery, snapshot/restore, the picker, the menu bar — works
for your adapter automatically.

## Dev setup

```sh
swift build            # build CLI + menu bar
swift run res list     # try the CLI
swift test             # run the suite
./build-app.sh         # assemble Res.app
```

macOS + Swift toolchain (Xcode or Command Line Tools). No external runtime; the
only dependency is Apple's swift-argument-parser, resolved by SwiftPM.

## Guidelines

- Keep `ResCore` generic — agent/terminal specifics belong in an adapter.
- Run `swift build` and `swift test` before opening a PR.
- Match the existing file layout (one focused type per file).

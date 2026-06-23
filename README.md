# 🧟 Resurrect

> The command is `res`.

Resurrect your coding-agent sessions. `res` surfaces your active and recent AI coding-agent conversations and brings any of them back to life in a fresh terminal window — resumed and ready. Reboot your Mac? or accidentally quit every terminal? **Restore last state** brings the whole workspace back exactly as
it was.

One self-contained Swift binary is both the **CLI** and the **menu-bar app** — no
runtime to install, no subprocess bridge. The menu bar shows 🪦 when nothing's
running and 🧟 N when N sessions are alive.

The name: three left-hand keys (r‑e‑s, one-handed), short for _resume / restore /
resurrect_.

## Two adapter axes

`res` is generic over **what** you resume and **where** it opens:

- `CodingAgent` — _what to resume_. Ships with **Claude Code**; Codex CLI,
  Gemini CLI, Aider, etc. are each one small adapter.
- `Terminal` — _where/how to open the window_. Ships with **Ghostty**;
  iTerm2, kitty, WezTerm, Terminal.app, etc. are each one small adapter.

A launch is just: pick a `Terminal`, ask it to open a window running the
`CodingAgent`'s resume command in the session's directory.

## How it works

For each agent, `res` reconstructs sessions from on-disk data and decides which
are truly live:

- **Title** comes from the agent's metadata (manual rename → auto title → first
  prompt).
- **Liveness** requires both a "running" marker _and_ a process that's actually
  alive (`kill(pid, 0)`) — so sessions left behind by a crash, a reboot, or
  quitting your terminal are correctly shown as not-live.

## Install

> Notarized Homebrew distribution is planned: `brew install --cask than/tap/resurrect`.

From source (macOS, Swift toolchain via Xcode or Command Line Tools):

```sh
git clone https://github.com/than/resurrect && cd resurrect
swift build -c release            # builds the `res` binary
./build-app.sh                    # assembles Res.app + installs a (login) LaunchAgent

# put the CLI on your PATH
ln -sf "$PWD/.build/release/res" ~/.local/bin/res

# run the menu-bar app now / at login
open Res.app
launchctl load ~/Library/LaunchAgents/com.than.resurrect.plist
```

## Usage

```sh
res list [--json] [--active] [--here] [-n N]   # table or JSON
res pick [--here] [--active]                   # interactive multiselect TUI -> launch
res open <id...> [--dry-run]                   # resurrect by id (unique prefixes ok)
res snapshot                                   # save current live set
res restore [--pick]                           # bring back the last live set (reboot path)
res agents                                     # list available agent adapters
res terminals                                  # list terminal adapters (and the selected one)
```

Run bare `res` in a terminal for the picker; launched as `Res.app` it runs the
menu bar. Status glyphs: `◉` busy · `○` idle (waiting on you) · `●` recently
active · ` ` older. A `*` marks a manually renamed session.

### Restore after a reboot (or quitting everything)

`res` keeps `~/.local/state/res/last-live.json` current — every `list`/`pick` and
every menu-bar poll re-snapshots the live set, but never overwrites it with an
empty set. So after a restart, **Restore last state** (menu bar) or `res restore`
brings them all back.

## Adding an agent adapter

Conform to `CodingAgent` (`Sources/ResCore/Agents/CodingAgent.swift`) and register
it in `AgentRegistry`:

```swift
struct CodexAgent: CodingAgent {
    let name = "codex"
    let display = "Codex CLI"
    func available() -> Bool { /* e.g. ~/.codex exists */ }
    func discover() -> [Session] { /* parse store; tag agent: name; use pidAlive() */ }
    func resumeCommand(_ id: String, name: String?) -> String { "codex resume \(shellQuote(id))" }
}
```

## Adding a terminal adapter

Conform to `Terminal` (`Sources/ResCore/Terminals/Terminal.swift`) and register it
in `TerminalRegistry`:

```swift
struct ITermTerminal: Terminal {
    let name = "iterm2"
    let display = "iTerm2"
    func available() -> Bool { /* iTerm.app installed */ }
    func launchArgv(cwd: String, command: String) -> [String] { /* osascript ... */ }
    func openWindow(cwd: String, command: String, dryRun: Bool) { /* run or print argv */ }
}
```

Selection order: `RES_TERMINAL` → `$TERM_PROGRAM` (when run inside a terminal) →
first available → Ghostty.

## Compatibility

### Terminals

> **Only Ghostty is installed and verified.** The other rows reflect each
> terminal's *documented* capabilities — no adapter is built or tested for them
> yet. Treat them as a roadmap, not a promise; contributions (and corrections)
> welcome.

| Terminal | Status | Single-instance | Notes |
|---|---|---|---|
| **Ghostty** | ✅ shipped, verified | ❌ no *(verified)* | macOS Ghostty exposes no CLI/IPC to target a running instance, so each launch is a **separate app instance**. True single-instance would require driving it via Accessibility — TBD. |
| kitty | 📋 unbuilt, untested | likely *(per docs)* | `kitten @ launch` remote control — not yet verified here. |
| WezTerm | 📋 unbuilt, untested | likely *(per docs)* | `wezterm cli spawn` — not yet verified here. |
| iTerm2 | 📋 unbuilt, untested | likely *(per docs)* | AppleScript-scriptable — not yet verified here. |
| Apple Terminal | 📋 unbuilt, untested | likely *(per docs)* | AppleScript `do script` — not yet verified here. |

If single-instance matters to you, kitty/WezTerm look like the robust paths *on
paper* (their remote-control CLIs), but those adapters are unwritten and untested
— that's exactly the kind of contribution that'd help. (See
[Adding a terminal adapter](#adding-a-terminal-adapter).)

### Coding agents

| Agent | Status |
|---|---|
| **Claude Code** | ✅ shipped |
| Codex CLI, Gemini CLI, Aider, … | adapter welcome — see [Adding an agent adapter](#adding-an-agent-adapter) |

## Config (env vars)

- `RES_TERMINAL` — force a terminal adapter by name (default: auto-detect).
- `RES_ACTIVE_WINDOW` — minutes a session counts as "recently active" (default 10).

## Tests

```sh
swift test
```

> On **Command Line Tools only** (no full Xcode), the test target bakes in the
> CLT swift-testing plugin/rpath via `unsafeFlags` in `Package.swift` so a bare
> `swift test` works. The _product_ targets carry no such flags, so
> `swift build -c release` (what packaging uses) stays fully portable.

## Privacy & security

Everything stays on your machine. `res` only **reads local files** (your agent's
on-disk session data, e.g. `~/.claude/…`) and **launches local terminal windows**.
It makes no network requests, phones nothing home, and collects no telemetry — no
data ever leaves your device.

## License

MIT — see [LICENSE](LICENSE).

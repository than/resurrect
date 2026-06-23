import Foundation

/// Opens a session in a fresh terminal window via the selected terminal.
///
/// Launch-path decision (graceful, fallback ALWAYS works):
///   1. Resolve the terminal from Preferences (chosen) or env/$TERM_PROGRAM.
///   2. If single-instance is enabled (terminal supports it AND its required
///      permission is granted), try the single-instance path:
///        - .remoteControl  -> run the terminal's singleInstanceArgv (kitty/wez).
///        - .accessibility  -> Ghostty AX path (P5), best-effort.
///      Any failure falls through to (3).
///   3. Multi-instance fallback: the terminal's verified `open -na … -ilc` argv.
public enum Launcher {
    /// The argv that opens a new terminal window and runs `resume` in `cwd`,
    /// using the currently selected terminal adapter. This is always the SAFE
    /// multi-instance fallback argv. Exposed for tests.
    public static func launchArgv(cwd: String, resume: String) -> [String] {
        TerminalRegistry.selectedTerminal().launchArgv(cwd: cwd, command: resume)
    }

    /// Decide the launch path for the resolved terminal. Pure given the inputs;
    /// exposed for testing.
    public enum Path: Equatable {
        case multiInstance
        case remoteControl
        case ghosttyAccessibility
    }

    public static func decidePath(
        terminal: Terminal,
        singleInstanceEnabled: Bool
    ) -> Path {
        guard singleInstanceEnabled else { return .multiInstance }
        switch terminal.singleInstance {
        case .remoteControl:
            return .remoteControl
        case .accessibility:
            return .ghosttyAccessibility
        case .appleScript, .none:
            return .multiInstance
        }
    }

    /// Open a window resuming `resume` in `cwd`. dryRun prints the argv.
    public static func open(cwd: String, resume: String, dryRun: Bool = false) {
        let prefs = Preferences.shared
        let terminal = prefs.resolvedTerminal()
        let enabled = prefs.singleInstanceEnabled(
            for: terminal,
            permissionGranted: { Permissions.granted($0) }
        )
        let path = decidePath(terminal: terminal, singleInstanceEnabled: enabled)

        switch path {
        case .remoteControl:
            if let argv = terminal.singleInstanceArgv(cwd: cwd, command: resume) {
                if dryRun {
                    print(argv.map { shellQuote($0) }.joined(separator: " "))
                    return
                }
                if attemptRemoteControl(argv) { return }
            }
            // fall through to multi-instance
            terminal.openWindow(cwd: cwd, command: resume, dryRun: dryRun)

        case .ghosttyAccessibility:
            if dryRun {
                // Dry-run can't drive AX/keystrokes; show the safe fallback argv.
                print(terminal.launchArgv(cwd: cwd, command: resume)
                    .map { shellQuote($0) }.joined(separator: " "))
                return
            }
            #if canImport(AppKit)
            if GhosttyAccessibility.openInNewWindow(cwd: cwd, command: resume) { return }
            #endif
            // AX path failed / unavailable -> safe fallback.
            terminal.openWindow(cwd: cwd, command: resume, dryRun: dryRun)

        case .multiInstance:
            terminal.openWindow(cwd: cwd, command: resume, dryRun: dryRun)
        }
    }

    /// Run a remote-control argv; return true only if it exited 0. Never throws.
    private static func attemptRemoteControl(_ argv: [String]) -> Bool {
        guard let first = argv.first else { return false }
        let proc = Process()
        if first.hasPrefix("/") {
            proc.executableURL = URL(fileURLWithPath: first)
            proc.arguments = Array(argv.dropFirst())
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = argv
        }
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}

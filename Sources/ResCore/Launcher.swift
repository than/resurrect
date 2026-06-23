import Foundation

/// Opens a session in a fresh terminal window via the selected terminal.
public enum Launcher {
    /// The argv that opens a new terminal window and runs `resume` in `cwd`,
    /// using the currently selected terminal adapter. Exposed for tests.
    public static func launchArgv(cwd: String, resume: String) -> [String] {
        TerminalRegistry.selectedTerminal().launchArgv(cwd: cwd, command: resume)
    }

    /// Open a window resuming `resume` in `cwd`. dryRun prints the argv.
    public static func open(cwd: String, resume: String, dryRun: Bool = false) {
        TerminalRegistry.selectedTerminal().openWindow(cwd: cwd, command: resume, dryRun: dryRun)
    }
}

import Foundation

/// A terminal-emulator adapter. Knows how to open a new window running a
/// command in a working directory.
public protocol Terminal: Sendable {
    /// machine-readable id, e.g. "ghostty"
    var name: String { get }
    /// human-readable label, e.g. "Ghostty"
    var display: String { get }
    /// True if this terminal is usable on this machine.
    func available() -> Bool
    /// Open a new window in `cwd` running `command`. When `dryRun`, print the
    /// shell-quoted argv instead of launching.
    func openWindow(cwd: String, command: String, dryRun: Bool)
    /// The argv used to open the window (exposed for testing / dry-run).
    func launchArgv(cwd: String, command: String) -> [String]
}

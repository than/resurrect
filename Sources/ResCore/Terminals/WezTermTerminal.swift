import Foundation

/// WezTerm terminal adapter.
///
/// UNTESTED — wezterm is not installed on this machine. The launch shapes below
/// are based on wezterm's documented `wezterm cli spawn` CLI, not on a verified
/// run. Treat as runtime-unverified.
///
/// Single-instance launching uses wezterm's native multiplexer CLI. `wezterm
/// cli spawn` talks to the running GUI's mux server over its default unix
/// socket; if no GUI is running the command fails and the Launcher falls back
/// to the multi-instance `open -na` path. No macOS permission is required.
public struct WezTermTerminal: Terminal {
    public let name = "wezterm"
    public let display = "WezTerm"

    public let app: String

    public init(app: String = "WezTerm.app") {
        self.app = app
    }

    public var singleInstance: SingleInstanceMechanism { .remoteControl }
    public var requiredPermission: TerminalPermission { .none }
    public var canCaptureGeometry: Bool { false }

    public func available() -> Bool {
        let fm = FileManager.default
        let candidates = [
            "/Applications/\(app)",
            "\(NSHomeDirectory())/Applications/\(app)",
        ]
        if candidates.contains(where: { fm.fileExists(atPath: $0) }) { return true }
        return which("wezterm") != nil
    }

    /// Single-instance launch via the wezterm CLI mux client.
    public func singleInstanceArgv(cwd: String, command: String) -> [String]? {
        let dir = cwd.isEmpty ? NSHomeDirectory() : cwd
        let inner = "\(command); exec zsh -il"
        return [
            "wezterm", "cli", "spawn",
            "--cwd", dir,
            "--", "zsh", "-ilc", inner,
        ]
    }

    /// Multi-instance fallback: spawn a separate WezTerm instance.
    public func launchArgv(cwd: String, command: String) -> [String] {
        let dir = cwd.isEmpty ? NSHomeDirectory() : cwd
        let inner = "cd \(shellQuote(dir)); \(command); exec zsh -il"
        return ["open", "-na", app, "--args", "start", "--", "zsh", "-ilc", inner]
    }

    public func openWindow(cwd: String, command: String, dryRun: Bool) {
        let argv = launchArgv(cwd: cwd, command: command)
        if dryRun {
            print(argv.map { shellQuote($0) }.joined(separator: " "))
            return
        }
        runArgv(argv)
    }
}

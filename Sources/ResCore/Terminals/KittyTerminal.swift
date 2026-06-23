import Foundation

/// Kitty terminal adapter.
///
/// UNTESTED — kitty is not installed on this machine. The launch shapes below
/// are based on kitty's documented `kitten @` remote-control CLI, not on a
/// verified run. Treat as runtime-unverified.
///
/// Single-instance launching uses kitty's native remote control, which requires
/// the user to have BOTH:
///   - `allow_remote_control yes` in kitty.conf (or `--listen-on`), AND
///   - a listen socket kitty can reach (e.g. `listen_on unix:/tmp/kitty`).
/// When that isn't configured the remote command fails; the Launcher always
/// falls back to the multi-instance `open -na` path, so this can never break.
///
/// No macOS permission is needed (it's a local IPC socket, not Accessibility).
public struct KittyTerminal: Terminal {
    public let name = "kitty"
    public let display = "kitty"

    /// The .app to open for the multi-instance fallback.
    public let app: String

    public init(app: String = "kitty.app") {
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
        // Also accept a `kitten`/`kitty` on PATH (CLI-only install).
        return which("kitten") != nil || which("kitty") != nil
    }

    /// Single-instance launch via remote control: opens a new OS window in the
    /// running kitty and runs an interactive login shell so ~/.zshrc/PATH load.
    public func singleInstanceArgv(cwd: String, command: String) -> [String]? {
        let dir = cwd.isEmpty ? NSHomeDirectory() : cwd
        let inner = "\(command); exec zsh -il"
        return [
            "kitten", "@", "launch",
            "--type=os-window",
            "--cwd", dir,
            "zsh", "-ilc", inner,
        ]
    }

    /// Multi-instance fallback: spawn a separate kitty instance via `open -na`.
    public func launchArgv(cwd: String, command: String) -> [String] {
        let dir = cwd.isEmpty ? NSHomeDirectory() : cwd
        let inner = "cd \(shellQuote(dir)); \(command); exec zsh -il"
        // kitty accepts a command after `--`; we run it through zsh -ilc.
        return ["open", "-na", app, "--args", "zsh", "-ilc", inner]
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

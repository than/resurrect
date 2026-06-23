import Foundation

/// The one shipped terminal adapter. Verified primitive on macOS/Ghostty:
///
///   open -na Ghostty.app --args -e zsh -lc '<inner>'
///
/// where <inner> = "cd <shellquoted cwd>; <command>; exec zsh -l".
///
/// `-n` is required (spawns a separate Ghostty instance per window — accepted).
/// `exec zsh -l` keeps the window alive after the conversation exits. We build
/// argv WITHOUT a shell (array args) to avoid quoting bugs; only `cwd` is
/// shell-quoted inside <inner>.
public struct GhosttyTerminal: Terminal {
    public let name = "ghostty"
    public let display = "Ghostty"

    /// The .app to open. RES_TERMINAL overrides (default "Ghostty.app").
    public let app: String

    public init(app: String? = nil) {
        self.app = app
            ?? ProcessInfo.processInfo.environment["RES_TERMINAL"]
            ?? "Ghostty.app"
    }

    public func available() -> Bool {
        // Try to resolve the app bundle; if we can't, assume present (open will
        // surface the error). Probe common locations.
        let fm = FileManager.default
        let candidates = [
            "/Applications/\(app)",
            "\(NSHomeDirectory())/Applications/\(app)",
        ]
        if candidates.contains(where: { fm.fileExists(atPath: $0) }) { return true }
        // Fall back to allowing it — selection still works and `open` reports failure.
        return true
    }

    public func launchArgv(cwd: String, command: String) -> [String] {
        let dir = cwd.isEmpty ? NSHomeDirectory() : cwd
        // `-il` (interactive + login) so ~/.zshrc is sourced. GUI-launched
        // terminals get a sparse PATH; tools like `claude` are commonly added to
        // PATH in ~/.zshrc, which a non-interactive `zsh -lc` would skip.
        let inner = "cd \(shellQuote(dir)); \(command); exec zsh -il"
        return ["open", "-na", app, "--args", "-e", "zsh", "-ilc", inner]
    }

    public func openWindow(cwd: String, command: String, dryRun: Bool) {
        let argv = launchArgv(cwd: cwd, command: command)
        if dryRun {
            print(argv.map { shellQuote($0) }.joined(separator: " "))
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = Array(argv.dropFirst())  // drop "open"
        try? proc.run()
        proc.waitUntilExit()
    }
}

import Foundation

/// Thin wrapper around the `res` CLI. All methods are static and run the
/// binary by an absolute, portably-resolved path so they work regardless of
/// the GUI's (typically empty) PATH.
enum ResCLI {
    /// Resolve the `res` executable. A launched .app does not inherit the shell
    /// PATH, so we probe the common install locations (and honor a RES_BIN
    /// override), falling back to `/usr/bin/env res` with an augmented PATH.
    private static let resolved: (url: URL, prefix: [String]) = {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["RES_BIN"],
           fm.isExecutableFile(atPath: override) {
            return (URL(fileURLWithPath: override), [])
        }
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/res",   // uv tool / pipx default
            "/opt/homebrew/bin/res",    // Homebrew (Apple silicon)
            "/usr/local/bin/res",       // Homebrew (Intel) / manual
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return (URL(fileURLWithPath: path), [])
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["res"])
    }()

    /// A reasonable PATH so the `/usr/bin/env res` fallback (and `res` itself)
    /// can resolve helpers even when launched from a GUI bundle.
    private static var augmentedPath: String {
        let home = NSHomeDirectory()
        return "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    }

    enum ResError: Error {
        case nonZeroExit(Int32, String)
        case launchFailed(String)
    }

    /// Run `res` with the given arguments, returning captured stdout data.
    /// Throws on launch failure or non-zero exit. Safe to call off the main thread.
    @discardableResult
    private static func run(_ args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = resolved.url
        process.arguments = resolved.prefix + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPath
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw ResError.launchFailed(error.localizedDescription)
        }

        // Read before waiting to avoid deadlock on large output.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            throw ResError.nonZeroExit(process.terminationStatus, msg)
        }
        return outData
    }

    /// `res list --json` decoded into `[Session]`. Blocking; call off main thread.
    static func list() throws -> [Session] {
        let data = try run(["list", "--json"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Session].self, from: data)
    }

    /// `res open <id>` — resurrect a session in a new terminal window.
    static func open(id: String) throws {
        try run(["open", id])
    }

    /// `res restore` — resurrect the last live set.
    static func restore() throws {
        try run(["restore"])
    }

    /// Launch the interactive picker in its own Ghostty window.
    /// `res pick` is a TUI and must run inside a real terminal, not be captured.
    static func openPicker() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [
            "-na", "Ghostty.app",
            "--args", "-e", "zsh", "-lc", "res pick; exec zsh -l"
        ]
        try? task.run()
    }
}

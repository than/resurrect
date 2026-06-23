import Foundation

/// Resolve an executable on PATH (like `which`). Returns its absolute path or
/// nil. Used by adapters to detect CLI-only installs.
func which(_ tool: String) -> String? {
    let env = ProcessInfo.processInfo.environment
    let path = env["PATH"] ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
    let fm = FileManager.default
    for dir in path.split(separator: ":") {
        let candidate = (String(dir) as NSString).appendingPathComponent(tool)
        if fm.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
}

/// Run an argv as a child process and wait for it. The first element is the
/// program. For `open …` argv we use /usr/bin/open directly; for everything
/// else we resolve the program on PATH (or run it as-is if absolute), falling
/// back to /usr/bin/env so PATH lookup works for CLI tools like `kitten`.
func runArgv(_ argv: [String]) {
    guard let first = argv.first else { return }
    let rest = Array(argv.dropFirst())
    let proc = Process()
    if first == "open" {
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = rest
    } else if first.hasPrefix("/") {
        proc.executableURL = URL(fileURLWithPath: first)
        proc.arguments = rest
    } else {
        // Resolve via env so the tool's directory on PATH is honored.
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = argv
    }
    do {
        try proc.run()
        proc.waitUntilExit()
    } catch {
        NSLog("res: launch failed for \(first): \(error.localizedDescription)")
    }
}

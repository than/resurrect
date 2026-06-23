import Foundation
import ResCore

// Entry point. Routing:
//   - `res menubar` (or any explicit subcommand)            -> ArgumentParser CLI
//   - bare `res` from a TTY                                  -> picker (pick)
//   - bare `res` with no args and NOT a TTY (launched .app)  -> menu bar app
let rawArgs = Array(CommandLine.arguments.dropFirst())

if rawArgs.isEmpty {
    // No args: decide by whether stdin is a TTY.
    if isatty(STDIN_FILENO) != 0 {
        // Interactive shell -> picker
        ResCommand.main(["pick"])
    } else {
        // Launched as a .app (no TTY) -> menu bar
        runMenuBarApp()
    }
} else if rawArgs == ["menubar"] {
    runMenuBarApp()
} else {
    ResCommand.main(rawArgs)
}

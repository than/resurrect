import Foundation

/// Terminal adapter registry. Selection priority:
///   RES_TERMINAL env > $TERM_PROGRAM detect > first available > Ghostty.
public enum TerminalRegistry {
    public static var allTerminals: [Terminal] {
        // Ghostty is the verified, shipped adapter and stays first (the default).
        // Kitty/WezTerm are UNTESTED adapters (neither installed here) based on
        // documented CLIs — they only activate if available() detects them.
        [GhosttyTerminal(), KittyTerminal(), WezTermTerminal()]
    }

    public static func availableTerminals() -> [Terminal] {
        allTerminals.filter { $0.available() }
    }

    /// The terminal `res` will launch windows in.
    public static func selectedTerminal() -> Terminal {
        let env = ProcessInfo.processInfo.environment

        // RES_TERMINAL overrides. It names an .app; Ghostty adapter honors it
        // for the open invocation. If it matches a known adapter name, prefer that.
        if let raw = env["RES_TERMINAL"], !raw.isEmpty {
            let lowered = raw.lowercased()
            if let match = allTerminals.first(where: {
                lowered.contains($0.name) || lowered.contains($0.display.lowercased())
            }) {
                return match
            }
            // Unknown app name: drive it through the Ghostty-style adapter,
            // which respects RES_TERMINAL for the `open -na <app>` target.
            return GhosttyTerminal(app: raw)
        }

        // $TERM_PROGRAM detection (e.g. "ghostty", "Apple_Terminal").
        if let tp = env["TERM_PROGRAM"]?.lowercased() {
            if let match = allTerminals.first(where: {
                tp.contains($0.name) || tp.contains($0.display.lowercased())
            }) {
                return match
            }
        }

        // First available, else Ghostty.
        return availableTerminals().first ?? GhosttyTerminal()
    }
}

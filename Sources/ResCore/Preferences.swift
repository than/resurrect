import Foundation

/// Persistent user preferences backed by UserDefaults (suite
/// "com.than.resurrect"). Holds the chosen terminal, onboarding state, and the
/// computed "single-instance enabled" decision the Launcher consults.
///
/// Sendable: a value type capturing a UserDefaults reference. UserDefaults is
/// thread-safe; we mark the wrapper @unchecked Sendable for that reason.
public struct Preferences: @unchecked Sendable {
    public static let suiteName = "com.than.resurrect"

    let defaults: UserDefaults

    /// The shared store (suite com.than.resurrect, or .standard if unavailable).
    public static let shared = Preferences()

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Preferences.suiteName)
            ?? .standard
    }

    private enum Key {
        static let chosenTerminal = "res.chosenTerminal"
        static let onboardingComplete = "res.onboardingComplete"
    }

    /// The machine-readable name of the terminal the user chose during
    /// onboarding (e.g. "ghostty"). nil if not yet chosen.
    public var chosenTerminalName: String? {
        get { defaults.string(forKey: Key.chosenTerminal) }
        nonmutating set {
            if let newValue { defaults.set(newValue, forKey: Key.chosenTerminal) }
            else { defaults.removeObject(forKey: Key.chosenTerminal) }
        }
    }

    public var onboardingComplete: Bool {
        get { defaults.bool(forKey: Key.onboardingComplete) }
        nonmutating set { defaults.set(newValue, forKey: Key.onboardingComplete) }
    }

    /// The Terminal the Launcher should use: the chosen one (by name) if it's
    /// known and available, else fall back to env/$TERM_PROGRAM detection.
    public func resolvedTerminal() -> Terminal {
        if let name = chosenTerminalName,
           let match = TerminalRegistry.allTerminals.first(where: { $0.name == name }) {
            return match
        }
        return TerminalRegistry.selectedTerminal()
    }

    /// True when the resolved terminal supports single-instance AND its required
    /// permission is satisfied. `permissionGranted` is supplied by the caller
    /// (e.g. via Permissions.accessibilityTrusted()) so this stays pure/testable.
    public func singleInstanceEnabled(
        for terminal: Terminal,
        permissionGranted: (TerminalPermission) -> Bool
    ) -> Bool {
        guard terminal.singleInstance != .none else { return false }
        switch terminal.requiredPermission {
        case .none:
            return true
        case .accessibility, .automation:
            return permissionGranted(terminal.requiredPermission)
        }
    }
}

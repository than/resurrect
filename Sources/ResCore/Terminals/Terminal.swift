import Foundation

/// How (if at all) a terminal can launch a new window/tab inside its EXISTING
/// process rather than spawning a fresh instance. This is what makes
/// "single-instance" launching possible.
public enum SingleInstanceMechanism: Sendable, Equatable {
    /// No supported single-instance path — always spawn a new instance.
    case none
    /// Native CLI remote-control (e.g. kitty `kitten @`, wezterm `cli spawn`).
    case remoteControl
    /// Driven via AppleScript / `System Events` keystrokes.
    case appleScript
    /// Driven via the macOS Accessibility (AX) API.
    case accessibility
}

/// The macOS permission a terminal needs before its single-instance / geometry
/// features can be used.
public enum TerminalPermission: Sendable, Equatable {
    /// No special permission required.
    case none
    /// Accessibility (AXIsProcessTrusted / System Settings > Privacy).
    case accessibility
    /// Automation (AppleEvents / "control <app>" prompt on first use).
    case automation
}

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
    /// The argv used to open the window (exposed for testing / dry-run). This is
    /// always the SAFE multi-instance fallback path.
    func launchArgv(cwd: String, command: String) -> [String]

    // MARK: - Capability metadata (P1)

    /// How this terminal can reuse its existing process for new windows/tabs.
    var singleInstance: SingleInstanceMechanism { get }
    /// The macOS permission the single-instance / geometry features need.
    var requiredPermission: TerminalPermission { get }
    /// True if window geometry (position/size) can be captured & restored for
    /// this terminal (currently only via Accessibility).
    var canCaptureGeometry: Bool { get }

    /// The argv for the SINGLE-INSTANCE launch path, if `singleInstance` is a
    /// CLI-driven mechanism (remoteControl). Returns nil for mechanisms that
    /// aren't argv-based (none / appleScript / accessibility). The Launcher only
    /// uses this when single-instance is enabled for the selected terminal.
    func singleInstanceArgv(cwd: String, command: String) -> [String]?
}

// Sensible defaults so existing adapters keep compiling: capabilities off,
// no single-instance argv.
extension Terminal {
    public var singleInstance: SingleInstanceMechanism { .none }
    public var requiredPermission: TerminalPermission { .none }
    public var canCaptureGeometry: Bool { false }
    public func singleInstanceArgv(cwd: String, command: String) -> [String]? { nil }
}

/// Human-readable tier for the onboarding UI.
public func singleInstanceTier(_ t: Terminal) -> String {
    switch t.singleInstance {
    case .none:
        return "multi-instance only"
    case .remoteControl:
        return "single-instance: native (remote control)"
    case .appleScript:
        return "single-instance: via AppleScript"
    case .accessibility:
        return "single-instance: via Accessibility"
    }
}

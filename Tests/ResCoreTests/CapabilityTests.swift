import Testing
import Foundation
@testable import ResCore

// MARK: - Capability metadata per adapter (P1)

@Test func ghosttyCapabilities() {
    let g = GhosttyTerminal()
    #expect(g.singleInstance == .accessibility)
    #expect(g.requiredPermission == .accessibility)
    #expect(g.canCaptureGeometry == true)
    // Ghostty's single-instance path is AX-driven, not argv-based.
    #expect(g.singleInstanceArgv(cwd: "/x", command: "claude") == nil)
}

@Test func kittyCapabilities() {
    let k = KittyTerminal()
    #expect(k.singleInstance == .remoteControl)
    #expect(k.requiredPermission == .none)
    #expect(k.canCaptureGeometry == false)
}

@Test func weztermCapabilities() {
    let w = WezTermTerminal()
    #expect(w.singleInstance == .remoteControl)
    #expect(w.requiredPermission == .none)
    #expect(w.canCaptureGeometry == false)
}

// MARK: - launchArgv / singleInstanceArgv shapes

@Test func kittySingleInstanceArgvShape() throws {
    let k = KittyTerminal()
    let argv = try #require(k.singleInstanceArgv(cwd: "/Users/dev/proj", command: "claude --resume x"))
    #expect(Array(argv.prefix(5)) == ["kitten", "@", "launch", "--type=os-window", "--cwd"])
    #expect(argv[5] == "/Users/dev/proj")
    #expect(argv.contains("zsh"))
    let last = try #require(argv.last)
    #expect(last.contains("claude --resume x"))
    #expect(last.hasSuffix("exec zsh -il"))
}

@Test func kittySingleInstanceArgvEmptyCwdDefaultsHome() throws {
    let argv = try #require(KittyTerminal().singleInstanceArgv(cwd: "", command: "c"))
    #expect(argv[5] == NSHomeDirectory())
}

@Test func weztermSingleInstanceArgvShape() throws {
    let w = WezTermTerminal()
    let argv = try #require(w.singleInstanceArgv(cwd: "/Users/dev/proj", command: "claude --resume x"))
    #expect(Array(argv.prefix(5)) == ["wezterm", "cli", "spawn", "--cwd", "/Users/dev/proj"])
    #expect(argv.contains("--"))
    let last = try #require(argv.last)
    #expect(last.contains("claude --resume x"))
    #expect(last.hasSuffix("exec zsh -il"))
}

@Test func ghosttyMultiInstanceArgvUnchanged() throws {
    // The verified fallback must stay exactly as before.
    let argv = GhosttyTerminal(app: "Ghostty.app")
        .launchArgv(cwd: "/Users/dev/proj", command: "claude --resume abc")
    #expect(Array(argv.prefix(7)) == ["open", "-na", "Ghostty.app", "--args", "-e", "zsh", "-ilc"])
}

@Test func kittyMultiInstanceFallbackArgv() throws {
    let argv = KittyTerminal(app: "kitty.app").launchArgv(cwd: "/x", command: "c")
    #expect(Array(argv.prefix(4)) == ["open", "-na", "kitty.app", "--args"])
}

// MARK: - Tier labels

@Test func tierLabels() {
    #expect(singleInstanceTier(GhosttyTerminal()).contains("Accessibility"))
    #expect(singleInstanceTier(KittyTerminal()).contains("native"))
    let stub = StubTerminal(mech: .none)
    #expect(singleInstanceTier(stub) == "multi-instance only")
}

// MARK: - Preferences: selection + enabled logic

/// A minimal Terminal for testing the enabled-logic in isolation.
struct StubTerminal: Terminal {
    let mech: SingleInstanceMechanism
    var perm: TerminalPermission = .none
    var name: String { "stub" }
    var display: String { "Stub" }
    func available() -> Bool { true }
    func openWindow(cwd: String, command: String, dryRun: Bool) {}
    func launchArgv(cwd: String, command: String) -> [String] { ["open", "stub"] }
    var singleInstance: SingleInstanceMechanism { mech }
    var requiredPermission: TerminalPermission { perm }
}

private func freshPrefs() -> Preferences {
    let suite = "res.test.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    return Preferences(defaults: d)
}

@Test func singleInstanceDisabledWhenMechanismNone() {
    let prefs = freshPrefs()
    let term = StubTerminal(mech: .none)
    #expect(prefs.singleInstanceEnabled(for: term, permissionGranted: { _ in true }) == false)
}

@Test func singleInstanceEnabledWhenNoPermissionNeeded() {
    let prefs = freshPrefs()
    let term = StubTerminal(mech: .remoteControl, perm: .none)
    // Permission predicate shouldn't even matter; returns true regardless.
    #expect(prefs.singleInstanceEnabled(for: term, permissionGranted: { _ in false }) == true)
}

@Test func singleInstanceGatedOnAccessibility() {
    let prefs = freshPrefs()
    let term = StubTerminal(mech: .accessibility, perm: .accessibility)
    #expect(prefs.singleInstanceEnabled(for: term, permissionGranted: { _ in false }) == false)
    #expect(prefs.singleInstanceEnabled(for: term, permissionGranted: { $0 == .accessibility }) == true)
}

@Test func prefsRoundTripChosenTerminalAndOnboarding() {
    let prefs = freshPrefs()
    #expect(prefs.chosenTerminalName == nil)
    #expect(prefs.onboardingComplete == false)
    prefs.chosenTerminalName = "kitty"
    prefs.onboardingComplete = true
    #expect(prefs.chosenTerminalName == "kitty")
    #expect(prefs.onboardingComplete == true)
}

@Test func resolvedTerminalUsesChosenName() {
    let prefs = freshPrefs()
    prefs.chosenTerminalName = "kitty"
    #expect(prefs.resolvedTerminal().name == "kitty")
}

@Test func resolvedTerminalFallsBackWhenUnknown() {
    let prefs = freshPrefs()
    prefs.chosenTerminalName = "does-not-exist"
    // Falls back to selectedTerminal() (env/detect/first); just verify non-nil
    // and that it's a registered adapter name.
    let name = prefs.resolvedTerminal().name
    #expect(["ghostty", "kitty", "wezterm"].contains(name))
}

// MARK: - Launcher path decision (pure)

@Test func decidePathMultiWhenDisabled() {
    let p = Launcher.decidePath(terminal: KittyTerminal(), singleInstanceEnabled: false)
    #expect(p == .multiInstance)
}

@Test func decidePathRemoteControlForKitty() {
    let p = Launcher.decidePath(terminal: KittyTerminal(), singleInstanceEnabled: true)
    #expect(p == .remoteControl)
}

@Test func decidePathAccessibilityForGhostty() {
    let p = Launcher.decidePath(terminal: GhosttyTerminal(), singleInstanceEnabled: true)
    #expect(p == .ghosttyAccessibility)
}

// MARK: - Permissions purity (no prompt)

@Test func permissionsGrantedNoneAlwaysTrue() {
    #expect(Permissions.granted(.none) == true)
}

@Test func permissionsAccessibilityMatchesTrustCheck() {
    // accessibilityTrusted() never prompts; granted(.accessibility) mirrors it.
    #expect(Permissions.granted(.accessibility) == Permissions.accessibilityTrusted())
}

// MARK: - Geometry store round-trip (pure JSON)

@Test func geometryRoundTrip() {
    let tmp = NSTemporaryDirectory() + "geo-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    let frame = WindowFrame(x: 100, y: 200, w: 800, h: 600)
    #expect(Geometry.update(sessionId: "s1", frame: frame, fileOverride: tmp) == true)
    #expect(Geometry.frame(for: "s1", fileOverride: tmp) == frame)
    // Add a second, ensure first survives.
    let f2 = WindowFrame(x: 0, y: 0, w: 10, h: 10)
    Geometry.update(sessionId: "s2", frame: f2, fileOverride: tmp)
    let all = Geometry.readAll(fileOverride: tmp)
    #expect(all.count == 2)
    #expect(all["s1"] == frame)
    #expect(all["s2"] == f2)
}

@Test func geometryMissingFileEmpty() {
    let none = Geometry.readAll(fileOverride: NSTemporaryDirectory() + "nope-\(UUID().uuidString).json")
    #expect(none.isEmpty)
}

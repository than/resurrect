import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ApplicationServices)
import ApplicationServices
#endif

/// Accessibility-driven Ghostty integration: window-geometry capture/restore
/// (P4) and single-instance new-tab launching (P5).
///
/// RUNTIME-UNVERIFIED. None of this can be exercised headlessly:
///   - It requires the Accessibility permission (AXIsProcessTrusted).
///   - It drives a real running Ghostty via the AX API and CGEvent/AppleScript
///     keystrokes, which are timing-sensitive.
///   - Mapping windows -> sessions is approximate: it matches the AX window /
///     tab TITLE against the session title/name. Claude writes the session name
///     to the terminal tab title, but this is heuristic and may mismatch when
///     titles collide or are truncated. Every operation is best-effort and
///     guarded behind `Permissions.accessibilityTrusted()`; failure degrades to
///     the multi-instance fallback and never crashes.
///
/// All entry points are no-ops returning false when AppKit/AX is unavailable or
/// the process is not trusted, so callers can rely on graceful fallback.
public enum GhosttyAccessibility {

    /// The running Ghostty application, if any.
    #if canImport(AppKit)
    static func runningGhostty() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: GhosttyTerminal.bundleIdentifier
        ).first
    }
    #endif

    // MARK: - P5: single-instance new tab

    /// Activate the running Ghostty, open a new tab, and type the command. Best
    /// effort. Returns true only if we believe we drove the running instance;
    /// false means the caller should fall back to multi-instance launch.
    ///
    /// RUNTIME-UNVERIFIED — keystroke timing & AppleScript automation prompt.
    @discardableResult
    public static func openInNewTab(cwd: String, command: String) -> Bool {
        #if canImport(AppKit) && canImport(ApplicationServices)
        guard Permissions.accessibilityTrusted() else { return false }
        guard let app = runningGhostty() else { return false }

        app.activate(options: [])
        // Give the app a beat to come forward.
        usleep(200_000)

        // New tab: Cmd+T.
        guard sendCommandKeystroke("t") else { return false }
        usleep(250_000)

        // The new tab's interactive login shell sources ~/.zshrc (PATH ok).
        let dir = cwd.isEmpty ? NSHomeDirectory() : cwd
        let line = "cd \(shellQuote(dir)); \(command)\n"
        return typeString(line)
        #else
        return false
        #endif
    }

    // MARK: - P4: geometry capture

    /// Capture {sessionId: frame} for the given sessions by matching each
    /// session's title/name against Ghostty's AX window titles. Persists via
    /// `Geometry`. Best-effort; returns the number of frames captured.
    ///
    /// RUNTIME-UNVERIFIED.
    @discardableResult
    public static func captureGeometry(for sessions: [Session]) -> Int {
        #if canImport(AppKit) && canImport(ApplicationServices)
        guard Permissions.accessibilityTrusted() else { return 0 }
        guard let app = runningGhostty() else { return 0 }

        let windows = axWindows(pid: app.processIdentifier)
        guard !windows.isEmpty else { return 0 }

        var captured = 0
        for s in sessions {
            let needle = (s.name ?? s.title)
            guard let win = matchWindow(windows, to: needle) else { continue }
            guard let frame = frameOf(win) else { continue }
            if Geometry.update(sessionId: s.id, frame: frame) { captured += 1 }
        }
        return captured
        #else
        return 0
        #endif
    }

    // MARK: - P4: geometry restore

    /// After launching `session`, if a saved frame exists and AX is trusted,
    /// move/resize the newly created window matching by title. Best-effort;
    /// returns true if a frame was applied.
    ///
    /// RUNTIME-UNVERIFIED.
    @discardableResult
    public static func restoreGeometry(for session: Session) -> Bool {
        #if canImport(AppKit) && canImport(ApplicationServices)
        guard Permissions.accessibilityTrusted() else { return false }
        guard let frame = Geometry.frame(for: session.id) else { return false }
        guard let app = runningGhostty() else { return false }

        let windows = axWindows(pid: app.processIdentifier)
        let needle = (session.name ?? session.title)
        guard let win = matchWindow(windows, to: needle) else { return false }
        return applyFrame(frame, to: win)
        #else
        return false
        #endif
    }

    // MARK: - AX primitives (compiled, runtime-unverified)

    #if canImport(ApplicationServices)
    /// All AX window elements for a pid.
    static func axWindows(pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let arr = value as? [AXUIElement] else { return [] }
        return arr
    }

    /// First window whose AX title contains (or is contained by) `needle`.
    static func matchWindow(_ windows: [AXUIElement], to needle: String) -> AXUIElement? {
        let target = needle.lowercased()
        guard !target.isEmpty else { return nil }
        // Exact-ish first, then substring either direction.
        for win in windows {
            guard let title = stringAttribute(win, kAXTitleAttribute)?.lowercased() else { continue }
            if title == target { return win }
        }
        for win in windows {
            guard let title = stringAttribute(win, kAXTitleAttribute)?.lowercased() else { continue }
            if title.contains(target) || target.contains(title) { return win }
        }
        return nil
    }

    static func stringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    /// Read position + size into a WindowFrame.
    static func frameOf(_ window: AXUIElement) -> WindowFrame? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        if let posRef {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        }
        if let sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }
        // swiftlint:enable force_cast
        return WindowFrame(x: point.x, y: point.y, w: size.width, h: size.height)
    }

    /// Apply a frame to a window via AX set position/size.
    static func applyFrame(_ frame: WindowFrame, to window: AXUIElement) -> Bool {
        var point = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.w, height: frame.h)
        guard let posValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let p = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        let s = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return p == .success && s == .success
    }
    #endif

    // MARK: - Keystroke helpers (P5, runtime-unverified)

    #if canImport(AppKit)
    /// Send Cmd+<char> to the frontmost app via CGEvent. Returns false if event
    /// creation fails. Requires Accessibility trust at runtime.
    static func sendCommandKeystroke(_ char: String) -> Bool {
        guard let keyCode = virtualKeyCode(for: char) else { return false }
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return false }
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Type a literal string. We shell out to AppleScript `System Events
    /// keystroke` which handles arbitrary unicode and the trailing newline as a
    /// return. This may trigger the one-time Automation prompt for System
    /// Events; if denied, returns false and the caller falls back.
    static func typeString(_ s: String) -> Bool {
        // Escape for AppleScript string literal.
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\" & return & \"")
        let script = "tell application \"System Events\" to keystroke \"\(escaped)\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Minimal US-keyboard virtual keycode map (only what we need).
    static func virtualKeyCode(for char: String) -> CGKeyCode? {
        switch char.lowercased() {
        case "t": return 0x11
        default: return nil
        }
    }
    #endif
}

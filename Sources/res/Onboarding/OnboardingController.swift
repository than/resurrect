import AppKit
import SwiftUI
import ResCore

/// Presents the onboarding wizard in a standalone NSWindow hosting the SwiftUI
/// view. The app is a menu-bar accessory (no normal windows), so we create the
/// window on demand and activate the app so it's visible.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    private var window: NSWindow?
    private var model: OnboardingModel?

    /// Show onboarding only if it hasn't been completed yet. Returns true if it
    /// was shown. Safe to call once on launch.
    @discardableResult
    func showIfNeeded() -> Bool {
        guard !Preferences.shared.onboardingComplete else { return false }
        show()
        return true
    }

    /// Force-show the wizard (used by the "Setup…" menu item).
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = OnboardingModel()
        self.model = model
        let hosting = NSHostingController(rootView: OnboardingView(model: model))
        let win = NSWindow(contentViewController: hosting)
        win.title = "Resurrect Setup"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Drop references so a fresh model is built next time.
        window = nil
        model = nil
    }
}

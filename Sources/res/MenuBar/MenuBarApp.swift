import SwiftUI
import AppKit
import ResCore

/// Launch the SwiftUI MenuBarExtra app. Called from main when no CLI args are
/// present and there's no TTY (running as a .app), or via `res menubar`.
/// Invoked from the main thread; we assert main-actor isolation rather than
/// hopping, since this never returns.
func runMenuBarApp() -> Never {
    MainActor.assumeIsolated {
        // Ensure we're an accessory (no dock icon) even without LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
        ResBarApp.main()
    }
    // ResBarApp.main() runs the run loop and does not return.
    exit(0)
}

struct ResBarApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra {
            ResMenu(store: store)
        } label: {
            Text(store.menuBarTitle)
                .onAppear {
                    store.start()
                    // Defer so the app is fully active before showing any window.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        // First run: onboarding wizard (which includes the
                        // start-at-login step). Otherwise, the legacy first-run
                        // login prompt for users who onboarded before this flow.
                        if !store.onboardingComplete {
                            store.maybeShowOnboarding()
                        } else {
                            store.maybePromptLaunchAtLogin()
                        }
                    }
                }
        }
        .menuBarExtraStyle(.menu)
    }
}

/// The dropdown contents. With .menu style, SwiftUI renders Buttons/Dividers
/// as native menu items.
struct ResMenu: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        if !store.available {
            Text("\u{26A0}\u{FE0F} no sessions")  // ⚠️
            Divider()
            Button("\u{21BB} Refresh now") { store.refresh() }  // ↻
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } else {
            Text("\u{1F9DF} \(store.liveCount) resurrected")
            Divider()

            // Grouped by workspace (the directory each session ran in).
            ForEach(store.groupedRows) { group in
                Section(group.workspace) {
                    ForEach(group.sessions) { session in
                        Button {
                            store.open(session)
                        } label: {
                            Text(rowLabel(for: session))
                        }
                    }
                }
            }

            Divider()
            Button("\u{21BA} Restore last state") { store.restore() }   // ↺
            Button("\u{29C9} Open picker\u{2026}") { store.openPicker() }  // ⧉ …
            Button("\u{21BB} Refresh now") { store.refresh() }        // ↻
            Divider()
            Text("\u{1F5A5} \(store.terminalStatus)")  // 🖥 terminal + mode
            Button("\u{2699} Setup\u{2026}") { store.openSetup() }  // ⚙
            Button(store.launchAtLogin ? "\u{2713} Start at Login" : "Start at Login") {
                store.toggleLaunchAtLogin()
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private func rowLabel(for session: Session) -> String {
        let glyph = statusGlyph(session)
        let prefix = glyph == " " ? "  " : "\(glyph) "
        return "\(prefix)\(session.title)"
    }
}

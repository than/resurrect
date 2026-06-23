import SwiftUI

@main
struct ResBarApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra {
            ResMenu(store: store)
        } label: {
            Text(store.menuBarTitle)
                .onAppear { store.start() }
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
            Text("\u{26A0}\u{FE0F} res unavailable")  // ⚠️
            Divider()
            Button("\u{21BB} Refresh now") { store.refresh() }  // ↻
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } else {
            Text("\u{1F94C} \(store.liveCount) active")
            Divider()

            ForEach(store.menuRows) { session in
                Button {
                    store.open(session)
                } label: {
                    Text(rowLabel(for: session))
                }
            }

            Divider()
            Button("\u{21BA} Restore last state") { store.restore() }   // ↺
            Button("\u{29C9} Open picker\u{2026}") { store.openPicker() }  // ⧉ …
            Button("\u{21BB} Refresh now") { store.refresh() }        // ↻
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private func rowLabel(for session: Session) -> String {
        let glyph = session.glyph
        let prefix = glyph.isEmpty ? "  " : "\(glyph) "
        return "\(prefix)\(session.displayTitle)"
    }
}

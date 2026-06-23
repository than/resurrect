import SwiftUI
import ResCore

/// The first-run onboarding window contents. A simple multi-step wizard.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            stepBody
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 480, height: 380)
    }

    private var header: some View {
        HStack {
            Text("\u{1F9DF} Resurrect")
                .font(.title2).bold()
            Spacer()
            Text("Setup")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch model.step {
        case .welcome:    welcomeStep
        case .terminal:   terminalStep
        case .permission: permissionStep
        case .login:      loginStep
        case .finish:     finishStep
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bring your coding-agent sessions back to life.")
                .font(.headline)
            Text("Resurrect lives in your menu bar and relaunches your sessions in a terminal window. Let's pick how it opens windows.")
                .foregroundStyle(.secondary)
        }
    }

    private var terminalStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your terminal").font(.headline)
            if model.terminals.isEmpty {
                Text("No terminals detected. Ghostty will be used by default.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.terminals) { t in
                Button {
                    model.chooseTerminal(t.id)
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: model.chosenName == t.id
                              ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.display)
                            Text(t.tier).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unlock single-instance + window restore").font(.headline)
            Text("Granting Accessibility lets Resurrect open sessions as tabs in your existing \(model.chosenTerminal?.display ?? "terminal") window AND remember each window's position and size.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: model.accessibilityTrusted
                      ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                Text(model.accessibilityTrusted ? "Accessibility granted" : "Not granted yet")
            }
            HStack {
                Button("Grant Accessibility\u{2026}") { model.requestAccessibility() }
                Button("Re-check") { model.refreshTrust() }
                Button("Skip (use multi-instance)") { model.skipPermission() }
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loginStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start at login").font(.headline)
            Text("Keep the \u{1F9DF} in your menu bar across restarts.")
                .foregroundStyle(.secondary)
            Toggle("Start Resurrect at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { _ in model.toggleLaunchAtLogin() }
            ))
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You're set.").font(.headline)
            Text("Terminal: \(model.chosenTerminal?.display ?? model.chosenName)")
            if model.chosenRequiresPermission {
                Text("Single-instance + window restore: \(model.accessibilityTrusted ? "enabled" : "off (multi-instance fallback)")")
                    .foregroundStyle(.secondary)
            }
            Text("Re-open this anytime from the menu: \u{201C}Setup\u{2026}\u{201D}")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer nav

    private var footer: some View {
        HStack {
            if model.step != .welcome {
                Button("Back") { model.back() }
            }
            Spacer()
            if model.isLastStep {
                Button("Finish") { model.finish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") {
                    if model.step == .terminal { model.persistChoice() }
                    model.next()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

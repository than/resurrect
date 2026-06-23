import Foundation
import SwiftUI
import ServiceManagement
import ResCore

/// Drives the multi-step first-run onboarding. @MainActor — all state is touched
/// on the main thread, matching SessionStore's pattern.
@MainActor
final class OnboardingModel: ObservableObject {

    enum Step: Int, CaseIterable {
        case welcome
        case terminal
        case permission
        case login
        case finish
    }

    @Published var step: Step = .welcome
    @Published var terminals: [TerminalChoice] = []
    @Published var chosenName: String = ""
    @Published var accessibilityTrusted: Bool = Permissions.accessibilityTrusted()
    @Published var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    /// One selectable terminal + its capability tier.
    struct TerminalChoice: Identifiable {
        let id: String        // adapter name
        let display: String
        let tier: String
        let requiredPermission: TerminalPermission
    }

    private let prefs = Preferences.shared

    init() {
        loadTerminals()
    }

    func loadTerminals() {
        let available = TerminalRegistry.availableTerminals()
        terminals = available.map {
            TerminalChoice(
                id: $0.name,
                display: $0.display,
                tier: singleInstanceTier($0),
                requiredPermission: $0.requiredPermission
            )
        }
        // Default selection: previously chosen > $TERM_PROGRAM match > first.
        if let saved = prefs.chosenTerminalName,
           terminals.contains(where: { $0.id == saved }) {
            chosenName = saved
        } else {
            chosenName = TerminalRegistry.selectedTerminal().name
            if !terminals.contains(where: { $0.id == chosenName }) {
                chosenName = terminals.first?.id ?? "ghostty"
            }
        }
    }

    /// The capability metadata for the currently chosen terminal.
    var chosenTerminal: Terminal? {
        TerminalRegistry.allTerminals.first { $0.name == chosenName }
    }

    var chosenRequiresPermission: Bool {
        (chosenTerminal?.requiredPermission ?? .none) != .none
    }

    // MARK: - Navigation

    /// Steps actually shown — skip the permission step when not needed.
    var visibleSteps: [Step] {
        Step.allCases.filter { s in
            if s == .permission { return chosenRequiresPermission }
            return true
        }
    }

    func next() {
        let order = visibleSteps
        guard let idx = order.firstIndex(of: step), idx + 1 < order.count else {
            finish()
            return
        }
        step = order[idx + 1]
    }

    func back() {
        let order = visibleSteps
        guard let idx = order.firstIndex(of: step), idx > 0 else { return }
        step = order[idx - 1]
    }

    var isLastStep: Bool { step == .finish }

    // MARK: - Actions

    func chooseTerminal(_ name: String) {
        chosenName = name
    }

    /// Persist the choice immediately so the Launcher can use it.
    func persistChoice() {
        prefs.chosenTerminalName = chosenName
    }

    func requestAccessibility() {
        // Triggers the system prompt / opens System Settings. Refresh state.
        _ = Permissions.requestAccessibility(prompt: true)
        refreshTrust()
    }

    func refreshTrust() {
        accessibilityTrusted = Permissions.accessibilityTrusted()
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("res: onboarding login toggle failed: \(error.localizedDescription)")
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    /// Mark onboarding done and persist the terminal choice.
    func finish() {
        persistChoice()
        prefs.onboardingComplete = true
        OnboardingController.shared.close()
    }

    /// Skip permission: keep multi-instance fallback. Just advance.
    func skipPermission() {
        next()
    }
}

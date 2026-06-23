import Foundation
#if canImport(ApplicationServices)
import ApplicationServices
#endif

/// macOS permission helpers for the Accessibility (AX) features.
///
/// IMPORTANT (dev note): an unsigned / ad-hoc-signed app's Accessibility grant
/// is keyed to its code signature. Every `swift build` + re-sign changes the
/// signature, so macOS RESETS the grant and the user must re-approve. This is
/// expected during development and is NOT a bug in this code.
///
/// None of these functions are called during build or tests. `requestAccessibility`
/// is the ONLY one that can show a system prompt, and it is invoked solely from
/// explicit user action in onboarding/menu.
public enum Permissions {

    /// True if this process is currently trusted for Accessibility. Never
    /// prompts. Safe to poll. Returns false on platforms without AX.
    public static func accessibilityTrusted() -> Bool {
        #if canImport(ApplicationServices)
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }

    /// Request Accessibility trust. With prompt == true this shows the system
    /// dialog / opens System Settings > Privacy & Security > Accessibility the
    /// first time. Returns the CURRENT trust state (often false until the user
    /// approves and the app is restarted). DO NOT call during build/tests.
    @discardableResult
    public static func requestAccessibility(prompt: Bool = true) -> Bool {
        #if canImport(ApplicationServices)
        // kAXTrustedCheckOptionPrompt is an imported global `var` (not
        // concurrency-safe under Swift 6 strict checking). Its documented value
        // is the CFString "AXTrustedCheckOptionPrompt"; use that literal so we
        // avoid touching shared mutable state. AXIsProcessTrustedWithOptions
        // shows the prompt / opens System Settings when this key is true.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
        #else
        return false
        #endif
    }

    /// Whether a given TerminalPermission is currently satisfied. Automation is
    /// granted per-target-app on first AppleEvent use and can't be reliably
    /// pre-checked without sending an event, so we report it as "true" here and
    /// let the first use prompt; single-instance via Automation still gracefully
    /// falls back if the user denies.
    public static func granted(_ permission: TerminalPermission) -> Bool {
        switch permission {
        case .none:
            return true
        case .accessibility:
            return accessibilityTrusted()
        case .automation:
            // Can't pre-check without sending an AppleEvent; treat as available
            // and rely on graceful fallback if the runtime prompt is denied.
            return true
        }
    }
}

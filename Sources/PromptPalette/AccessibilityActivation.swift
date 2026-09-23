import Foundation
import ApplicationServices

/// Activates the renderer and checks Electron's readable state at most every five
/// seconds when focus is unavailable. Readable focus needs no recovery, even if
/// Electron reports a partial accessibility mode through its manual switch.
final class AccessibilityActivation {
    private var finished = Set<pid_t>()
    private var manual = Set<pid_t>()
    private var retryAfter: [pid_t: TimeInterval] = [:]

    func enable(pid: pid_t, now: TimeInterval = ProcessInfo.processInfo.systemUptime,
                hasFocusedElement: Bool = false,
                manualState: () -> Bool? = { nil },
                setAttribute: (String) -> AXError) {
        guard now >= (retryAfter[pid] ?? 0) else { return }
        if finished.contains(pid) {
            guard manual.contains(pid), !hasFocusedElement else { return }
            retryAfter[pid] = now + 5
            // Missing focus alone is normal (menus, window switches, etc.). An
            // unreadable state is not evidence that activation has been lost.
            guard manualState() == false else { return }
        }
        retryAfter[pid] = now + 5

        // Electron exposes a dedicated switch. Plain Chromium uses the general
        // assistive-technology switch instead; prefer Electron's when available.
        var result = setAttribute("AXManualAccessibility")
        if result == .success { manual.insert(pid) }
        let usesFallback = result == .attributeUnsupported || result == .notImplemented
        if usesFallback {
            result = setAttribute("AXEnhancedUserInterface")
        }

        switch result {
        case .success, .attributeUnsupported, .notImplemented:
            if usesFallback { manual.remove(pid) }
            // Do not repeat completed or unsupported requests. Chromium can
            // apply the enhanced request before its superclass returns an error;
            // regular focus checks remain active while its tree initializes.
            finished.insert(pid)
        default:
            retryAfter[pid] = now + 5
        }
    }
}

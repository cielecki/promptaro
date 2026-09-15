import Foundation
import ApplicationServices

/// Requests the renderer's accessibility tree once per process. Transient IPC
/// failures can recover without repeating activation on every focus notification.
final class AccessibilityActivation {
    private var finished = Set<pid_t>()
    private var retryAfter: [pid_t: TimeInterval] = [:]

    func enable(pid: pid_t, now: TimeInterval = ProcessInfo.processInfo.systemUptime,
                setAttribute: (String) -> AXError) {
        guard !finished.contains(pid), now >= (retryAfter[pid] ?? 0) else { return }

        // Electron exposes a dedicated switch. Plain Chromium uses the general
        // assistive-technology switch instead; prefer Electron's when available.
        var result = setAttribute("AXManualAccessibility")
        if result == .attributeUnsupported || result == .notImplemented {
            result = setAttribute("AXEnhancedUserInterface")
        }

        switch result {
        case .success, .attributeUnsupported, .notImplemented:
            // Do not repeat completed or unsupported requests. Chromium can
            // apply the enhanced request before its superclass returns an error;
            // regular focus checks remain active while its tree initializes.
            finished.insert(pid)
            retryAfter.removeValue(forKey: pid)
        default:
            retryAfter[pid] = now + 5
        }
    }
}

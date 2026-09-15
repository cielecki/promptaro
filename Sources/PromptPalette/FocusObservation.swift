import AppKit
import ApplicationServices
import OSLog

/// Observe only the active app and the focused composer's local layout.
/// A slow refresh in AppDelegate covers renderers that omit AX notifications.
final class FocusObservation {
    var onChange: (() -> Void)?
    private let logger = Logger(subsystem: "pl.maciej.prompt-palette", category: "Observation")
    private var receivedEvent = false
    private var observer: AXObserver?
    private var pid: pid_t?
    private var application: AXUIElement?
    private var elements: [AXUIElement] = []
    private var pending: DispatchWorkItem?
    private var workspaceToken: NSObjectProtocol?

    init() {
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRefresh() }
    }

    func observe(pid: pid_t?, elements: [AXUIElement]? = nil) {
        if self.pid != pid {
            disconnect()
            self.pid = pid
            if let pid {
                var created: AXObserver?
                let result = AXObserverCreate(pid, { _, _, _, context in
                    guard let context else { return }
                    Unmanaged<FocusObservation>.fromOpaque(context).takeUnretainedValue().accessibilityChanged()
                }, &created)
                if result == .success, let created {
                    observer = created
                    let app = AXUIElementCreateApplication(pid)
                    application = app
                    for name in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
                        add(name, to: app)
                    }
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
                }
            }
        }
        guard let observer, let elements else { return }
        let removed = self.elements.filter { old in !elements.contains { CFEqual(old, $0) } }
        let added = elements.filter { new in !self.elements.contains { CFEqual(new, $0) } }
        for element in removed {
            for name in Self.layoutNotifications {
                AXObserverRemoveNotification(observer, element, name as CFString)
            }
        }
        self.elements = elements
        for element in added {
            for name in Self.layoutNotifications { add(name, to: element) }
        }
    }

    private static let layoutNotifications = [
        kAXMovedNotification, kAXResizedNotification, kAXLayoutChangedNotification,
        kAXValueChangedNotification, kAXUIElementDestroyedNotification
    ]

    private func add(_ name: String, to element: AXUIElement) {
        guard let observer else { return }
        // Notification support varies by renderer; the periodic refresh remains active.
        AXObserverAddNotification(observer, element, name as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
    }

    private func accessibilityChanged() {
        if !receivedEvent {
            receivedEvent = true
            logger.notice("Receiving Accessibility changes for the active app.")
        }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        // Coalesce bursts without pushing the deadline back during continuous changes.
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.onChange?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func disconnect() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        receivedEvent = false
        observer = nil
        application = nil
        elements = []
    }

    deinit {
        pending?.cancel()
        disconnect()
        if let workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken) }
    }
}

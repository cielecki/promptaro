import AppKit
import ApplicationServices
import PromptCore
import OSLog

enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    static func string(_ element: AXUIElement, _ attribute: String) -> String {
        value(element, attribute) as? String ?? ""
    }
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(element, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p),
              AXValueGetValue(size as! AXValue, .cgSize, &s), s.width > 0, s.height > 0 else { return nil }
        return CGRect(origin: p, size: s)
    }
    static func selection(_ element: AXUIElement) -> NSRange? {
        guard let value = value(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func textSnapshot(_ element: AXUIElement) -> ComposerTextSnapshot {
        var readings: [ComposerTextSnapshot.Source: String] = [:]
        // Read every supported representation. A successful range read does not
        // mean it contains the same paragraph breaks or latest content as AXValue.
        if let count = value(element, kAXNumberOfCharactersAttribute) as? NSNumber,
           count.intValue >= 0, count.intValue <= 1_000_000 {
            var range = CFRange(location: 0, length: count.intValue)
            if let parameter = AXValueCreate(.cfRange, &range) {
                let attributes: [(ComposerTextSnapshot.Source, String)] = [
                    (.stringForRange, kAXStringForRangeParameterizedAttribute),
                    (.attributedStringForRange, kAXAttributedStringForRangeParameterizedAttribute)
                ]
                for (source, attribute) in attributes {
                    var result: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &result) == .success {
                        readings[source] = (result as? String) ?? (result as? NSAttributedString)?.string
                    }
                }
            }
        }
        let rawValue = value(element, kAXValueAttribute)
        readings[.value] = (rawValue as? String) ?? (rawValue as? NSAttributedString)?.string
        return ComposerTextSnapshot(readings: readings)
    }

    struct ComposerLayout {
        let frame: CGRect
        let elements: [AXUIElement]
        let panelCount: Int
    }

    static func webURL(for input: AXUIElement) -> URL? {
        var ancestor: AXUIElement? = input
        for _ in 0..<32 {
            guard let node = ancestor else { break }
            let role = string(node, kAXRoleAttribute)
            if role == "AXWebArea", let raw = value(node, kAXURLAttribute),
               let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:)),
               ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                return url
            }
            if [kAXWindowRole, kAXApplicationRole].contains(role) { break }
            ancestor = element(node, kAXParentAttribute)
        }
        return nil
    }

    static func composerLayout(for input: AXUIElement, openCode: Bool = false) -> ComposerLayout? {
        var ancestor: AXUIElement? = input
        var branch: AXUIElement?
        var body: CGRect?
        var panels: [CGRect] = []
        var observed: [AXUIElement] = []
        for _ in 0..<24 {
            guard let node = ancestor else { break }
            let role = string(node, kAXRoleAttribute)
            let classes = value(node, "AXDOMClassList") as? [String] ?? []
            // Never search the transcript or other composers for a matching panel.
            if [kAXWindowRole, kAXApplicationRole, "AXWebArea"].contains(role)
                || classes.contains("thread-scroll-container") { break }
            observed.append(node)
            if openCode, ComposerSurface.isOpenCodePrompt(classes: classes), let bounds = frame(node) {
                return ComposerLayout(frame: bounds, elements: observed, panelCount: 0)
            }
            if !openCode, ComposerSurface.isApprovalDock(classes: classes), let bounds = frame(node) {
                return ComposerLayout(frame: bounds, elements: observed, panelCount: 0)
            }
            if ComposerSurface.isBody(classes: classes) { body = frame(node) }
            if body == nil, ComposerSurface.isForm(subrole: string(node, kAXSubroleAttribute),
                                                   tagName: string(node, "AXDOMTagName")) {
                body = frame(node)
            }
            if body != nil, let branch {
                let siblings = (value(node, kAXChildrenAttribute) as? [AXUIElement] ?? [])
                    .filter { !CFEqual($0, branch) }
                for sibling in siblings {
                    let classes = value(sibling, "AXDOMClassList") as? [String] ?? []
                    if ComposerSurface.isRail(classes: classes) || ComposerSurface.isTopTray(classes: classes),
                       let bounds = frame(sibling) {
                        panels.append(bounds)
                        observed.append(sibling)
                    }
                }
            }
            branch = node
            ancestor = element(node, kAXParentAttribute)
        }
        guard !openCode, let body else { return nil }
        return ComposerLayout(frame: ComposerSurface.anchor(body: body, panels: panels), elements: observed, panelCount: panels.count)
    }

}

struct ChatTarget {
    let pid: pid_t
    let element: AXUIElement
    let frame: CGRect
    let appName: String
    var layoutElements: [AXUIElement] = []
    var documentURL: URL?
    func matches(_ other: ChatTarget?) -> Bool {
        guard let other else { return false }
        return pid == other.pid && CFEqual(element, other.element) && documentURL == other.documentURL
    }
}

final class FocusTracker {
    private let accessibilityActivation = AccessibilityActivation()
    private let logger = Logger(subsystem: "pl.maciej.prompt-palette", category: "Layout")
    private var lastPanelCount: Int?
    private var lastDecision: String?

    private func recordDecision(_ decision: String, bundle: String) {
        guard ComposerPolicy.bundleIDs.contains(bundle) else { return }
        let state = "\(bundle): \(decision)"
        guard state != lastDecision else { return }
        lastDecision = state
        logger.notice("Focus detection: \(state, privacy: .public)")
    }

    func current(includeComposerFrame: Bool = true) -> ChatTarget? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              let bundle = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let nativeChat = ComposerPolicy.bundleIDs.contains(bundle)
        let openCode = bundle == "ai.opencode.desktop"
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        var focusedElement = AX.element(application, kAXFocusedUIElementAttribute)
        if nativeChat {
            accessibilityActivation.enable(pid: app.processIdentifier,
                                          hasFocusedElement: focusedElement != nil, manualState: {
                AX.value(application, "AXManualAccessibility") as? Bool
            }) { attribute in
                let result = AXUIElementSetAttributeValue(application, attribute as CFString, kCFBooleanTrue)
                logger.notice("Accessibility activation: \(bundle, privacy: .public) \(attribute, privacy: .public) result: \(result.rawValue)")
                return result
            }
            if focusedElement == nil { focusedElement = AX.element(application, kAXFocusedUIElementAttribute) }
        }
        guard var focused = focusedElement else {
            recordDecision("no focused element", bundle: bundle)
            return nil
        }
        var roles: [String] = []
        // Some web editors focus a child inside their accessible text area.
        for _ in 0..<4 {
            let role = AX.string(focused, kAXRoleAttribute)
            roles.append(role)
            let hints = [kAXPlaceholderValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXIdentifierAttribute, "AXDOMIdentifier"]
                .map { AX.string(focused, $0) }.joined(separator: " ")
            if ComposerPolicy.accepts(role: role, subrole: AX.string(focused, kAXSubroleAttribute),
                                      hints: hints, editable: AX.value(focused, "AXEditable") as? Bool),
               AX.value(focused, kAXEnabledAttribute) as? Bool != false,
               let rect = AX.frame(focused) {
                let web = nativeChat ? nil : AX.webURL(for: focused)
                if !nativeChat {
                    guard let web, ComposerPolicy.acceptsWebURL(web) else { return nil }
                }
                let surface = includeComposerFrame || openCode ? AX.composerLayout(for: focused, openCode: openCode) : nil
                if openCode {
                    // OpenCode also contains a terminal, file editors, and a shell
                    // mode. Only its normal prompt form is a chat target.
                    let classes = AX.value(focused, "AXDOMClassList") as? [String] ?? []
                    guard !classes.contains("font-mono!"), surface != nil else { return nil }
                }
                if includeComposerFrame, lastPanelCount != (surface?.panelCount ?? -1) {
                    lastPanelCount = surface?.panelCount ?? -1
                    if let surface { logger.notice("Composer surface resolved with \(surface.panelCount) adjacent panels.") }
                    else { logger.notice("Composer surface not exposed; using text input bounds.") }
                }
                // Recompute the entire composer on every poll: attachments can grow
                // above the text area without moving the caret or changing focus.
                recordDecision("composer detected", bundle: bundle)
                return ChatTarget(pid: app.processIdentifier, element: focused,
                                  frame: surface?.frame ?? rect,
                                  appName: app.localizedName ?? "Chat",
                                  layoutElements: surface?.elements ?? [focused],
                                  documentURL: web)
            }
            guard let parent = AX.element(focused, kAXParentAttribute) else { break }
            focused = parent
        }
        recordDecision("no accepted input (roles: \(roles.joined(separator: ", ")))", bundle: bundle)
        return nil
    }
}

final class PromptSender {
    private let tracker: FocusTracker
    private(set) var busy = false
    var onStatus: ((String?) -> Void)?
    init(tracker: FocusTracker) { self.tracker = tracker }

    func send(_ prompt: Prompt, to target: ChatTarget) {
        guard !busy, target.matches(tracker.current(includeComposerFrame: false)) else { NSSound.beep(); return }
        let before = AX.textSnapshot(target.element)
        guard before.isReadable else {
            onStatus?("This input cannot be verified. Nothing was sent.")
            return
        }
        let selection = AX.selection(target.element)
        let clipboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (clipboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        busy = true
        onStatus?("Inserting…")
        clipboard.clearContents()
        guard clipboard.setString(prompt.text, forType: .string) else {
            restoreClipboard(saved, ifUnchanged: clipboard.changeCount)
            busy = false
            onStatus?("Could not put the prompt on the clipboard.")
            return
        }
        let changeCount = clipboard.changeCount
        guard target.matches(tracker.current(includeComposerFrame: false)), key(9, flags: .maskCommand) else {
            finish(saved, changeCount, "Focus changed. Nothing was sent.")
            return
        }
        verify(prompt: prompt, target: target, before: before, selection: selection,
               saved: saved, changeCount: changeCount, attempts: 0)
    }

    private func verify(prompt: Prompt, target: ChatTarget, before: ComposerTextSnapshot, selection: NSRange?,
                        saved: [[NSPasteboard.PasteboardType: Data]], changeCount: Int, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
            guard let current = tracker.current(includeComposerFrame: false), target.matches(current) else {
                finish(saved, changeCount, "Focus changed. Return was not pressed.")
                return
            }
            // Reacquire the focused object after the editor has processed the paste.
            let after = AX.textSnapshot(current.element)
            if before.verifiesInsertion(after: after, inserted: prompt.text, selection: selection) {
                guard key(36) else { finish(saved, changeCount, "Prompt inserted. Press Return to send."); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in finish(saved, changeCount, nil) }
            } else if attempts < 19 {
                verify(prompt: prompt, target: target, before: before, selection: selection,
                       saved: saved, changeCount: changeCount, attempts: attempts + 1)
            } else {
                finish(saved, changeCount, "Could not verify insertion. Return was not pressed.")
            }
        }
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func finish(_ saved: [[NSPasteboard.PasteboardType: Data]], _ count: Int, _ message: String?) {
        restoreClipboard(saved, ifUnchanged: count)
        busy = false
        onStatus?(message)
    }

    private func restoreClipboard(_ saved: [[NSPasteboard.PasteboardType: Data]], ifUnchanged count: Int) {
        let clipboard = NSPasteboard.general
        guard clipboard.changeCount == count else { return } // Keep anything copied while we were sending.
        clipboard.clearContents()
        let items = saved.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { clipboard.writeObjects(items) }
    }
}

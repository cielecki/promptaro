import AppKit
import ApplicationServices
import ServiceManagement
import PromptCore
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tracker = FocusTracker()
    private let observation = FocusObservation()
    private lazy var sender = PromptSender(tracker: tracker)
    private let palette = PaletteController()
    private let editor = EditorController()
    private let store = ConfigurationStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Prompt Palette/prompts.json"))
    private var configuration = Configuration()
    private var statusItem: NSStatusItem!
    private var loginItem: NSMenuItem?
    private var timer: Timer?
    private var target: ChatTarget?
    private var dismissedTarget: ChatTarget?
    private var paused = false
    private var hadTrust = false
    private var previewing = false
    private let logger = Logger(subsystem: "pl.maciej.prompt-palette", category: "Visibility")
    private var lastVisibilityReason: String?

    private func recordVisibility(_ reason: String) {
        guard reason != lastVisibilityReason else { return }
        lastVisibilityReason = reason
        logger.notice("Overlay: \(reason, privacy: .public)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        do { configuration = try store.load() }
        catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not load your prompts"
            alert.informativeText = "\(error.localizedDescription)\n\nYour file was left unchanged at \(store.url.path)."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        palette.rebuild(configuration)
        palette.onPrompt = { [weak self] prompt in
            guard let self, let target = self.target, !self.paused else { return }
            self.sender.send(prompt, to: target)
        }
        palette.onEdit = { [weak self] in self?.editPrompts() }
        palette.onDismiss = { [weak self] in
            guard let self else { return }
            self.dismissedTarget = self.target
            self.previewing = false
        }
        editor.onPreview = { [weak self] config, input in
            guard let self else { return }
            self.previewing = true
            self.target = nil
            self.palette.rebuild(config)
            self.palette.status("Preview — these buttons appear above your chat input", busy: false)
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            self.palette.show(near: CGRect(x: input.minX, y: mainHeight - input.maxY, width: input.width, height: input.height))
        }
        sender.onStatus = { [weak self] message in
            guard let self else { return }
            self.palette.status(message, busy: self.sender.busy)
        }
        editor.onSave = { [weak self] config in
            guard let self else { return }
            try self.store.save(config)
            self.previewing = false
            self.configuration = config
            self.palette.rebuild(config)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: AppIdentity.name)
        statusItem.button?.toolTip = AppIdentity.name
        statusItem.button?.setAccessibilityLabel(AppIdentity.name)
        rebuildMenu()
        observation.onChange = { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.1
        RunLoop.main.add(timer!, forMode: .common)
        tick()
        if !AXIsProcessTrusted() || !FileManager.default.fileExists(atPath: store.url.path) { editPrompts() }
        if CommandLine.arguments.contains("--preview") {
            timer?.invalidate()
            observation.onChange = nil
            palette.panel.center()
            palette.panel.setFrameOrigin(NSPoint(x: 100, y: 100))
            palette.panel.orderFrontRegardless()
        }
    }

    private func tick() {
        let trusted = AXIsProcessTrusted()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let observedPID = trusted && !paused && frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier
            ? frontmost?.processIdentifier : nil
        // Keep focus notifications active even when no composer currently has focus.
        observation.observe(pid: observedPID)
        if trusted != hadTrust {
            hadTrust = trusted
            editor.refreshPermission()
            rebuildMenu()
        }
        if previewing, editor.window?.isVisible == true,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        if previewing {
            previewing = false
            palette.rebuild(configuration)
        }
        // A background editor window must not suppress the overlay in another app.
        // FocusTracker already excludes our own app while the editor is active.
        guard trusted, !paused else {
            recordVisibility(trusted ? "paused" : "accessibility permission missing")
            target = nil
            palette.hide()
            return
        }
        target = tracker.current()
        var elements = target?.layoutElements ?? []
        if let input = target?.element, let window = AX.element(input, kAXWindowAttribute) { elements.append(window) }
        observation.observe(pid: observedPID, elements: elements)
        if let dismissedTarget, dismissedTarget.matches(target) {
            recordVisibility("dismissed for this input")
            palette.hide()
            return
        }
        dismissedTarget = nil
        if let target {
            palette.show(near: target.frame)
            recordVisibility("shown")
        } else {
            palette.hide()
            recordVisibility("no eligible focused input")
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let state = NSMenuItem(title: !AXIsProcessTrusted() ? "Accessibility permission needed" :
                                paused ? "Paused" : "Ready for desktop and web chats", action: nil, keyEquivalent: "")
        menu.addItem(state)
        menu.addItem(.separator())
        func item(_ title: String, _ action: Selector, _ key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        item("Edit Prompts…", #selector(editPrompts), ",")
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        loginItem = login
        refreshLoginItem()
        menu.addItem(login)
        item(paused ? "Resume" : "Pause", #selector(togglePause))
        item("Accessibility Settings…", #selector(accessibilitySettings))
        item("About \(AppIdentity.name)…", #selector(about))
        if AppIdentity.supportURL != nil {
            item("Support My Work…", #selector(supportMyWork))
        }
        menu.addItem(.separator())
        item("Quit \(AppIdentity.name)", #selector(quit), "q")
        statusItem?.menu = menu
    }

    private func installMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: AppIdentity.name)
        let edit = NSMenuItem(title: "Edit Prompts…", action: #selector(editPrompts), keyEquivalent: ",")
        edit.target = self
        applicationMenu.addItem(edit)
        applicationMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit \(AppIdentity.name)", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
                                     ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    @objc private func editPrompts() { previewing = false; palette.hide(); editor.present(configuration) }
    @objc private func togglePause() { paused.toggle(); rebuildMenu(); tick() }
    @objc private func accessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func menuWillOpen(_ menu: NSMenu) { refreshLoginItem() }
    private func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        loginItem?.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
        loginItem?.title = status == .requiresApproval ? "Launch at Login — Approval Needed…" : "Launch at Login"
    }
    @objc private func supportMyWork() {
        guard let url = AppIdentity.supportURL else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppIdentity.name,
            .applicationVersion: AppIdentity.version,
            .credits: NSAttributedString(string: "Your saved prompts, above your chat.\n\nSaved prompts are stored on this Mac. Clicking a prompt sends it through your chat app.")
        ])
    }
    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            case .notFound:
                throw ValidationError("Move the app to Applications and reopen it before enabling Launch at Login.")
            @unknown default:
                throw ValidationError("Check this app in System Settings → General → Login Items.")
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        rebuildMenu()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if editor.window?.isVisible != true { editPrompts() }
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

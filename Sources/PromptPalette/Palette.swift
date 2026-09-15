import AppKit
import PromptCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PromptButton: NSButton {
    var invoke: (() -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    init(prompt: Prompt) {
        super.init(frame: .zero)
        title = prompt.buttonLabel
        toolTip = prompt.text
        alignment = .center
        isBordered = true
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12, weight: .medium)
        lineBreakMode = .byTruncatingTail
        target = self
        action = #selector(pressed)
        setAccessibilityLabel(prompt.buttonLabel)
        setAccessibilityHelp("Insert this prompt and press Return: " + prompt.text)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func pressed() { invoke?() }
}

final class PaletteController {
    let panel: FloatingPanel
    var onPrompt: ((Prompt) -> Void)?
    var onEdit: (() -> Void)?
    var onDismiss: (() -> Void)?
    private let statusLabel = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let edit = NSButton()
    private let close = NSButton()
    private var rows: [PromptButton] = []
    private var preferredWidth: CGFloat = 360
    private var message: String?

    init() {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 44),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityLabel(AppIdentity.name)

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        panel.contentView = effect
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        effect.addSubview(scroll)
        for (button, symbol, label, action) in [
            (edit, "pencil", "Edit prompts", #selector(editPrompts)),
            (close, "xmark", "Dismiss prompts", #selector(dismiss))
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.target = self
            button.action = action
            effect.addSubview(button)
        }
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        effect.addSubview(statusLabel)
    }

    func rebuild(_ config: Configuration) {
        let strip = NSView()
        var x: CGFloat = 0
        rows = config.prompts.map { prompt in
            let button = PromptButton(prompt: prompt)
            button.invoke = { [weak self] in self?.onPrompt?(prompt) }
            let width = min(156, max(66, button.intrinsicContentSize.width + 12))
            button.frame = NSRect(x: x, y: 0, width: width, height: 28)
            strip.addSubview(button)
            x += width + 6
            return button
        }
        if rows.isEmpty {
            let empty = NSTextField(labelWithString: "Add a prompt →")
            empty.font = .systemFont(ofSize: 12)
            empty.frame = NSRect(x: 4, y: 5, width: 118, height: 18)
            strip.addSubview(empty)
            x = 128
        }
        strip.frame = NSRect(x: 0, y: 0, width: max(0, x - 6), height: 28)
        scroll.documentView = strip
        preferredWidth = strip.frame.width + 82
        message = nil
        layout(width: min(preferredWidth, 680))
    }

    private func layout(width: CGFloat) {
        let footer: CGFloat = message == nil ? 0 : 20
        let size = NSSize(width: width, height: 44 + footer)
        if panel.frame.size != size { panel.setContentSize(size) }
        scroll.frame = NSRect(x: 8, y: 8 + footer, width: max(20, width - 82), height: 28)
        edit.frame = NSRect(x: width - 66, y: 10 + footer, width: 24, height: 24)
        close.frame = NSRect(x: width - 34, y: 10 + footer, width: 24, height: 24)
        statusLabel.isHidden = message == nil
        statusLabel.stringValue = message ?? ""
        statusLabel.toolTip = message
        statusLabel.frame = NSRect(x: 12, y: 7, width: width - 24, height: 16)
    }

    func show(near axFrame: CGRect) {
        // AX coordinates start at the top-left of the main display.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let input = NSRect(x: axFrame.minX, y: mainHeight - axFrame.maxY, width: axFrame.width, height: axFrame.height)
        let screen = NSScreen.screens.max { a, b in
            let x = a.frame.intersection(input), y = b.frame.intersection(input)
            return x.width * x.height < y.width * y.height
        } ?? NSScreen.main
        guard let screen else { return }
        let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        layout(width: min(preferredWidth, max(180, input.width), available.width, 680))
        let size = panel.frame.size
        // The anchor includes attachments and composer controls, not just the text.
        var y = input.maxY + 10
        if y + size.height > available.maxY { y = input.minY - size.height - 10 }
        let origin = NSPoint(x: min(max(input.midX - size.width / 2, available.minX), available.maxX - size.width),
                             y: min(max(y, available.minY), available.maxY - size.height))
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func status(_ message: String?, busy: Bool) {
        // Normal operation stays a single slim row. Errors remain visible below it.
        self.message = busy || message?.hasPrefix("Preview") == true ? nil : message
        layout(width: panel.frame.width)
        rows.forEach { $0.isEnabled = !busy }
    }
    func hide() { panel.orderOut(nil) }
    @objc private func editPrompts() { onEdit?() }
    @objc private func dismiss() { hide(); onDismiss?() }
}

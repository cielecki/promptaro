import AppKit
import ApplicationServices
import PromptCore

final class EditorController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var draft = Configuration()
    private var selected = -1
    private var restoringSelection = false
    private static let dragType = NSPasteboard.PasteboardType("pl.maciej.prompt-palette.prompt-row")
    private let table = NSTableView()
    private let label = NSTextField()
    private let body = NSTextView()
    private let permission = NSTextField(wrappingLabelWithString: "")
    private let remove = NSButton(title: "Remove", target: nil, action: nil)
    private let moveUp = NSButton()
    private let moveDown = NSButton()
    var onSave: ((Configuration) throws -> Void)?
    var onPreview: ((Configuration, NSRect) -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "\(AppIdentity.name) — Edit Prompts"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    func present(_ configuration: Configuration) {
        if window?.isVisible != true {
            configure(configuration)
        }
        refreshPermission()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func configure(_ configuration: Configuration) {
        draft = configuration
        restoreSelection(at: draft.prompts.isEmpty ? -1 : 0)
    }

    private func restoreSelection(at index: Int) {
        restoringSelection = true
        table.reloadData()
        table.selectRowIndexes(index >= 0 ? IndexSet(integer: index) : [], byExtendingSelection: false)
        loadSelection(index)
        if index >= 0 { table.scrollRowToVisible(index) }
        restoringSelection = false
    }

    func refreshPermission() {
        permission.stringValue = AXIsProcessTrusted()
            ? "Ready. Focus a chat input in a desktop app or browser to show your buttons."
            : "One-time setup: allow \(AppIdentity.name) in System Settings → Privacy & Security → Accessibility. This lets it detect the chat input and insert your prompts."
    }

    private func build() {
        guard let content = window?.contentView else { return }
        func caption(_ text: String, _ frame: NSRect) {
            let field = NSTextField(labelWithString: text)
            field.frame = frame
            field.font = .systemFont(ofSize: 12, weight: .semibold)
            content.addSubview(field)
        }
        let heading = NSTextField(labelWithString: "Your prompts, one click away.")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 491, width: 650, height: 28)
        content.addSubview(heading)
        permission.frame = NSRect(x: 24, y: 429, width: 528, height: 49)
        permission.font = .systemFont(ofSize: 12)
        permission.textColor = .secondaryLabelColor
        content.addSubview(permission)
        let access = NSButton(title: "Accessibility Settings…", target: self, action: #selector(openAccessibility))
        access.bezelStyle = .rounded
        access.frame = NSRect(x: 568, y: 441, width: 168, height: 30)
        content.addSubview(access)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
        column.width = 225
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 38
        table.delegate = self
        table.dataSource = self
        table.allowsEmptySelection = false
        table.style = .sourceList
        table.registerForDraggedTypes([Self.dragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        table.setAccessibilityLabel("Prompts")
        table.toolTip = "Drag prompts to change their button order."
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 143, width: 230, height: 267))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        content.addSubview(scroll)
        let add = NSButton(title: "+ Add", target: self, action: #selector(addPrompt))
        add.setAccessibilityLabel("Add prompt")
        add.bezelStyle = .rounded
        remove.target = self
        remove.action = #selector(removePrompt)
        remove.bezelStyle = .rounded
        for (button, symbol, name, action) in [
            (moveUp, "arrow.up", "Move prompt up", #selector(movePromptUp)),
            (moveDown, "arrow.down", "Move prompt down", #selector(movePromptDown))
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
            button.imagePosition = .imageOnly
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
            button.toolTip = name
            button.setAccessibilityLabel(name)
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let listActions = NSStackView(views: [add, remove, moveUp, moveDown])
        listActions.orientation = .horizontal
        listActions.alignment = .centerY
        listActions.distribution = .fill
        listActions.spacing = 12
        listActions.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(listActions)
        NSLayoutConstraint.activate([
            listActions.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            listActions.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            listActions.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12)
        ])

        caption("Button label (1–2 words)", NSRect(x: 278, y: 391, width: 310, height: 18))
        label.frame = NSRect(x: 278, y: 358, width: 458, height: 26)
        label.placeholderString = "A short name for your prompt"
        label.setAccessibilityLabel("Button label")
        content.addSubview(label)
        caption("Prompt text", NSRect(x: 278, y: 324, width: 310, height: 18))
        let textScroll = NSScrollView(frame: NSRect(x: 278, y: 105, width: 458, height: 211))
        textScroll.borderType = .bezelBorder
        textScroll.hasVerticalScroller = true
        body.isRichText = false
        body.font = .systemFont(ofSize: 14)
        body.textContainerInset = NSSize(width: 8, height: 8)
        body.isAutomaticQuoteSubstitutionEnabled = false
        body.isAutomaticDashSubstitutionEnabled = false
        body.isVerticallyResizable = true
        body.isHorizontallyResizable = false
        body.autoresizingMask = [.width]
        body.frame = NSRect(x: 0, y: 0, width: 456, height: 209)
        body.textContainer?.widthTracksTextView = true
        body.setAccessibilityLabel("Prompt text")
        textScroll.documentView = body
        content.addSubview(textScroll)
        let note = NSTextField(labelWithString: "Buttons paste at the cursor and press Return. Prompts are saved only on this Mac.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 24, y: 70, width: 712, height: 18)
        content.addSubview(note)
        let preview = NSButton(title: "Preview buttons", target: self, action: #selector(previewButtons))
        preview.bezelStyle = .rounded
        preview.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(preview)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelEdit))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save prompts", target: self, action: #selector(savePrompts))
        save.bezelStyle = .rounded
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = .command
        let actions = NSStackView(views: [cancel, save])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 12
        actions.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(actions)
        NSLayoutConstraint.activate([
            actions.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            actions.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            save.widthAnchor.constraint(greaterThanOrEqualToConstant: 118),
            preview.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            preview.centerYAnchor.constraint(equalTo: actions.centerYAnchor)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { draft.prompts.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = NSTextField(labelWithString: draft.prompts[row].title)
        view.lineBreakMode = .byTruncatingTail
        view.font = .systemFont(ofSize: 13)
        return view
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !restoringSelection else { return }
        let previous = selected
        captureSelection()
        loadSelection(table.selectedRow)
        if draft.prompts.indices.contains(previous) {
            table.reloadData(forRowIndexes: IndexSet(integer: previous), columnIndexes: IndexSet(integer: 0))
        }
    }
    private func captureSelection() {
        guard draft.prompts.indices.contains(selected) else { return }
        draft.prompts[selected].title = label.stringValue
        draft.prompts[selected].text = body.string
    }
    private func loadSelection(_ index: Int) {
        selected = index
        let prompt = draft.prompts.indices.contains(index) ? draft.prompts[index] : nil
        label.stringValue = prompt?.title ?? ""
        body.string = prompt?.text ?? ""
        label.isEnabled = prompt != nil
        body.isEditable = prompt != nil
        remove.isEnabled = prompt != nil
        moveUp.isEnabled = prompt != nil && index > 0
        moveDown.isEnabled = prompt != nil && index < draft.prompts.count - 1
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === table, draft.prompts.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(draft.prompts[row].id.uuidString, forType: Self.dragType)
        return item
    }

    private func draggedPrompt(_ info: NSDraggingInfo) -> UUID? {
        guard let source = info.draggingSource as? NSTableView, source === table,
              let value = info.draggingPasteboard.string(forType: Self.dragType),
              let id = UUID(uuidString: value), draft.prompts.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard tableView === table, (0...draft.prompts.count).contains(row),
              let id = draggedPrompt(info), let source = draft.prompts.firstIndex(where: { $0.id == id }),
              row != source, row != source + 1 else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation operation: NSTableView.DropOperation) -> Bool {
        guard tableView === table, operation == .above, let id = draggedPrompt(info) else { return false }
        return movePrompt(id: id, beforeRow: row)
    }

    @discardableResult
    func movePrompt(id: UUID, beforeRow row: Int) -> Bool {
        guard (0...draft.prompts.count).contains(row),
              let source = draft.prompts.firstIndex(where: { $0.id == id }) else { return false }
        let destination = row > source ? row - 1 : row
        guard destination != source else { return false }
        captureSelection()
        let selectedID = draft.prompts.indices.contains(selected) ? draft.prompts[selected].id : nil
        let prompt = draft.prompts.remove(at: source)
        draft.prompts.insert(prompt, at: destination)
        restoreSelection(at: draft.prompts.firstIndex(where: { $0.id == selectedID }) ?? destination)
        return true
    }

    @objc private func movePromptUp() {
        guard draft.prompts.indices.contains(selected), selected > 0 else { return }
        movePrompt(id: draft.prompts[selected].id, beforeRow: selected - 1)
    }

    @objc private func movePromptDown() {
        guard draft.prompts.indices.contains(selected), selected < draft.prompts.count - 1 else { return }
        movePrompt(id: draft.prompts[selected].id, beforeRow: selected + 2)
    }
    @objc private func addPrompt() {
        captureSelection()
        draft.prompts.append(Prompt(title: "New prompt", text: ""))
        selected = -1
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: draft.prompts.count - 1), byExtendingSelection: false)
        loadSelection(draft.prompts.count - 1)
        window?.makeFirstResponder(label)
    }
    @objc private func removePrompt() {
        guard draft.prompts.indices.contains(selected) else { return }
        let next = max(0, selected - 1)
        draft.prompts.remove(at: selected)
        selected = -1
        table.reloadData()
        if !draft.prompts.isEmpty {
            table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            loadSelection(next)
        } else { loadSelection(-1) }
    }
    @objc private func savePrompts() {
        captureSelection()
        do {
            try draft.validate()
            try onSave?(draft)
            window?.close()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save prompts"
            alert.informativeText = error.localizedDescription
            if let window { alert.beginSheetModal(for: window) }
        }
    }
    @objc private func cancelEdit() { window?.close() }
    @objc private func previewButtons() {
        captureSelection()
        guard let window else { return }
        onPreview?(draft, window.convertToScreen(body.convert(body.bounds, to: nil)))
    }
    @objc private func openAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

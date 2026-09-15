import AppKit
import PromptCore
import Testing
@testable import PromptPalette

@Suite(.serialized) @MainActor
struct EditorReorderingTests {
    private func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    private func makeEditor() -> (EditorController, Configuration, NSTableView, NSTextField, NSTextView, [NSButton]) {
        _ = NSApplication.shared
        let configuration = Configuration(prompts: [
            Prompt(title: "First", text: "First body"),
            Prompt(title: "Second", text: "Second body"),
            Prompt(title: "Third", text: "Third body")
        ])
        let editor = EditorController()
        editor.configure(configuration)
        let controls = views(in: editor.window!.contentView!)
        return (editor, configuration,
                controls.compactMap { $0 as? NSTableView }.first!,
                controls.compactMap { $0 as? NSTextField }.first { $0.placeholderString != nil }!,
                controls.compactMap { $0 as? NSTextView }.first!,
                controls.compactMap { $0 as? NSButton })
    }

    @Test func movingSelectedPromptPreservesUnsavedFieldsAndSavesOrder() {
        let (editor, original, table, label, body, buttons) = makeEditor()
        defer { editor.close() }
        label.stringValue = "Edited first"
        body.string = "Unsaved multiline\nprompt 🦉"
        var saved: Configuration?
        editor.onSave = { saved = $0 }

        #expect(editor.movePrompt(id: original.prompts[0].id, beforeRow: 3))
        #expect(table.selectedRow == 2)
        #expect(label.stringValue == "Edited first")
        #expect(body.string == "Unsaved multiline\nprompt 🦉")
        #expect(saved == nil)
        buttons.first { $0.title == "Save prompts" }!.performClick(nil)

        var expected = original.prompts[0]
        expected.title = "Edited first"
        expected.text = "Unsaved multiline\nprompt 🦉"
        #expect(saved?.prompts == [original.prompts[1], original.prompts[2], expected])
    }

    @Test func movingAnotherPromptRetainsSelectionAndArrowButtonsRespectEdges() {
        let (editor, original, table, label, body, buttons) = makeEditor()
        defer { editor.close() }
        let up = buttons.first { $0.toolTip == "Move prompt up" }!
        let down = buttons.first { $0.toolTip == "Move prompt down" }!
        #expect(!up.isEnabled)
        #expect(down.isEnabled)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        label.stringValue = "Edited second"
        body.string = "Preserved second"
        #expect(editor.movePrompt(id: original.prompts[2].id, beforeRow: 0))
        #expect(table.selectedRow == 2)
        #expect(label.stringValue == "Edited second")
        #expect(!down.isEnabled)
        up.performClick(nil)
        #expect(table.selectedRow == 1)
        up.performClick(nil)
        #expect(table.selectedRow == 0)
        #expect(!up.isEnabled)
        down.performClick(nil)
        #expect(table.selectedRow == 1)
        var preview: Configuration?
        editor.onPreview = { configuration, _ in preview = configuration }
        buttons.first { $0.title == "Preview buttons" }!.performClick(nil)
        var expected = original.prompts[1]
        expected.title = "Edited second"
        expected.text = "Preserved second"
        #expect(preview?.prompts == [original.prompts[2], expected, original.prompts[0]])
    }

    @Test func cancelDiscardsReorderingAndInvalidMovesLeaveDraftIntact() {
        let (editor, original, table, label, _, buttons) = makeEditor()
        defer { editor.close() }
        var saves = 0
        editor.onSave = { _ in saves += 1 }
        #expect(!editor.movePrompt(id: UUID(), beforeRow: 0))
        #expect(!editor.movePrompt(id: original.prompts[0].id, beforeRow: -1))
        #expect(!editor.movePrompt(id: original.prompts[0].id, beforeRow: 4))
        #expect(!editor.movePrompt(id: original.prompts[0].id, beforeRow: 1))
        #expect(editor.movePrompt(id: original.prompts[2].id, beforeRow: 0))
        label.stringValue = "Discard this edit"
        buttons.first { $0.title == "Cancel" }!.performClick(nil)
        #expect(saves == 0)
        editor.configure(original)
        #expect(table.selectedRow == 0)
        #expect(label.stringValue == "First")
        var preview: Configuration?
        editor.onPreview = { configuration, _ in preview = configuration }
        buttons.first { $0.title == "Preview buttons" }!.performClick(nil)
        #expect(preview == original)
        editor.configure(Configuration(prompts: []))
        #expect(buttons.filter { $0.toolTip?.hasPrefix("Move prompt") == true }.allSatisfy { !$0.isEnabled })
    }
}

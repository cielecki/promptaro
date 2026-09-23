import Foundation
import Testing
@testable import PromptCore

@Test func requestedDefaults() {
    #expect(Prompt.defaults.map(\.title) == ["Next step?", "Proceed", "Step back", "Explain", "TLDR", "Reorient", "Wrap up"])
    #expect(Prompt.defaults.map(\.text) == [
        "Next step? (Think through the possible paths forward. Plan so your next step can, where it makes sense, cover a long stretch of work on your own. In your final message, recommend that next step and ask every decision you need from me for it, each with your recommended answer.)",
        "Proceed (if you have any loose ends, tidy them up; If you proposed the next step, it's approved as proposed; If you asked me to do something, check whether it's done and finish it yourself if not; If you haven't proposed the next step, propose one now)",
        "Take a step back and look at the entire backlog, all the things we have open in this chat and lets do backlog grooming, prioritisation and operationalization of work.",
        "Explain in simple terms what you mean, because I don't understand. Most likely some of the things you mentioned need expanding upon.",
        "TLDR",
        "Reorient yourself in what has happened since we last talked",
        "Any loose ends? any leftovers from our work? anything to clean up or refactor related to what we did here?"
    ])
}

@Test func composerFiltering() {
    #expect(ComposerPolicy.accepts(role: "AXTextArea", subrole: "", hints: "", editable: nil))
    #expect(ComposerPolicy.accepts(role: "AXTextField", subrole: "", hints: "Message Claude", editable: true))
    #expect(!ComposerPolicy.accepts(role: "AXTextArea", subrole: "", hints: "Search chats", editable: true))
    #expect(!ComposerPolicy.accepts(role: "AXTextField", subrole: "AXSecureTextField", hints: "Message", editable: true))
    #expect(!ComposerPolicy.accepts(role: "AXTextArea", subrole: "", hints: "Message", editable: false))
    #expect(!ComposerPolicy.accepts(role: "AXTextField", subrole: "", hints: "Project name", editable: true))
    #expect(!ComposerPolicy.accepts(role: "AXButton", subrole: "", hints: "Send message", editable: true))
}

@Test func verifyInsertionBeforeReturn() {
    let inserted = "do this\nand that 🐈"
    let expected = ComposerPolicy.expectedValue(before: "Hi 🐈!", inserted: inserted, selection: NSRange(location: 3, length: 2))
    #expect(expected == "Hi do this\nand that 🐈!")
    #expect(ComposerPolicy.insertionVerified(before: "Hi 🐈!", after: expected!, inserted: inserted, expected: expected))
    #expect(!ComposerPolicy.insertionVerified(before: inserted, after: inserted, inserted: inserted, expected: inserted))
    #expect(!ComposerPolicy.insertionVerified(before: "", after: "do this", inserted: inserted, expected: inserted))
    #expect(!ComposerPolicy.insertionVerified(before: "", after: "unrelated", inserted: inserted, expected: nil))
    #expect(!ComposerPolicy.insertionVerified(before: "finalize", after: "x finalize", inserted: "finalize", expected: nil))
    #expect(ComposerPolicy.insertionVerified(before: "hello world", after: "hello finalize", inserted: "finalize", expected: nil))
    #expect(ComposerPolicy.insertionVerified(before: "hello ", after: "hello finalize", inserted: "finalize", expected: nil))
    #expect(ComposerPolicy.expectedValue(before: "a", inserted: "b", selection: NSRange(location: 5, length: 0)) == nil)
}

@Test func configurationPersistsEditsAndEmptyList() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(url: directory.appendingPathComponent("prompts.json"))
    #expect(try store.load().prompts.map(\.text) == Prompt.defaults.map(\.text))
    var config = Configuration(prompts: [Prompt(title: "Multiline", text: "zażółć 🐈\nsecond line")])
    try store.save(config)
    #expect(try store.load() == config)
    config.prompts = []
    try store.save(config)
    #expect(try store.load().prompts.isEmpty)
}

@Test func rejectInvalidConfigurationWithoutOverwriting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(url: directory.appendingPathComponent("prompts.json"))
    let good = Configuration()
    try store.save(good)
    let bad = Configuration(prompts: [Prompt(title: "", text: "test")])
    #expect(throws: (any Error).self) { try store.save(bad) }
    #expect(try store.load() == good)
    try Data("broken".utf8).write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try String(contentsOf: store.url, encoding: .utf8) == "broken")
}

@Test func legacySettingsKeepPromptsAndDropShortcuts() throws {
    let json = #"{"prompts":[{"id":"2EE9BDE2-0573-4496-9BB4-4A93523223D2","title":"My prompt","text":"Keep this text","shortcut":"u"}],"shortcutsEnabled":true}"#
    let config = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    #expect(config.prompts.first?.text == "Keep this text")
    let saved = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
    #expect(!saved.contains("shortcut"))
}

@Test func richEditorParagraphsAndStaleSelection() {
    let prompt = "ok what is the next logical step?"
    // OpenCode's empty editor exposes a zero-width placeholder that paste removes.
    #expect(ComposerPolicy.insertionVerified(before: "\u{200b}", after: prompt, inserted: prompt, expected: "\u{200b}" + prompt))
    // Empty ProseMirror-style paragraph and its trailing accessible line break.
    #expect(ComposerPolicy.insertionVerified(before: "\n", after: prompt + "\n", inserted: prompt, expected: "\n" + prompt))
    #expect(ComposerPolicy.insertionVerified(before: "", after: prompt.replacingOccurrences(of: " ", with: "\u{00a0}") + "\n", inserted: prompt, expected: prompt))
    // The selection offset reports the start while the real cursor is at the end.
    #expect(ComposerPolicy.insertionVerified(before: "Please: ", after: "Please: finalize\n", inserted: "finalize", expected: "finalizePlease: "))
    #expect(ComposerPolicy.insertionVerified(before: "", after: "first\u{2029}second\n", inserted: "first\nsecond", expected: "first\nsecond"))
    // An unchanged old prompt, partial paste, or unrelated typing must still fail.
    #expect(!ComposerPolicy.insertionVerified(before: prompt, after: prompt + "\n", inserted: prompt, expected: prompt))
    #expect(!ComposerPolicy.insertionVerified(before: "", after: "ok what is the next", inserted: prompt, expected: prompt))
    #expect(!ComposerPolicy.insertionVerified(before: "finalize", after: "x finalize", inserted: "finalize", expected: "finalizefinalize"))
    #expect(!ComposerPolicy.insertionVerified(before: "", after: "first second", inserted: "first\nsecond", expected: "first\nsecond"))
}

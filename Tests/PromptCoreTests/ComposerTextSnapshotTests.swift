import Foundation
import Testing
@testable import PromptCore

struct ComposerTextSnapshotTests {
    private let prompt = "First paragraph.\n\nSecond paragraph. "

    @Test func completeValueVerifiesDespiteLossyOrStaleRangeRead() {
        let before = ComposerTextSnapshot(readings: [.stringForRange: "", .attributedStringForRange: "", .value: ""])
        for range in ["", "First paragraph.", "First paragraph.\nSecond paragraph."] {
            let after = ComposerTextSnapshot(readings: [.stringForRange: range, .attributedStringForRange: range, .value: prompt + "\n"])
            #expect(before.verifiesInsertion(after: after, inserted: prompt, selection: NSRange(location: 0, length: 0)))
        }
    }

    @Test func completeRangeVerifiesDespiteStaleValue() {
        for source in [ComposerTextSnapshot.Source.stringForRange, .attributedStringForRange] {
            let before = ComposerTextSnapshot(readings: [source: "", .value: ""])
            let after = ComposerTextSnapshot(readings: [source: prompt, .value: ""])
            #expect(before.verifiesInsertion(after: after, inserted: prompt, selection: NSRange(location: 0, length: 0)))
        }
    }

    @Test func differencesBetweenSourcesNeverProveInsertion() {
        // These readings disagree before the click and never change afterward.
        // Comparing an empty range before with the value after would be unsafe.
        let before = ComposerTextSnapshot(readings: [.stringForRange: "", .value: prompt])
        #expect(!before.verifiesInsertion(after: before, inserted: prompt, selection: nil))
        let after = ComposerTextSnapshot(readings: [.value: prompt])
        #expect(!ComposerTextSnapshot(readings: [.stringForRange: ""]).verifiesInsertion(after: after, inserted: prompt, selection: nil))
    }

    @Test func chatGPTParagraphSpacingDoesNotBlockSubmission() {
        // Observed in ChatGPT Work in Chrome: paste has a blank line and the
        // rendered composer has two spaced paragraphs, but AXValue has one LF.
        let before = ComposerTextSnapshot(readings: [.value: ""])
        let after = ComposerTextSnapshot(readings: [.value: "First paragraph.\nSecond paragraph. "])
        #expect(before.verifiesInsertion(after: after, inserted: prompt, selection: NSRange(location: 0, length: 0)))
    }

    @Test func paragraphSpacingAloneDoesNotProveInsertion() {
        let before = ComposerTextSnapshot(readings: [.value: prompt])
        let after = ComposerTextSnapshot(readings: [.value: "First paragraph.\nSecond paragraph. "])
        #expect(!before.verifiesInsertion(after: after, inserted: prompt, selection: nil))
    }

    @Test func missingParagraphTextOrBoundariesStillFail() {
        let before = ComposerTextSnapshot(readings: [.value: ""])
        for text in ["First paragraph.", "First paragraph. Second paragraph.", "First paragraph.\nDifferent paragraph.", "Second paragraph.\nFirst paragraph."] {
            #expect(!before.verifiesInsertion(after: ComposerTextSnapshot(readings: [.value: text]), inserted: prompt, selection: nil))
        }
    }

    @Test func multilineInsertionPreservesExistingDraftAndSelection() {
        let draft = "Keep 🐈: replace this; keep this too"
        let selection = (draft as NSString).range(of: "replace this")
        let expected = (draft as NSString).replacingCharacters(in: selection, with: prompt)
        let before = ComposerTextSnapshot(readings: [.value: draft])
        #expect(before.verifiesInsertion(after: ComposerTextSnapshot(readings: [.value: expected]), inserted: prompt, selection: selection))
        #expect(!before.verifiesInsertion(after: ComposerTextSnapshot(readings: [.value: "unrelated " + prompt]), inserted: prompt, selection: selection))
    }

    @Test func unreadableAndReadableEmptyAreDifferent() {
        #expect(!ComposerTextSnapshot(readings: [:]).isReadable)
        #expect(ComposerTextSnapshot(readings: [.value: ""]).isReadable)
        #expect(!ComposerTextSnapshot(readings: [:]).verifiesInsertion(after: ComposerTextSnapshot(readings: [.value: prompt]), inserted: prompt, selection: nil))
    }
}

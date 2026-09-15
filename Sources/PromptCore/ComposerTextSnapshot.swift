import Foundation

/// Keep Accessibility representations separate: a range response can lag or
/// differ in paragraph formatting from the editor's value response.
public struct ComposerTextSnapshot {
    public enum Source: CaseIterable { case stringForRange, attributedStringForRange, value }
    public let readings: [Source: String]

    public init(readings: [Source: String]) { self.readings = readings }
    public var isReadable: Bool { !readings.isEmpty }

    public func verifiesInsertion(after: ComposerTextSnapshot, inserted: String, selection: NSRange?) -> Bool {
        Source.allCases.contains { source in
            guard let before = readings[source], let after = after.readings[source] else { return false }
            return ComposerPolicy.insertionVerified(
                before: before, after: after, inserted: inserted,
                expected: ComposerPolicy.expectedValue(before: before, inserted: inserted, selection: selection)
            )
        }
    }
}

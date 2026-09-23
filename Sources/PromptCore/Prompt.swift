import Foundation

public struct Prompt: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var text: String

    public init(id: UUID = UUID(), title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }

    public var buttonLabel: String {
        title.split(whereSeparator: { $0.isWhitespace }).prefix(2).joined(separator: " ")
    }

    public static let defaults = [
        Prompt(title: "Next step?", text: "Next step? (Think through the possible paths forward. Plan so your next step can, where it makes sense, cover a long stretch of work on your own. In your final message, recommend that next step and ask every decision you need from me for it, each with your recommended answer.)"),
        Prompt(title: "Proceed", text: "Proceed (if you have any loose ends, tidy them up; If you proposed the next step, it's approved as proposed; If you asked me to do something, check whether it's done and finish it yourself if not; If you haven't proposed the next step, propose one now)"),
        Prompt(title: "Step back", text: "Take a step back and look at the entire backlog, all the things we have open in this chat and lets do backlog grooming, prioritisation and operationalization of work."),
        Prompt(title: "Explain", text: "Explain in simple terms what you mean, because I don't understand. Most likely some of the things you mentioned need expanding upon."),
        Prompt(title: "TLDR", text: "TLDR"),
        Prompt(title: "Reorient", text: "Reorient yourself in what has happened since we last talked"),
        Prompt(title: "Wrap up", text: "Any loose ends? any leftovers from our work? anything to clean up or refactor related to what we did here?")
    ]
}

public struct Configuration: Codable, Equatable {
    public var prompts: [Prompt]
    public init(prompts: [Prompt] = Prompt.defaults) {
        self.prompts = prompts
    }

    public func validate() throws {
        for prompt in prompts {
            guard !prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("Each prompt needs a button label and prompt text.")
            }

        }
    }
}

public struct ValidationError: LocalizedError {
    public let errorDescription: String?
    public init(_ description: String) { errorDescription = description }
}

public final class ConfigurationStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        try config.validate()
        return config
    }
    public func save(_ configuration: Configuration) throws {
        try configuration.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: url, options: .atomic)
        guard try load() == configuration else { throw ValidationError("Could not verify saved prompts.") }
    }
}

public enum ComposerPolicy {
    public static let bundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex",
        "ai.opencode.desktop"
    ]

    // A multiline editor is not evidence of an AI chat. Match exact service hosts
    // before applying the generic editor heuristics, regardless of the browser.
    public static let webChatHosts: Set<String> = [
        "chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com",
        "copilot.microsoft.com", "perplexity.ai", "www.perplexity.ai",
        "grok.com", "chat.mistral.ai", "chat.deepseek.com"
    ]

    public static func acceptsWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else { return false }
        return webChatHosts.contains(host)
    }

    public static func accepts(role: String, subrole: String, hints: String, editable: Bool?) -> Bool {
        guard subrole != "AXSecureTextField", editable != false else { return false }
        let hint = hints.lowercased()
        if ["search", "find in", "rename", "title", "filter", "password"].contains(where: hint.contains) { return false }
        let composerHint = ["message", "reply", "ask", "prompt", "chat", "claude", "follow-up", "follow up"].contains(where: hint.contains)
        if role == "AXTextArea" { return true }
        return role == "AXTextField" && composerHint
    }

    /// Accessibility uses UTF-16 offsets, including for emoji and non-Latin text.
    public static func expectedValue(before: String, inserted: String, selection: NSRange?) -> String? {
        guard let selection, selection.location != NSNotFound,
              selection.location >= 0, selection.length >= 0,
              selection.location <= (before as NSString).length,
              selection.length <= (before as NSString).length - selection.location else { return nil }
        return (before as NSString).replacingCharacters(in: selection, with: inserted)
    }

    private static func normalizedText(_ text: String) -> String {
        // Web editors may expose paragraph terminators and nonbreaking spaces
        // differently through AXValue and AXStringForRange. Do not alter the paste.
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            // Rich editors render paragraph spacing without exposing every blank
            // line through Accessibility. Keep line boundaries and all text;
            // compare paragraph spacing independently of the original paste.
            .replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression)
    }

    public static func comparableText(_ text: String) -> String {
        normalizedText(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func insertionVerified(before: String, after: String, inserted: String, expected: String?) -> Bool {
        let untrimmedBefore = normalizedText(before)
        let before = comparableText(before)
        let after = comparableText(after)
        let inserted = comparableText(inserted)
        // A change in AX formatting alone is not evidence of insertion.
        guard before != after else { return false }
        if let expected, after == comparableText(expected) { return true }
        // Rich editors can expose stale selection offsets. If the prediction does
        // not match, still accept a proven single contiguous replacement.
        // A prompt already elsewhere in the draft does not prove the paste worked.
        guard !inserted.isEmpty else { return false }
        var search = after.startIndex..<after.endIndex
        while let match = after.range(of: inserted, range: search) {
            let prefix = String(after[..<match.lowerBound])
            let suffix = String(after[match.upperBound...])
            for candidate in [untrimmedBefore, before] {
                if candidate.hasPrefix(prefix), candidate.hasSuffix(suffix),
                   prefix.utf16.count + suffix.utf16.count <= candidate.utf16.count { return true }
            }
            guard match.lowerBound < after.endIndex else { break }
            search = after.index(after: match.lowerBound)..<after.endIndex
        }
        return false
    }
}

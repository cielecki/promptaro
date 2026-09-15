import Foundation
import Testing
@testable import PromptCore

@Test func slackMessagesAreExcludedWithoutBlockingAIChats() {
    #expect(ComposerPolicy.excludedBundleIDs.contains("com.tinyspeck.slackmacgap"))
    #expect(ComposerPolicy.excludedBundleIDs.isDisjoint(with: ComposerPolicy.bundleIDs))
    for address in [
        "https://app.slack.com/client/T123/C456",
        "https://workspace.slack.com/messages/general",
        "https://SLACK.COM./messages",
        "http://slack.com/",
    ] {
        #expect(!ComposerPolicy.acceptsWebURL(URL(string: address)!))
    }
    for address in [
        "https://chatgpt.com/", "https://claude.ai/new", "https://gemini.google.com/app",
        "https://chat.example.com/", "https://chat.example.com/slack.com",
        "https://notslack.com/", "https://slack.com.example.com/",
    ] {
        #expect(ComposerPolicy.acceptsWebURL(URL(string: address)!))
    }
    for address in ["slack://open", "file:///tmp/chat.html", "/relative"] {
        #expect(!ComposerPolicy.acceptsWebURL(URL(string: address)!))
    }
}

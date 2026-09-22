import Foundation
import Testing
@testable import PromptCore

@Test func ordinaryWebEditorsAreNotAIChats() {
    for address in [
        "https://app.slack.com/client/T123/C456",
        "https://workspace.slack.com/messages/general",
        "https://SLACK.COM./messages",
        "http://slack.com/",
        "https://discord.com/channels/@me", "https://canary.discord.com/channels/@me",
        "https://discordapp.com/channels/@me", "https://app.todoist.com/app/today",
        "https://todoist.com/app/task/123", "https://chat.example.com/",
        "https://example.com/?next=https://chatgpt.com/",
        "https://chatgpt.com.example.com/", "https://notchatgpt.com/",
        "https://chatgpt.com@discord.com/channels/@me",
    ] {
        #expect(!ComposerPolicy.acceptsWebURL(URL(string: address)!))
    }
    for address in [
        "https://chatgpt.com/", "https://claude.ai/new", "https://gemini.google.com/app",
        "https://CHATGPT.COM./c/example", "https://chat.openai.com/",
        "https://chatgpt.com/c/example?ref=slack.com",
        "https://copilot.microsoft.com/", "https://www.perplexity.ai/",
        "https://perplexity.ai/", "https://grok.com/",
        "https://chat.mistral.ai/", "https://chat.deepseek.com/",
    ] {
        #expect(ComposerPolicy.acceptsWebURL(URL(string: address)!))
    }
    for address in ["slack://open", "file:///tmp/chat.html", "/relative"] {
        #expect(!ComposerPolicy.acceptsWebURL(URL(string: address)!))
    }
}

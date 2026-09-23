import AppKit
import PromptCore
import Testing
@testable import PromptPalette

@Suite(.serialized) @MainActor
struct PaletteOverflowTests {
    private func views(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(views)
    }

    @Test func narrowPaletteKeepsWholeButtonsAndRoutesEveryOverflowPrompt() {
        _ = NSApplication.shared
        let palette = PaletteController()
        let config = Configuration()
        palette.rebuild(config)
        defer { palette.hide() }
        let controls = views(palette.panel.contentView!)
        let buttons = controls.compactMap { $0 as? PromptButton }
        let more = controls.compactMap { $0 as? NSPopUpButton }.first!
        var sent: [Prompt] = []
        palette.onPrompt = { sent.append($0) }
        for width in [180.0, 300.0, 680.0] {
            palette.layout(width: width)
            let visible = buttons.filter { !$0.isHidden }
            #expect(visible.allSatisfy { $0.frame.maxX <= $0.superview!.bounds.width })
            #expect(!more.isHidden)
            #expect(more.frame.maxX <= width - 74)
            let items = Array(more.menu!.items.dropFirst())
            #expect(visible.map(\.title) + items.map(\.title) == config.prompts.map(\.buttonLabel))
            sent = []
            for item in items {
                #expect(NSApp.sendAction(item.action!, to: item.target, from: item))
            }
            #expect(sent == Array(config.prompts.suffix(items.count)))
        }
        palette.status("Example insertion error", busy: false)
        #expect(palette.panel.frame.height == 64)
        palette.status(nil, busy: true)
        #expect(!more.isEnabled)
        #expect(more.menu!.items.dropFirst().allSatisfy { !$0.isEnabled })
        #expect(buttons.allSatisfy { !$0.isEnabled })
        palette.status(nil, busy: false)
        palette.layout(width: 1200)
        #expect(more.isHidden)
        #expect(buttons.allSatisfy { !$0.isHidden && $0.isEnabled })
    }

    @Test func rebuildingClearsStaleOverflowActions() {
        _ = NSApplication.shared
        let palette = PaletteController()
        defer { palette.hide() }
        palette.rebuild(Configuration())
        palette.layout(width: 180)
        let replacement = Prompt(title: "Replacement", text: "New prompt")
        palette.rebuild(Configuration(prompts: [replacement]))
        palette.layout(width: 180)
        let more = views(palette.panel.contentView!).compactMap { $0 as? NSPopUpButton }.first!
        #expect(more.menu!.items.dropFirst().map(\.title) == [replacement.buttonLabel])
        palette.rebuild(Configuration(prompts: []))
        palette.layout(width: 180)
        #expect(more.isHidden)
    }
}

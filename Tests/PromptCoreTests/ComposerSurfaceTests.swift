import Testing
import CoreGraphics
@testable import PromptCore

@Test func openCodeUsesItsCompletePromptForm() {
    // Captured from the installed OpenCode desktop app's Accessibility ancestry.
    let ancestors: [([String], CGRect)] = [
        (["relative", "z-10", "block", "min-h-[60px]"], CGRect(x: 505, y: 721, width: 720, height: 60)),
        (["relative", "min-h-[60px]"], CGRect(x: 505, y: 721, width: 720, height: 60)),
        (["group/prompt-input", "relative", "min-h-[96px]", "w-full"], CGRect(x: 505, y: 721, width: 720, height: 104)),
        (["relative", "size-full", "flex", "flex-col", "gap-0"], CGRect(x: 505, y: 721, width: 720, height: 104))
    ]
    let forms = ancestors.filter { ComposerSurface.isOpenCodePrompt(classes: $0.0) }
    #expect(forms.count == 1)
    #expect(forms.first?.1 == CGRect(x: 505, y: 721, width: 720, height: 104))
    #expect(!ComposerSurface.isOpenCodePrompt(classes: ["terminal", "relative"]))
    #expect(!ComposerSurface.isOpenCodePrompt(classes: ["group/prompt-input-other"]))
}

@Test func claudeCodeAnchorIncludesNoticesAndRepositoryControls() {
    // Input, inner card, complete dock, and outer pane from Claude's AX ancestry.
    let ancestors: [([String], CGRect)] = [
        (["tiptap", "ProseMirror"], CGRect(x: 545, y: 947, width: 472, height: 44)),
        (["epitaxy-prompt", "relative", "isolate", "rounded-card"], CGRect(x: 545, y: 947, width: 510, height: 44)),
        (["group/approval-dock", "w-full", "mx-auto"], CGRect(x: 513, y: 828, width: 570, height: 189)),
        (["relative", "h-full", "min-w-0", "flex", "flex-col"], CGRect(x: 513, y: 95, width: 570, height: 922))
    ]
    let surfaces = ancestors.filter { ComposerSurface.isApprovalDock(classes: $0.0) }
    #expect(surfaces.count == 1)
    let dock = surfaces.first?.1
    #expect(dock?.minY == 828)
    #expect(dock?.maxY == 1017)
    #expect(dock?.contains(CGRect(x: 545, y: 874, width: 510, height: 67)) == true)
    #expect(dock?.contains(CGRect(x: 545, y: 828, width: 510, height: 40)) == true)
}

@Test func identifiesTheActualComposerSurfaceIndependentlyOfContents() {
    // Component classes read from the installed desktop renderer, not invented
    // button labels or rectangle-size estimates.
    #expect(ComposerSurface.isBody(classes: ["_ComposerLayoutBody_kbwao_2", "transition-[border-radius]"]))
    #expect(ComposerSurface.isBody(classes: ["_ComposerLayoutBody_newBuild_7"]))
    #expect(!ComposerSurface.isBody(classes: ["_ComposerLayoutInput_kbwao_2"]))
    #expect(!ComposerSurface.isBody(classes: ["_ComposerLayoutAttachments_kbwao_2"]))
    #expect(!ComposerSurface.isBody(classes: ["_ComposerLayoutFooter_kbwao_2"]))
    #expect(!ComposerSurface.isBody(classes: ["relative", "flex", "w-full"]))
    #expect(!ComposerSurface.isBody(classes: []))
}


@Test func steeringPanelExtendsAnchorWithoutChangingComposerContents() {
    let body = CGRect(x: 294, y: 1003, width: 530, height: 98)
    let steering = CGRect(x: 294, y: 953, width: 530, height: 50)
    #expect(ComposerSurface.anchor(body: body, panels: []).minY == 1003)
    let anchor = ComposerSurface.anchor(body: body, panels: [steering])
    #expect(anchor.minY == 953)
    #expect(anchor.maxY == body.maxY)
    #expect(anchor.width == body.width)
    let withImage = CGRect(x: 294, y: 903, width: 530, height: 198)
    let tallerSteering = CGRect(x: 294, y: 803, width: 530, height: 100)
    #expect(ComposerSurface.anchor(body: withImage, panels: [tallerSteering]).minY == 803)
    #expect(ComposerSurface.anchor(body: withImage, panels: []) == withImage)
}

@Test func recognizesSafariComposerFormWithoutDOMTag() {
    // Safari ChatGPT's actual ancestor: AXGroup / AXLandmarkForm, no DOM tag.
    #expect(ComposerSurface.isForm(subrole: "AXLandmarkForm", tagName: ""))
    #expect(ComposerSurface.isForm(subrole: "", tagName: "FORM"))
    #expect(!ComposerSurface.isForm(subrole: "AXLandmarkMain", tagName: ""))
    #expect(!ComposerSurface.isForm(subrole: "", tagName: "div"))
}

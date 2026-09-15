import CoreGraphics

public enum ComposerSurface {
    /// OpenCode's prompt form contains the editor and attachments. In the current
    /// v2 layout it also contains the footer controls.
    public static func isOpenCodePrompt(classes: [String]) -> Bool {
        classes.contains("group/prompt-input")
    }

    /// Claude Code's dock encloses repository controls, notices, the prompt, and
    /// the footer. Its own frame is the complete surface; stop at this ancestor.
    public static func isApprovalDock(classes: [String]) -> Bool {
        classes.contains("group/approval-dock")
    }

    /// The installed OpenAI renderer exposes this container through AXDOMClassList.
    /// It encloses attachments, the text input, and the footer. Match the component
    /// name without the generated CSS-module suffix.
    public static func isBody(classes: [String]) -> Bool {
        classes.contains { $0.hasPrefix("_ComposerLayoutBody_") }
    }

    /// Safari exposes HTML forms as landmarks without an AXDOMTagName.
    public static func isForm(subrole: String, tagName: String) -> Bool {
        subrole == "AXLandmarkForm" || tagName.lowercased() == "form"
    }

    /// The composer rail is a sibling containing queued/steering messages and status.
    public static func isRail(classes: [String]) -> Bool {
        classes.contains { $0.hasPrefix("_rail_") }
    }

    public static func isTopTray(classes: [String]) -> Bool {
        classes.contains { $0.hasPrefix("_ComposerTopMenuShell_") }
    }

    public static func anchor(body: CGRect, panels: [CGRect]) -> CGRect {
        panels.reduce(body) { $0.union($1) }
    }
}

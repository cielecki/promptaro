import AppKit

enum PromptaroIcon {
    /// The app icon's prompt strip above a chat bubble, simplified for the menu bar.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()

            let strip = NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: 18, height: 6),
                                     xRadius: 2.5, yRadius: 2.5)
            strip.windingRule = .evenOdd
            for x in [2.0, 7.0, 12.0] {
                strip.append(NSBezierPath(roundedRect: NSRect(x: x, y: 2.5, width: 4, height: 3),
                                          xRadius: 0.8, yRadius: 0.8))
            }
            strip.fill()

            let bubble = NSBezierPath(roundedRect: NSRect(x: 1, y: 9, width: 16, height: 6),
                                      xRadius: 2.5, yRadius: 2.5)
            bubble.fill()
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 3, y: 13))
            tail.line(to: NSPoint(x: 3, y: 17))
            tail.line(to: NSPoint(x: 7, y: 14))
            tail.close()
            tail.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppIdentity.name
        return image
    }
}

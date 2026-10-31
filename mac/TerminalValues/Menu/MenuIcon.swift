import AppKit

/// The menu bar icon: TV's mark (a prism, with its beam and three rays),
/// drawn as a template image so macOS tints it for light and dark menu bars.
/// Running and in sync, the prism is filled; stopped, it's an outline; a dot
/// at its corner means something needs you.
enum MenuIcon {
    enum State { case running, stopped }

    static func image(_ state: State, attention: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            NSColor.black.set()
            let beam = NSBezierPath()
            beam.lineWidth = 1.6
            beam.lineCapStyle = .round
            beam.move(to: NSPoint(x: 1.5, y: 8)); beam.line(to: NSPoint(x: 6, y: 8))
            for y in [4.0, 8.0, 12.0] {
                beam.move(to: NSPoint(x: 15.5, y: 8 + (y - 8) * 0.35)); beam.line(to: NSPoint(x: 20.5, y: y))
            }
            beam.stroke()
            let prism = NSBezierPath()
            prism.move(to: NSPoint(x: 6, y: 8)); prism.line(to: NSPoint(x: 15, y: 2.5))
            prism.line(to: NSPoint(x: 15, y: 13.5)); prism.close()
            prism.lineWidth = 1.6
            prism.lineJoinStyle = .round
            if state == .running { prism.fill() }
            prism.stroke()
            if attention {
                NSBezierPath(ovalIn: NSRect(x: 17, y: 0, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

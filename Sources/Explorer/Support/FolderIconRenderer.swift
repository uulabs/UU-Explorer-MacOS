import AppKit
import ExplorerCore

@MainActor
enum FolderIconRenderer {
    private static var cache: [String: NSImage] = [:]

    static func icon(folderColor: ThemeColor, style: FolderIconStyle) -> NSImage {
        let key = "\(folderColor.hex)-\(style.rawValue)"
        if let cached = cache[key] { return cached }

        let side: CGFloat = 128
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        defer { image.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high

        let color = folderColor.nsColor
        let darker = color.blended(withFraction: 0.22, of: .black) ?? color
        let muchDarker = color.blended(withFraction: 0.38, of: .black) ?? color
        let lighter = color.blended(withFraction: 0.28, of: .white) ?? color

        let tabRect = NSRect(x: 14, y: 78, width: 48, height: 30)
        let bodyRect = NSRect(x: 14, y: 24, width: 100, height: 66)
        let tab = NSBezierPath(roundedRect: tabRect, xRadius: 9, yRadius: 9)
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: 14, yRadius: 14)

        switch style {
        case .classic:
            darker.setFill()
            tab.fill()

            let gradient = NSGradient(colors: [lighter, darker]) ?? NSGradient(starting: lighter, ending: darker)!
            gradient.draw(in: body, angle: -90)
            muchDarker.withAlphaComponent(0.5).setStroke()
            tab.lineWidth = 2
            body.lineWidth = 2
            tab.stroke()
            body.stroke()

            NSColor.white.withAlphaComponent(0.22).setStroke()
            let shine = NSBezierPath()
            shine.move(to: NSPoint(x: 24, y: 84))
            shine.line(to: NSPoint(x: 104, y: 84))
            shine.lineWidth = 2
            shine.stroke()

        case .duotone:
            lighter.setFill()
            tab.fill()

            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            color.setFill()
            bodyRect.fill()
            lighter.withAlphaComponent(0.42).setFill()
            NSRect(x: bodyRect.minX, y: bodyRect.midY, width: bodyRect.width, height: bodyRect.height / 2).fill()
            NSGraphicsContext.restoreGraphicsState()

            muchDarker.withAlphaComponent(0.4).setStroke()
            tab.lineWidth = 2
            body.lineWidth = 2
            tab.stroke()
            body.stroke()

        case .outline:
            color.withAlphaComponent(0.10).setFill()
            tab.fill()
            body.fill()

            color.setStroke()
            tab.lineWidth = 7
            body.lineWidth = 7
            tab.lineJoinStyle = .round
            body.lineJoinStyle = .round
            tab.stroke()
            body.stroke()

            color.withAlphaComponent(0.55).setStroke()
            let inner = NSBezierPath(roundedRect: bodyRect.insetBy(dx: 8, dy: 8), xRadius: 9, yRadius: 9)
            inner.lineWidth = 1.5
            inner.stroke()

        case .minimal:
            color.setFill()
            tab.fill()
            body.fill()

        case .glossy:
            NSGradient(colors: [lighter, color])?.draw(in: tab, angle: -90)
            NSGradient(colors: [lighter, color, darker])?.draw(in: body, angle: -90)

            muchDarker.withAlphaComponent(0.5).setStroke()
            tab.lineWidth = 2
            body.lineWidth = 2
            tab.stroke()
            body.stroke()

            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            let reflection = NSBezierPath()
            reflection.move(to: NSPoint(x: bodyRect.minX - 12, y: bodyRect.midY - 18))
            reflection.line(to: NSPoint(x: bodyRect.minX + 24, y: bodyRect.maxY + 12))
            reflection.line(to: NSPoint(x: bodyRect.minX + 54, y: bodyRect.maxY + 12))
            reflection.line(to: NSPoint(x: bodyRect.minX + 18, y: bodyRect.midY - 18))
            reflection.close()
            NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.32),
                NSColor.white.withAlphaComponent(0.025)
            ])?.draw(in: reflection, angle: -38)

            NSColor.white.withAlphaComponent(0.26).setFill()
            NSBezierPath(ovalIn: NSRect(x: 28, y: 68, width: 16, height: 10)).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.white.withAlphaComponent(0.28).setStroke()
            let inner = NSBezierPath(roundedRect: bodyRect.insetBy(dx: 3.5, dy: 3.5), xRadius: 11, yRadius: 11)
            inner.lineWidth = 1
            inner.stroke()

            NSColor.white.withAlphaComponent(0.22).setFill()
            NSRect(x: tabRect.minX + 6, y: tabRect.maxY - 7, width: tabRect.width - 12, height: 3).fill()

        case .stack:
            let backTwo = NSBezierPath(
                roundedRect: NSRect(x: 36, y: 46, width: 84, height: 56),
                xRadius: 12,
                yRadius: 12
            )
            let backOne = NSBezierPath(
                roundedRect: NSRect(x: 28, y: 38, width: 92, height: 64),
                xRadius: 12,
                yRadius: 12
            )

            muchDarker.withAlphaComponent(0.5).setFill()
            backTwo.fill()
            darker.withAlphaComponent(0.92).setFill()
            backOne.fill()
            muchDarker.withAlphaComponent(0.35).setStroke()
            backTwo.lineWidth = 2
            backOne.lineWidth = 2
            backTwo.stroke()
            backOne.stroke()

            NSGradient(colors: [lighter, color])?.draw(in: tab, angle: -90)
            NSGradient(colors: [lighter, color, darker])?.draw(in: body, angle: -90)
            muchDarker.withAlphaComponent(0.5).setStroke()
            tab.lineWidth = 2
            body.lineWidth = 2
            tab.stroke()
            body.stroke()

        case .pixel:
            let pixelFolder = NSBezierPath()
            pixelFolder.move(to: NSPoint(x: 16, y: 32))
            pixelFolder.line(to: NSPoint(x: 112, y: 32))
            pixelFolder.line(to: NSPoint(x: 112, y: 88))
            pixelFolder.line(to: NSPoint(x: 104, y: 88))
            pixelFolder.line(to: NSPoint(x: 104, y: 96))
            pixelFolder.line(to: NSPoint(x: 64, y: 96))
            pixelFolder.line(to: NSPoint(x: 64, y: 104))
            pixelFolder.line(to: NSPoint(x: 24, y: 104))
            pixelFolder.line(to: NSPoint(x: 16, y: 96))
            pixelFolder.close()

            color.setFill()
            pixelFolder.fill()

            NSGraphicsContext.saveGraphicsState()
            pixelFolder.addClip()
            muchDarker.withAlphaComponent(0.32).setFill()
            NSRect(x: 16, y: 32, width: 96, height: 20).fill()
            lighter.withAlphaComponent(0.9).setFill()
            NSRect(x: 24, y: 96, width: 32, height: 8).fill()
            NSGraphicsContext.restoreGraphicsState()

            muchDarker.withAlphaComponent(0.55).setStroke()
            pixelFolder.lineWidth = 2
            pixelFolder.lineJoinStyle = .miter
            pixelFolder.stroke()

        case .bold:
            color.setFill()
            body.fill()
            lighter.setFill()
            tab.fill()

            NSColor.white.withAlphaComponent(0.12).setFill()
            NSRect(x: bodyRect.minX + 10, y: bodyRect.maxY - 14, width: bodyRect.width - 20, height: 5).fill()

            muchDarker.setStroke()
            tab.lineWidth = 8
            body.lineWidth = 8
            tab.lineJoinStyle = .round
            body.lineJoinStyle = .round
            tab.stroke()
            body.stroke()
        }

        cache[key] = image
        return image
    }
}

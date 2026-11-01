import AppKit

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "icon-1024.png"
let dimension = 1024
let side = CGFloat(dimension)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: dimension,
    pixelsHigh: dimension,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create bitmap context")
}

bitmap.size = NSSize(width: side, height: side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let canvas = NSRect(x: 0, y: 0, width: side, height: side)
NSColor.clear.setFill()
canvas.fill()

// Deep blue/violet tile.
let backgroundRect = canvas.insetBy(dx: 64, dy: 64)
let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 215, yRadius: 215)
let backgroundGradient = NSGradient(colors: [
    NSColor(srgbRed: 0.09, green: 0.22, blue: 0.56, alpha: 1),
    NSColor(srgbRed: 0.31, green: 0.10, blue: 0.56, alpha: 1)
])!
backgroundGradient.draw(in: background, angle: -55)

// Soft top sheen.
NSGraphicsContext.saveGraphicsState()
background.addClip()
let gloss = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.16),
    NSColor.white.withAlphaComponent(0.0)
])!
gloss.draw(
    in: NSRect(
        x: backgroundRect.minX,
        y: backgroundRect.midY,
        width: backgroundRect.width,
        height: backgroundRect.height / 2
    ),
    angle: -90
)
NSGraphicsContext.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.14).setStroke()
background.lineWidth = 4
background.stroke()

let darkFolderTop = NSColor(srgbRed: 0.23, green: 0.26, blue: 0.34, alpha: 1.0)
let darkFolderBottom = NSColor(srgbRed: 0.055, green: 0.07, blue: 0.11, alpha: 1.0)
let rimColor = NSColor(srgbRed: 0.56, green: 0.72, blue: 1.0, alpha: 0.58)

// Folder tab.
let tabRect = NSRect(x: 208, y: 604, width: 300, height: 156)
let tab = NSBezierPath(roundedRect: tabRect, xRadius: 52, yRadius: 52)
let tabGradient = NSGradient(colors: [
    NSColor(srgbRed: 0.27, green: 0.31, blue: 0.40, alpha: 1),
    NSColor(srgbRed: 0.14, green: 0.17, blue: 0.24, alpha: 1)
])!
tabGradient.draw(in: tab, angle: -90)
rimColor.setStroke()
tab.lineWidth = 3
tab.stroke()

// Folder body with a soft drop shadow.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
shadow.shadowBlurRadius = 44
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()

let bodyRect = NSRect(x: 198, y: 272, width: 628, height: 444)
let body = NSBezierPath(roundedRect: bodyRect, xRadius: 56, yRadius: 56)
let bodyGradient = NSGradient(colors: [darkFolderTop, darkFolderBottom])!
bodyGradient.draw(in: body, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Dark front with a cold rim light.
rimColor.setStroke()
body.lineWidth = 3
body.stroke()

NSGraphicsContext.saveGraphicsState()
body.addClip()
let innerSheen = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.09),
    NSColor.white.withAlphaComponent(0.0)
])!
innerSheen.draw(
    in: NSRect(x: bodyRect.minX, y: bodyRect.midY, width: bodyRect.width, height: bodyRect.height / 2),
    angle: -90
)
NSGraphicsContext.restoreGraphicsState()

// Glowing file rows inside the dark folder.
let rowColors = [
    NSColor(srgbRed: 0.31, green: 0.64, blue: 1.0, alpha: 1.0),
    NSColor(srgbRed: 0.47, green: 0.47, blue: 1.0, alpha: 1.0),
    NSColor(srgbRed: 0.67, green: 0.41, blue: 1.0, alpha: 1.0)
]
let rowWidths: [CGFloat] = [474, 474, 326]

for index in 0..<3 {
    let y = 558 - CGFloat(index) * 92
    let rowRect = NSRect(x: 274, y: y, width: rowWidths[index], height: 38)
    let row = NSBezierPath(roundedRect: rowRect, xRadius: 19, yRadius: 19)

    NSGraphicsContext.saveGraphicsState()
    let rowShadow = NSShadow()
    rowShadow.shadowColor = rowColors[index].withAlphaComponent(0.5)
    rowShadow.shadowBlurRadius = 22
    rowShadow.set()
    rowColors[index].setFill()
    row.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(ovalIn: NSRect(x: 292, y: y + 11, width: 16, height: 16)).fill()
}

// Top edge highlight on the folder front.
NSColor.white.withAlphaComponent(0.22).setStroke()
let highlight = NSBezierPath()
highlight.move(to: NSPoint(x: 246, y: 710))
highlight.line(to: NSPoint(x: 778, y: 710))
highlight.lineWidth = 2
highlight.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")

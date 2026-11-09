// Draws the DMG window's background at 1x and 2x: a soft arrow from the app to Applications and
// a one-line instruction, in the system font. Usage: swift background.swift <out-dir>
// Positions match dmg/settings.py (window 660×400; icons centred at x 170 and 490, y 190).
import AppKit

let size = NSSize(width: 660, height: 400)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background: near-white, a touch cooler towards the bottom.
    NSGradient(starting: NSColor(srgbRed: 0.995, green: 0.996, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.945, green: 0.953, blue: 0.965, alpha: 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // Arrow between the icons (AppKit's y runs up; the icons sit at y 190 from the top).
    let y = size.height - 190
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 268, y: y))
    arrow.line(to: NSPoint(x: 384, y: y))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 372, y: y + 11))
    head.line(to: NSPoint(x: 386, y: y))
    head.line(to: NSPoint(x: 372, y: y - 11))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    NSColor(srgbRed: 0.62, green: 0.65, blue: 0.70, alpha: 1).setStroke()
    arrow.stroke()
    head.stroke()

    // Instruction, centred near the bottom.
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let text = NSAttributedString(string: "Drag Remembrance into Applications to install", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.42, green: 0.45, blue: 0.50, alpha: 1),
        .paragraphStyle: style,
    ])
    text.draw(in: NSRect(x: 0, y: 62, width: size.width, height: 20))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try! render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))

// Draws the app icon (a red poppy on a dark rounded square) as an .iconset for iconutil.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824/1024 body with ~185 corner radius.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1),
               ending: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1))!.draw(in: shape, angle: -90)

    let c = NSPoint(x: s / 2, y: s / 2)
    let petalR = s * 0.19, offset = s * 0.13
    let red = NSColor(srgbRed: 0.85, green: 0.11, blue: 0.13, alpha: 1)
    let deep = NSColor(srgbRed: 0.62, green: 0.05, blue: 0.08, alpha: 1)
    // Four overlapping petals, darker at their outer edge.
    for (i, angle) in [45.0, 135.0, 225.0, 315.0].enumerated() {
        let a = angle * .pi / 180
        let pc = NSPoint(x: c.x + offset * cos(a), y: c.y + offset * sin(a))
        let petal = NSBezierPath(ovalIn: NSRect(x: pc.x - petalR, y: pc.y - petalR, width: 2 * petalR, height: 2 * petalR))
        NSGradient(starting: i % 2 == 0 ? red : red.blended(withFraction: 0.08, of: .white)!, ending: deep)!
            .draw(in: petal, relativeCenterPosition: NSPoint(x: -cos(a) * 0.5, y: -sin(a) * 0.5))
    }
    // Black centre with a green button.
    let cr = s * 0.085
    NSColor(white: 0.04, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - cr, y: c.y - cr, width: 2 * cr, height: 2 * cr)).fill()
    let gr = s * 0.03
    NSColor(srgbRed: 0.18, green: 0.32, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - gr, y: c.y - gr, width: 2 * gr, height: 2 * gr)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! draw(px: size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! draw(px: size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

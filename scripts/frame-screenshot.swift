// Turns a 2x window snapshot into a README screenshot: rounded window corners and a soft drop
// shadow on a transparent background, kept at 2x (show it at half width in Markdown).
// Usage: swift scripts/frame-screenshot.swift <in.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]),
      let src = image.representations.first else { fatalError("usage: frame-screenshot <in.png> <out.png>") }

let w = CGFloat(src.pixelsWide), h = CGFloat(src.pixelsHigh)
let radius: CGFloat = 32      // macOS 26 window corners (16 pt) at 2x
let pad: CGFloat = 80         // room for the shadow
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w + 2 * pad), pixelsHigh: Int(h + 2 * pad),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let frame = NSRect(x: pad, y: pad, width: w, height: h)
let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)

// Shadow, then the window clipped to its corners, then a hairline border like the real window.
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 50
shadow.shadowOffset = NSSize(width: 0, height: -20)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()
image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

NSColor.black.withAlphaComponent(0.15).setStroke()
let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
border.lineWidth = 1
border.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))

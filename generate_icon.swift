#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Brand colour
let brandBlue = NSColor(red: 0x00/255.0, green: 0x40/255.0, blue: 0x80/255.0, alpha: 1.0)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let cx = s / 2
    let cy = s / 2

    // Background — rounded rect with brand colour
    let bgRect = NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.18, yRadius: s * 0.18)
    brandBlue.setFill()
    bgPath.fill()

    // Subtle radial gradient for depth
    let gradSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        NSColor(white: 1.0, alpha: 0.10).cgColor,
        NSColor(white: 0.0, alpha: 0.12).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: gradSpace, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addPath(bgPath.cgPath)
        ctx.clip()
        ctx.drawRadialGradient(gradient,
            startCenter: CGPoint(x: cx, y: cy + s * 0.14),
            startRadius: 0,
            endCenter: CGPoint(x: cx, y: cy),
            endRadius: s * 0.55,
            options: [])
        ctx.restoreGState()
    }

    // ── Command glyph (⌘) ──
    // Render the Unicode glyph from the system font: Apple's outlines are
    // already correct, no risk of open paths or mis-aligned corners.
    ctx.saveGState()
    ctx.addPath(bgPath.cgPath)
    ctx.clip()

    let glyphFont = NSFont.systemFont(ofSize: s * 0.62, weight: .semibold)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.04

    let attrs: [NSAttributedString.Key: Any] = [
        .font: glyphFont,
        .foregroundColor: NSColor(white: 1.0, alpha: 0.97),
        .shadow: shadow,
    ]
    let glyph = NSAttributedString(string: "\u{2318}", attributes: attrs)
    let gSize = glyph.size()
    // Optical centring: the ⌘ glyph sits a touch above the font box midline,
    // so nudge down slightly to look balanced inside the squircle.
    let drawPoint = NSPoint(x: cx - gSize.width / 2,
                            y: cy - gSize.height / 2 - s * 0.012)
    glyph.draw(at: drawPoint)

    ctx.restoreGState()

    image.unlockFocus()
    return image
}

// NSBezierPath -> CGPath
extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        defer { points.deallocate() }
        for i in 0..<elementCount {
            let element = self.element(at: i, associatedPoints: points)
            switch element {
            case .moveTo:    path.move(to: points[0])
            case .lineTo:    path.addLine(to: points[0])
            case .curveTo:   path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

// Generate all icon sizes
let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let scriptDir = CommandLine.arguments[0].components(separatedBy: "/").dropLast().joined(separator: "/")
let iconsetDir = (scriptDir.isEmpty ? "." : scriptDir) + "/Resources/ShortcutHUD.iconset"

let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { continue }
    let path = iconsetDir + "/" + name
    try! png.write(to: URL(fileURLWithPath: path))
    print("  \(name) (\(size)x\(size))")
}

// Generate .icns
let icnsPath = (scriptDir.isEmpty ? "." : scriptDir) + "/Resources/AppIcon.icns"
let result = Process()
result.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
result.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try! result.run()
result.waitUntilExit()
print("  AppIcon.icns")
print("Done.")

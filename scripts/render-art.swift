#!/usr/bin/env swift
// Renders the app icon set and the DMG background.
//   swift scripts/render-art.swift icon <AppIcon.appiconset>
//   swift scripts/render-art.swift dmg <out-dir>
import AppKit

func png(_ size: CGSize, scale: CGFloat = 1, _ draw: (CGContext, CGSize) -> Void) -> Data {
    let w = Int(size.width * scale), h = Int(size.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext, size)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

func drawCentered(_ image: NSImage, in rect: CGRect) {
    let s = image.size
    let r = CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height)
    image.draw(in: r)
}

/// Rounded "glass" slot: translucent fill, highlight rim, inner shadow.
func slot(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, filled: Bool = false) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(filled ? color(0xFFFFFF, 0.32) : color(0x000000, 0.18))
    ctx.fillPath()
    ctx.addPath(path)
    ctx.clip()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.height * 0.04), blur: rect.height * 0.12,
                  color: color(0x000000, 0.45))
    ctx.addRect(rect.insetBy(dx: -40, dy: -40))
    ctx.addPath(path)
    ctx.setFillColor(color(0x000000, 0.4))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(color(0xFFFFFF, 0.35))
    ctx.setLineWidth(max(1, rect.width * 0.02))
    ctx.strokePath()
}

func renderIcon(_ px: CGFloat) -> Data {
    png(CGSize(width: px, height: px)) { ctx, size in
        let s = size.width
        // macOS icon grid: 824/1024 body with shadow
        let body = CGRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
        let shape = CGPath(roundedRect: body, cornerWidth: s * 0.185, cornerHeight: s * 0.185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0, 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(color(0x3B2A1E))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        gradient(ctx, [color(0x8B5E3C), color(0x5B3A24)], from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.minY))
        // pixel planks
        let cell = body.width / 16
        for y in 0..<16 {
            for x in 0..<16 {
                var h = UInt32(truncatingIfNeeded: (x + (y / 4) * 5) &* 374_761_393 &+ y &* 668_265_263)
                h = (h ^ (h >> 13)) &* 1_274_126_177
                let a = CGFloat(h & 0xFF) / 255 * 0.14
                ctx.setFillColor(color(h & 0x100 == 0 ? 0xFFFFFF : 0x000000, a))
                ctx.fill(CGRect(x: body.minX + CGFloat(x) * cell, y: body.minY + CGFloat(y) * cell, width: cell, height: cell))
            }
            if y % 4 == 0 {
                ctx.setFillColor(color(0x000000, 0.22))
                ctx.fill(CGRect(x: body.minX, y: body.minY + CGFloat(y) * cell, width: body.width, height: max(1, cell * 0.18)))
            }
        }
        // glass sheen
        gradient(ctx, [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0.0)],
                 from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.midY))
        ctx.restoreGState()

        // 3x3 crafting grid with the result in the middle
        let grid = body.insetBy(dx: body.width * 0.14, dy: body.width * 0.14)
        let gap = grid.width * 0.06
        let cw = (grid.width - gap * 2) / 3
        for row in 0..<3 {
            for col in 0..<3 {
                let r = CGRect(x: grid.minX + CGFloat(col) * (cw + gap), y: grid.minY + CGFloat(row) * (cw + gap), width: cw, height: cw)
                let center = row == 1 && col == 1
                slot(ctx, r, radius: cw * 0.24, filled: center)
            }
        }
        let center = CGRect(x: grid.minX + cw + gap, y: grid.minY + cw + gap, width: cw, height: cw)
        if s >= 32 {
            drawCentered(symbol("signature", pointSize: cw * 0.62, weight: .bold, color: .white), in: center)
            let seal = symbol("checkmark.seal.fill", pointSize: cw * 0.42, weight: .bold, color: NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1))
            drawCentered(seal, in: CGRect(x: center.maxX - cw * 0.12, y: center.minY - cw * 0.05, width: 0, height: 0))
        }
    }
}

func renderDMG(scale: CGFloat) -> Data {
    let size = CGSize(width: 660, height: 400)
    return png(size, scale: scale) { ctx, size in
        gradient(ctx, [color(0xF4E6D4), color(0xE4DDF3), color(0xD3E6F2)],
                 from: CGPoint(x: 0, y: size.height), to: CGPoint(x: size.width, y: 0))
        let cell: CGFloat = 12
        for y in 0..<Int(size.height / cell) + 1 {
            for x in 0..<Int(size.width / cell) + 1 {
                var h = UInt32(truncatingIfNeeded: (x + (y / 4) * 7) &* 374_761_393 &+ y &* 668_265_263)
                h = (h ^ (h >> 13)) &* 1_274_126_177
                ctx.setFillColor(color(0x8B5E3C, 0.02 + CGFloat(h & 0xFF) / 255 * 0.05))
                ctx.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
            }
        }
        // icon slots at (165, 200) and (495, 200) in Finder (top-left) coordinates
        for x in [165.0, 495.0] {
            slot(ctx, CGRect(x: x - 80, y: size.height - 200 - 80, width: 160, height: 160), radius: 30, filled: true)
        }
        // dashed arrow
        ctx.setStrokeColor(color(0x5B3A24, 0.55))
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [2, 12])
        ctx.move(to: CGPoint(x: 270, y: size.height - 200))
        ctx.addLine(to: CGPoint(x: 380, y: size.height - 200))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.move(to: CGPoint(x: 372, y: size.height - 188))
        ctx.addLine(to: CGPoint(x: 388, y: size.height - 200))
        ctx.addLine(to: CGPoint(x: 372, y: size.height - 212))
        ctx.strokePath()

        let title = NSAttributedString(string: "Drag AppleSign to Applications", attributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor(white: 0.15, alpha: 0.85),
        ])
        let t = title.size()
        title.draw(at: CGPoint(x: (size.width - t.width) / 2, y: size.height - 70))
        let sub = NSAttributedString(string: "Then drop any .ipa on its crafting table to re-sign it", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(white: 0.2, alpha: 0.6),
        ])
        let u = sub.size()
        sub.draw(at: CGPoint(x: (size.width - u.width) / 2, y: 48))
    }
}

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: render-art.swift icon|dmg <dir>")
    exit(1)
}
let out = URL(filePath: args[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
switch args[1] {
case "icon":
    var images: [[String: String]] = []
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
            try renderIcon(CGFloat(pt * scale)).write(to: out.appending(path: name))
            images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
        }
    }
    let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        .write(to: out.appending(path: "Contents.json"))
case "dmg":
    try renderDMG(scale: 1).write(to: out.appending(path: "dmg-background.png"))
    try renderDMG(scale: 2).write(to: out.appending(path: "dmg-background@2x.png"))
default:
    print("unknown target \(args[1])")
    exit(1)
}

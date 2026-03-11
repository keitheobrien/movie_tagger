#!/usr/bin/swift

import AppKit
import CoreGraphics

/// Generate the MovieTagger app icon — dark cinematic clapperboard with blue star accents.
func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let sc = s / 512.0

    // ── Background: dark gradient rounded rect ──
    let cr = 100.0 * sc
    let inset = rect.insetBy(dx: 2 * sc, dy: 2 * sc)
    let bgPath = CGPath(roundedRect: inset, cornerWidth: cr, cornerHeight: cr, transform: nil)

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Very dark gradient — charcoal to near-black
    let bgColors = [
        CGColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1.0),
        CGColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1.0)
    ]
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: bgColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGrad,
                           start: CGPoint(x: s / 2, y: s),
                           end: CGPoint(x: s / 2, y: 0), options: [])
    ctx.restoreGState()

    // ── Subtle vignette (radial darkening at edges) ──
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let vigColors = [
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.0),
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
    ]
    let vigGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: vigColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(vigGrad,
                           startCenter: CGPoint(x: s * 0.5, y: s * 0.5), startRadius: s * 0.2,
                           endCenter: CGPoint(x: s * 0.5, y: s * 0.5), endRadius: s * 0.55,
                           options: .drawsAfterEndLocation)
    ctx.restoreGState()

    // ═══════════════════════════════════════════════════
    // CLAPPERBOARD — centered, dark slate style
    // ═══════════════════════════════════════════════════

    let boardW = 310.0 * sc
    let boardH = 210.0 * sc
    let boardX = (s - boardW) / 2
    let boardY = 80.0 * sc  // bottom of board (CoreGraphics y-up)

    // ── Board body (dark slate) ──
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * sc), blur: 20 * sc,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    let boardRect = CGRect(x: boardX, y: boardY, width: boardW, height: boardH)
    let boardPath = CGPath(roundedRect: boardRect, cornerWidth: 14 * sc, cornerHeight: 14 * sc, transform: nil)
    // Dark slate gradient
    ctx.addPath(boardPath)
    ctx.clip()
    let slateColors = [
        CGColor(red: 0.22, green: 0.23, blue: 0.28, alpha: 1.0),
        CGColor(red: 0.14, green: 0.15, blue: 0.19, alpha: 1.0)
    ]
    let slateGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: slateColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(slateGrad,
                           start: CGPoint(x: boardX, y: boardY + boardH),
                           end: CGPoint(x: boardX, y: boardY), options: [])
    ctx.restoreGState()

    // ── Board border/edge highlight ──
    ctx.saveGState()
    ctx.addPath(boardPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.setLineWidth(1.5 * sc)
    ctx.strokePath()
    ctx.restoreGState()

    // ── Text lines on the slate (info rows) ──
    ctx.saveGState()
    ctx.setLineCap(.round)
    for i in 0..<4 {
        let lineY = boardY + 30.0 * sc + CGFloat(i) * 40.0 * sc
        let lineXStart = boardX + 28.0 * sc
        let labelWidth: CGFloat = [90, 70, 100, 60][i] * sc
        let valueWidth: CGFloat = [160, 140, 120, 100][i] * sc

        // Label line (dimmer, shorter)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
        ctx.setLineWidth(3.5 * sc)
        ctx.move(to: CGPoint(x: lineXStart, y: lineY))
        ctx.addLine(to: CGPoint(x: lineXStart + labelWidth, y: lineY))
        ctx.strokePath()

        // Value line (brighter, longer)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
        ctx.setLineWidth(3.5 * sc)
        ctx.move(to: CGPoint(x: lineXStart + labelWidth + 14 * sc, y: lineY))
        ctx.addLine(to: CGPoint(x: lineXStart + labelWidth + 14 * sc + valueWidth, y: lineY))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // ═══════════════════════════════════════════════════
    // CLAPPER (top hinged part) — with diagonal stripes
    // ═══════════════════════════════════════════════════

    let clapH = 60.0 * sc
    let clapY = boardY + boardH  // sits on top of board
    let clapRect = CGRect(x: boardX, y: clapY, width: boardW, height: clapH)

    // Slightly angled — rotate a few degrees around the left hinge point
    let hingeX = boardX + 12.0 * sc
    let hingeY = clapY
    let angle: CGFloat = 6.0 * .pi / 180.0  // 6 degrees open

    ctx.saveGState()
    ctx.translateBy(x: hingeX, y: hingeY)
    ctx.rotate(by: angle)
    ctx.translateBy(x: -hingeX, y: -hingeY)

    // Clapper shadow
    ctx.setShadow(offset: CGSize(width: 0, height: 4 * sc), blur: 10 * sc,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))

    let clapPath = CGPath(roundedRect: clapRect, cornerWidth: 8 * sc, cornerHeight: 8 * sc, transform: nil)
    ctx.addPath(clapPath)
    ctx.clip()

    // Base color — dark
    ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0))
    ctx.fill(clapRect)

    // Diagonal stripes
    let stripeW = 28.0 * sc
    let gapW = 32.0 * sc
    var sx = boardX - clapH
    while sx < boardX + boardW + clapH {
        ctx.move(to: CGPoint(x: sx, y: clapY))
        ctx.addLine(to: CGPoint(x: sx + stripeW, y: clapY))
        ctx.addLine(to: CGPoint(x: sx + stripeW + clapH * 0.9, y: clapY + clapH))
        ctx.addLine(to: CGPoint(x: sx + clapH * 0.9, y: clapY + clapH))
        ctx.closePath()
        sx += stripeW + gapW
    }
    ctx.setFillColor(CGColor(red: 0.92, green: 0.92, blue: 0.95, alpha: 1.0))
    ctx.fillPath()

    ctx.restoreGState()

    // ── Hinge circle ──
    ctx.saveGState()
    let hingeCR = 10.0 * sc
    ctx.setShadow(offset: .zero, blur: 4 * sc,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
    ctx.setFillColor(CGColor(red: 0.35, green: 0.36, blue: 0.40, alpha: 1.0))
    ctx.addArc(center: CGPoint(x: hingeX, y: hingeY), radius: hingeCR,
               startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()
    // Inner circle
    ctx.setFillColor(CGColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1.0))
    ctx.addArc(center: CGPoint(x: hingeX, y: hingeY), radius: hingeCR * 0.55,
               startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()
    ctx.restoreGState()

    // ═══════════════════════════════════════════════════
    // STAR ACCENTS — blue/cyan sparkles
    // ═══════════════════════════════════════════════════

    func drawStar(cx: CGFloat, cy: CGFloat, outerR: CGFloat, innerR: CGFloat, points: Int, color: CGColor) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: outerR * 1.5, color: color)

        let path = CGMutablePath()
        for i in 0..<(points * 2) {
            let r = (i % 2 == 0) ? outerR : innerR
            let a = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let px = cx + r * cos(a)
            let py = cy + r * sin(a)
            if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
            else { path.addLine(to: CGPoint(x: px, y: py)) }
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()

        // Bright center
        ctx.setShadow(offset: .zero, blur: 0)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: innerR * 0.4,
                   startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Cross-shaped sparkle (4-pointed)
    func drawSparkle(cx: CGFloat, cy: CGFloat, length: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: length * 0.8, color: color)

        let path = CGMutablePath()
        let w = length * 0.15
        // Vertical spike
        path.move(to: CGPoint(x: cx, y: cy + length))
        path.addLine(to: CGPoint(x: cx + w, y: cy))
        path.addLine(to: CGPoint(x: cx, y: cy - length))
        path.addLine(to: CGPoint(x: cx - w, y: cy))
        path.closeSubpath()
        // Horizontal spike
        path.move(to: CGPoint(x: cx + length, y: cy))
        path.addLine(to: CGPoint(x: cx, y: cy + w))
        path.addLine(to: CGPoint(x: cx - length, y: cy))
        path.addLine(to: CGPoint(x: cx, y: cy - w))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()

        ctx.restoreGState()
    }

    let starBlue = CGColor(red: 0.30, green: 0.60, blue: 1.0, alpha: 1.0)
    let starCyan = CGColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 0.8)
    let starWhite = CGColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 0.7)

    // Large star — upper right
    drawStar(cx: 395 * sc, cy: 410 * sc, outerR: 22 * sc, innerR: 9 * sc, points: 4, color: starBlue)

    // Medium sparkle — upper left area
    drawSparkle(cx: 120 * sc, cy: 430 * sc, length: 16 * sc, color: starCyan)

    // Small sparkle — right of board
    drawSparkle(cx: 430 * sc, cy: 300 * sc, length: 10 * sc, color: starWhite)

    // Tiny star — lower left
    drawStar(cx: 90 * sc, cy: 130 * sc, outerR: 8 * sc, innerR: 3 * sc, points: 4, color: starCyan)

    // Medium star — above clapper, left-center
    drawStar(cx: 210 * sc, cy: 450 * sc, outerR: 12 * sc, innerR: 5 * sc, points: 4, color: starWhite)

    // Tiny sparkle dots
    func drawDot(cx: CGFloat, cy: CGFloat, r: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * 3, color: color)
        ctx.setFillColor(color)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                   startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.fillPath()
        ctx.restoreGState()
    }

    drawDot(cx: 350 * sc, cy: 460 * sc, r: 3 * sc, color: starBlue)
    drawDot(cx: 450 * sc, cy: 200 * sc, r: 2.5 * sc, color: starCyan)
    drawDot(cx: 70 * sc, cy: 320 * sc, r: 2 * sc, color: starWhite)
    drawDot(cx: 160 * sc, cy: 70 * sc, r: 2 * sc, color: starBlue)
    drawDot(cx: 300 * sc, cy: 60 * sc, r: 1.5 * sc, color: starCyan)
    drawDot(cx: 460 * sc, cy: 420 * sc, r: 2 * sc, color: starWhite)

    img.unlockFocus()
    return img
}

func savePNG(_ image: NSImage, to path: String, size: Int) {
    let targetSize = NSSize(width: size, height: size)
    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmapRep.size = targetSize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
    image.draw(in: NSRect(origin: .zero, size: targetSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    let pngData = bitmapRep.representation(using: .png, properties: [:])!
    try! pngData.write(to: URL(fileURLWithPath: path))
}

// ── Generate all required sizes ──

let iconsetPath = "MovieTagger/Assets.xcassets/AppIcon.appiconset"

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for entry in sizes {
    let path = "\(iconsetPath)/\(entry.name)"
    let icon = generateIcon(size: entry.pixels)
    savePNG(icon, to: path, size: entry.pixels)
    print("Generated \(entry.name) (\(entry.pixels)x\(entry.pixels))")
}

print("Done! All icons generated.")

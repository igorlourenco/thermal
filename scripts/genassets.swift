#!/usr/bin/env swift
// =============================================================================
// genassets.swift — generate every installer asset from installer.md, in code.
//
//   swift scripts/genassets.swift
//
// Produces:
//   Resources/Thermal.icns        app icon (spec §1)
//   Resources/VolumeIcon.icns     silver drive volume icon (spec §1)
//   Resources/dmg/background.tiff DMG window art, @1x+@2x reps (spec §2)
//   dist/asset-preview.png        contact sheet for eyeballing the sizes
//
// Everything is drawn with CoreGraphics so a colour tweak in the spec is a
// one-line change here, not a re-export from a design tool. Values are the
// ones installer.md marks final; `installer_prototype/Thermal - Installer
// .dc.html` is the visual reference they were checked against.
// =============================================================================

import AppKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

// MARK: - Colour: OKLCh -> sRGB
// The spec gives chip/bloom colours in oklch(); convert exactly rather than
// trusting the approximate hex the spec lists alongside.

func oklchColor(_ L: Double, _ C: Double, _ hDeg: Double, _ alpha: Double = 1) -> CGColor {
    let h = hDeg * .pi / 180
    let a = C * cos(h), b = C * sin(h)
    let l_ = L + 0.3963377774 * a + 0.2158037573 * b
    let m_ = L - 0.1055613458 * a - 0.0638541728 * b
    let s_ = L - 0.0894841775 * a - 1.2914855480 * b
    let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
    var rgb = [
        +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    ]
    rgb = rgb.map { c -> Double in
        let cc = min(max(c, 0), 1)
        return cc <= 0.0031308 ? 12.92 * cc : 1.055 * pow(cc, 1 / 2.4) - 0.055
    }
    return CGColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: alpha)
}

func hex(_ v: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255, alpha: alpha)
}

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Drawing helpers

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// macOS continuous-corner squircle, rendered by CoreAnimation so the curve is
// Apple's own, then used as a clip mask.
func squircleMask(_ size: CGSize, radius: CGFloat) -> CGImage {
    let layer = CALayer()
    layer.frame = CGRect(origin: .zero, size: size)
    layer.backgroundColor = CGColor(gray: 1, alpha: 1)
    layer.cornerRadius = min(radius, min(size.width, size.height) / 2)
    layer.cornerCurve = .continuous
    layer.masksToBounds = true
    let ctx = makeContext(Int(size.width.rounded()), Int(size.height.rounded()))
    layer.render(in: ctx)
    return ctx.makeImage()!
}

// CSS-style linear gradient: 0deg points up, angle grows clockwise.
func fillLinearGradient(_ ctx: CGContext, rect: CGRect, angleDeg: Double,
                        stops: [(Double, CGColor)]) {
    let rad = angleDeg * .pi / 180
    let dir = CGVector(dx: sin(rad), dy: cos(rad)) // CG y-up == CSS "up"
    let len = abs(rect.width * dir.dx) + abs(rect.height * dir.dy)
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let start = CGPoint(x: c.x - dir.dx * len / 2, y: c.y - dir.dy * len / 2)
    let end = CGPoint(x: c.x + dir.dx * len / 2, y: c.y + dir.dy * len / 2)
    let grad = CGGradient(colorsSpace: srgb,
                          colors: stops.map(\.1) as CFArray,
                          locations: stops.map { CGFloat($0.0) })!
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawLinearGradient(grad, start: start, end: end,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// Soft elliptical glow: a radial gradient with a gaussian-ish falloff, which
// is what the prototype's radial-gradient + blur() composite resolves to.
func drawBloom(_ ctx: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat, color: CGColor) {
    let comps = color.components!
    let a = color.alpha
    func at(_ f: CGFloat) -> CGColor {
        CGColor(srgbRed: comps[0], green: comps[1], blue: comps[2], alpha: a * f)
    }
    // CSS radial-gradient(circle, c, transparent 70%) + blur: alpha dies ~3/4
    // of the way out, blur rounds the shoulder.
    let stops: [(Double, CGColor)] = [(0, at(1)), (0.3, at(0.75)), (0.55, at(0.35)),
                                      (0.75, at(0.08)), (0.85, at(0)), (1, at(0))]
    let grad = CGGradient(colorsSpace: srgb, colors: stops.map(\.1) as CFArray,
                          locations: stops.map { CGFloat($0.0) })!
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: 1, y: ry / rx)
    ctx.drawRadialGradient(grad, startCenter: .zero, startRadius: 0,
                           endCenter: .zero, endRadius: rx, options: [])
    ctx.restoreGState()
}

// MARK: - The chip (shared mark: app icon, volume icon)

let chipTop = oklchColor(0.82, 0.13, 75)      // ≈ #F5BB6A
let chipBottom = oklchColor(0.62, 0.14, 45)   // ≈ #C4763A
let glowColor = oklchColor(0.78, 0.13, 75)

/// Draws the warm chip. `glow`/`highlight` are dropped at small sizes per spec.
func drawChip(_ ctx: CGContext, rect: CGRect, glow: Bool, glowAlpha: Double, highlight: Bool) {
    if glow {
        drawBloom(ctx, center: CGPoint(x: rect.midX, y: rect.midY),
                  rx: rect.width * 1.15, ry: rect.width * 1.15,
                  color: glowColor.copy(alpha: glowAlpha)!)
    }
    let mask = squircleMask(rect.size, radius: rect.width * 0.28)
    ctx.saveGState()
    ctx.clip(to: rect, mask: mask)
    fillLinearGradient(ctx, rect: rect, angleDeg: 180,
                       stops: [(0, chipTop), (1, chipBottom)])
    if highlight {
        let px = max(1, rect.width * 0.022)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.4))
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - px, width: rect.width, height: px))
    }
    ctx.restoreGState()
}

// MARK: - App icon (spec §1)

/// Renders the app icon at `px`. `simplified` = 16/32pt variants: no bloom,
/// no highlights, chip grows a few percent so it still reads.
func renderAppIcon(px: Int, simplified: Bool) -> CGImage {
    let S = CGFloat(px)
    // Apple icon grid: the tile occupies 824/1024 of the canvas, soft shadow.
    let tileSide = (S * 824 / 1024).rounded()
    let tileRect = CGRect(x: (S - tileSide) / 2, y: (S - tileSide) / 2,
                          width: tileSide, height: tileSide)

    // Compose the tile face at exact size, then stamp it with a shadow.
    let tctx = makeContext(Int(tileSide), Int(tileSide))
    let tRect = CGRect(x: 0, y: 0, width: tileSide, height: tileSide)
    let mask = squircleMask(tRect.size, radius: tileSide * 0.2237) // macOS ratio
    tctx.clip(to: tRect, mask: mask)
    fillLinearGradient(tctx, rect: tRect, angleDeg: 165,
                       stops: [(0, hex(0x2A2226)), (0.6, hex(0x171418)), (1, hex(0x121013))])
    if !simplified {
        // Prototype geometry at 112px tile: 130x100 ellipse, top -24 / left -14.
        drawBloom(tctx,
                  center: CGPoint(x: tileSide * (51.0 / 112.0),
                                  y: tileSide - tileSide * (26.0 / 112.0)),
                  rx: tileSide * (65.0 / 112.0), ry: tileSide * (50.0 / 112.0),
                  color: glowColor.copy(alpha: 0.5)!)
        // Tile top inner highlight (prototype: inset 0 1px rgba(255,255,255,0.14)).
        let px1 = max(1, tileSide * 0.009)
        tctx.setFillColor(CGColor(gray: 1, alpha: 0.14))
        tctx.fill(CGRect(x: 0, y: tileSide - px1, width: tileSide, height: px1))
    }
    let chipSide = (tileSide * (simplified ? 0.47 : 0.41)).rounded()
    drawChip(tctx,
             rect: CGRect(x: (tileSide - chipSide) / 2, y: (tileSide - chipSide) / 2,
                          width: chipSide, height: chipSide),
             glow: !simplified, glowAlpha: 0.55, highlight: !simplified)
    let tile = tctx.makeImage()!

    let ctx = makeContext(px, px)
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.01), blur: S * 0.02,
                  color: CGColor(gray: 0, alpha: 0.3))
    ctx.draw(tile, in: tileRect)
    return ctx.makeImage()!
}

// MARK: - Volume icon (spec §1)

/// Silver drive body with the chip inset top-left. Prototype geometry: body
/// 96x70, radius 9, chip 26 at (12, 14), slot line inset 12 / bottom 12.
func renderVolumeIcon(px: Int, simplified: Bool) -> CGImage {
    let S = CGFloat(px)
    let bodyW = (S * 824 / 1024).rounded()
    let bodyH = (bodyW * 70 / 96).rounded()
    let bodyRect = CGRect(x: (S - bodyW) / 2, y: (S - bodyH) / 2, width: bodyW, height: bodyH)

    let bctx = makeContext(Int(bodyW), Int(bodyH))
    let bRect = CGRect(x: 0, y: 0, width: bodyW, height: bodyH)
    let mask = squircleMask(bRect.size, radius: bodyW * 0.09)
    bctx.clip(to: bRect, mask: mask)
    fillLinearGradient(bctx, rect: bRect, angleDeg: 170,
                       stops: [(0, hex(0xE9E7E3)), (0.6, hex(0xC6C3BD)), (1, hex(0xB2AEA7))])
    if !simplified {
        let px1 = max(1, bodyW * 0.01)
        bctx.setFillColor(CGColor(gray: 1, alpha: 0.7))
        bctx.fill(CGRect(x: 0, y: bodyH - px1, width: bodyW, height: px1))
        // Slot line along the bottom.
        let inset = bodyW * (12.0 / 96.0)
        let slotH = max(1, bodyH * (2.0 / 70.0))
        bctx.setFillColor(hex(0x141418, 0.18))
        let slot = CGPath(roundedRect: CGRect(x: inset, y: bodyH * (12.0 / 70.0),
                                              width: bodyW - 2 * inset, height: slotH),
                          cornerWidth: slotH / 2, cornerHeight: slotH / 2, transform: nil)
        bctx.addPath(slot)
        bctx.fillPath()
    }
    let chipSide = (bodyW * (simplified ? 0.31 : 0.27)).rounded()
    let chipRect = CGRect(x: bodyW * (12.0 / 96.0),
                          y: bodyH - bodyH * (14.0 / 70.0) - chipSide,
                          width: chipSide, height: chipSide)
    drawChip(bctx, rect: chipRect, glow: !simplified, glowAlpha: 0.45, highlight: false)
    let body = bctx.makeImage()!

    let ctx = makeContext(px, px)
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.01), blur: S * 0.02,
                  color: CGColor(gray: 0, alpha: 0.3))
    ctx.draw(body, in: bodyRect)
    return ctx.makeImage()!
}

// MARK: - DMG background (spec §2)

func drawText(_ ctx: CGContext, _ string: String, font: NSFont, color: CGColor,
              tracking: CGFloat, centerX: CGFloat, topY: CGFloat, canvasH: CGFloat) -> CGFloat {
    let attr = NSAttributedString(string: string, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: tracking,
    ])
    let line = CTLineCreateWithAttributedString(attr)
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    ctx.textPosition = CGPoint(x: centerX - width / 2, y: canvasH - topY - ascent)
    CTLineDraw(line, ctx)
    return ascent + descent // drawn text height, for stacking
}

/// The 660x420 window art. Icons and their labels are Finder's; their space
/// stays empty. `scale` 1 or 2.
func renderDMGBackground(scale: CGFloat) -> CGImage {
    let W: CGFloat = 660, H: CGFloat = 420
    let ctx = makeContext(Int(W * scale), Int(H * scale))
    ctx.scaleBy(x: scale, y: scale)
    let full = CGRect(x: 0, y: 0, width: W, height: H)
    fillLinearGradient(ctx, rect: full, angleDeg: 180,
                       stops: [(0, hex(0x1A1719)), (0.58, hex(0x111114)), (1, hex(0x0E0E11))])
    // warm bloom: 560x420 at top -150 / left -70 (CSS box, so centre = box centre)
    drawBloom(ctx, center: CGPoint(x: -70 + 280, y: H - (-150 + 210)),
              rx: 280 + 50, ry: 210 + 50, color: glowColor.copy(alpha: 0.26)!)
    // cool bloom: 500x380 at bottom -170 / right -90
    drawBloom(ctx, center: CGPoint(x: W + 90 - 250, y: -170 + 190),
              rx: 250 + 52, ry: 190 + 52, color: oklchColor(0.70, 0.06, 235, 0.16))

    var y: CGFloat = 40
    y += drawText(ctx, "Thermal",
                  font: .systemFont(ofSize: 27, weight: .thin), // CSS weight 200
                  color: hex(0xFBF7F2), tracking: 27 * -0.02,
                  centerX: W / 2, topY: y, canvasH: H)
    y += 9
    _ = drawText(ctx, "Drag it to Applications",
                 font: .systemFont(ofSize: 13), color: CGColor(gray: 1, alpha: 0.5),
                 tracking: 0, centerX: W / 2, topY: y, canvasH: H)

    // Arrow between the icons, at the icon row's vertical centre (y 206 top-down).
    let midY = H - 206
    let ruleW: CGFloat = 56
    let x0 = W / 2 - ruleW / 2
    ctx.setLineWidth(1.6)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.42))
    ctx.setLineDash(phase: 0, lengths: [1, 5])
    ctx.move(to: CGPoint(x: x0, y: midY))
    ctx.addLine(to: CGPoint(x: x0 + ruleW - 8, y: midY))
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.62))
    ctx.move(to: CGPoint(x: x0 + ruleW - 6, y: midY + 5))
    ctx.addLine(to: CGPoint(x: x0 + ruleW, y: midY))
    ctx.addLine(to: CGPoint(x: x0 + ruleW - 6, y: midY - 5))
    ctx.strokePath()

    // Closing lines, 26px from the bottom of the block, 11.5px / 1.5.
    let closing = ["Thermal lives in the menu bar.",
                   "It asks for sensor access the first time you open it."]
    let lineH: CGFloat = 11.5 * 1.5
    var cy = H - 26 - lineH * CGFloat(closing.count)
    for l in closing {
        _ = drawText(ctx, l, font: .systemFont(ofSize: 11.5),
                     color: CGColor(gray: 1, alpha: 0.42), tracking: 0,
                     centerX: W / 2, topY: cy + (lineH - 11.5) / 2, canvasH: H)
        cy += lineH
    }
    return ctx.makeImage()!
}

// MARK: - Output plumbing

let fm = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func writePNG(_ image: CGImage, to url: URL) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func writeTIFF(_ image: CGImage, pointSize: NSSize, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = pointSize // sets dpi so tiffutil/Finder pick the right rep
    try! rep.representation(using: .tiff, properties: [:])!.write(to: url)
}

@discardableResult
func run(_ tool: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    try! p.run()
    p.waitUntilExit()
    return p.terminationStatus
}

func buildICNS(name: String, render: (Int, Bool) -> CGImage) {
    let iconset = root.appendingPathComponent("dist/\(name).iconset")
    try? fm.removeItem(at: iconset)
    try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    // (point size, scale). 16pt and 32pt ship the simplified drawing.
    for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                        (256, 1), (256, 2), (512, 1), (512, 2)] {
        let simplified = pt <= 32
        let img = render(pt * scale, simplified)
        let suffix = scale == 2 ? "@2x" : ""
        writePNG(img, to: iconset.appendingPathComponent("icon_\(pt)x\(pt)\(suffix).png"))
    }
    let out = root.appendingPathComponent("Resources/\(name).icns")
    try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", out.path]) == 0 else {
        fatalError("iconutil failed for \(name)")
    }
    try? fm.removeItem(at: iconset)
    print("wrote \(out.path)")
}

// MARK: - Main

buildICNS(name: "Thermal") { renderAppIcon(px: $0, simplified: $1) }
buildICNS(name: "VolumeIcon") { renderVolumeIcon(px: $0, simplified: $1) }

let dmgDir = root.appendingPathComponent("Resources/dmg")
try? fm.createDirectory(at: dmgDir, withIntermediateDirectories: true)
let bg1 = renderDMGBackground(scale: 1)
let bg2 = renderDMGBackground(scale: 2)
let t1 = dmgDir.appendingPathComponent("bg-1x.tiff")
let t2 = dmgDir.appendingPathComponent("bg-2x.tiff")
writeTIFF(bg1, pointSize: NSSize(width: 660, height: 420), to: t1)
writeTIFF(bg2, pointSize: NSSize(width: 660, height: 420), to: t2)
let bgOut = dmgDir.appendingPathComponent("background.tiff")
guard run("/usr/bin/tiffutil", ["-cathidpicheck", t1.path, t2.path, "-out", bgOut.path]) == 0 else {
    fatalError("tiffutil failed")
}
try? fm.removeItem(at: t1)
try? fm.removeItem(at: t2)
print("wrote \(bgOut.path)")

// Contact sheet: the sizes the prototype checks (112/64/58/26/19 equivalents)
// on light and dark strips, plus the DMG art.
do {
    let sizes = [512, 128, 64, 32, 16]
    let pad = 24
    let stripH = 512 + pad * 2
    let W = max(sizes.reduce(0, +) + pad * (sizes.count + 1), 1320)
    let ctx = makeContext(W, stripH * 2 + 840 + pad)
    ctx.setFillColor(hex(0xF2F2F4))
    ctx.fill(CGRect(x: 0, y: CGFloat(840 + pad + stripH), width: CGFloat(W), height: CGFloat(stripH)))
    ctx.setFillColor(hex(0x1B1B1E))
    ctx.fill(CGRect(x: 0, y: CGFloat(840 + pad), width: CGFloat(W), height: CGFloat(stripH)))
    for (rowIndex, isVolume) in [false, true].enumerated() {
        var x = pad
        let rowY = 840 + pad + stripH * (1 - rowIndex)
        for s in sizes {
            let img = isVolume ? renderVolumeIcon(px: s, simplified: s <= 32)
                               : renderAppIcon(px: s, simplified: s <= 32)
            ctx.draw(img, in: CGRect(x: CGFloat(x), y: CGFloat(rowY + pad),
                                     width: CGFloat(s), height: CGFloat(s)))
            x += s + pad
        }
    }
    ctx.draw(bg2, in: CGRect(x: 0, y: 0, width: 1320, height: 840))
    let out = root.appendingPathComponent("dist/asset-preview.png")
    writePNG(ctx.makeImage()!, to: out)
    print("wrote \(out.path)")
}

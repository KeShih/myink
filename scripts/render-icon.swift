#!/usr/bin/env swift
// Renders Myink's 1024 px master icon (a macOS-style squircle with a tray glyph).
// Usage: swift scripts/render-icon.swift Resources/AppIcon-1024.png
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let canvas: CGFloat = 1024
let inset: CGFloat = 100 // standard macOS icon grid: 824 pt body, 100 pt margins
let body = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
let cornerRadius: CGFloat = 185

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
let cg = context.cgContext

let squircle = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)

// Soft drop shadow under the body.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
NSColor.black.setFill()
squircle.fill()
cg.restoreGState()

// Body gradient: indigo → teal.
cg.saveGState()
squircle.addClip()
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.35, green: 0.27, blue: 0.93, alpha: 1),
    NSColor(srgbRed: 0.09, green: 0.60, blue: 0.86, alpha: 1)
])!
gradient.draw(in: body, angle: -70)

// Gentle top sheen.
let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
sheen.draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

// Glyph.
let configuration = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration) {
    let size = symbol.size
    let rect = NSRect(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2 - 8, width: size.width, height: size.height)
    cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    symbol.draw(in: rect)
}

cg.restoreGState()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")

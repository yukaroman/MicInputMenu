#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_app_icon.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvasSize = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)

image.lockFocus()

NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let tileRect = NSRect(x: 72, y: 72, width: 880, height: 880)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 196, yRadius: 196)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()
NSColor(calibratedRed: 0.94, green: 0.31, blue: 0.27, alpha: 1).setFill()
tilePath.fill()
NSShadow().set()

NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
NSColor(calibratedRed: 0.05, green: 0.48, blue: 0.43, alpha: 1).setFill()
NSRect(x: 72, y: 72, width: 880, height: 305).fill()
NSGraphicsContext.restoreGraphicsState()

let ivory = NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.92, alpha: 1)
let gold = NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.31, alpha: 1)

let microphoneBody = NSBezierPath(
    roundedRect: NSRect(x: 382, y: 384, width: 260, height: 390),
    xRadius: 130,
    yRadius: 130
)
ivory.setFill()
microphoneBody.fill()

let bodyAccent = NSBezierPath(roundedRect: NSRect(x: 466, y: 474, width: 92, height: 214), xRadius: 46, yRadius: 46)
NSColor(calibratedRed: 0.94, green: 0.31, blue: 0.27, alpha: 1).setFill()
bodyAccent.fill()

let cradle = NSBezierPath()
cradle.move(to: NSPoint(x: 314, y: 548))
cradle.curve(
    to: NSPoint(x: 710, y: 548),
    controlPoint1: NSPoint(x: 314, y: 322),
    controlPoint2: NSPoint(x: 710, y: 322)
)
cradle.lineWidth = 48
cradle.lineCapStyle = .round
ivory.setStroke()
cradle.stroke()

let stem = NSBezierPath(roundedRect: NSRect(x: 488, y: 246, width: 48, height: 120), xRadius: 24, yRadius: 24)
ivory.setFill()
stem.fill()

let base = NSBezierPath(roundedRect: NSRect(x: 366, y: 224, width: 292, height: 48), xRadius: 24, yRadius: 24)
ivory.setFill()
base.fill()

for (x, height) in [(238.0, 108.0), (182.0, 68.0), (786.0, 108.0), (842.0, 68.0)] {
    let bar = NSBezierPath(
        roundedRect: NSRect(x: x - 12, y: 526 - height / 2, width: 24, height: height),
        xRadius: 12,
        yRadius: 12
    )
    gold.setFill()
    bar.fill()
}

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to render app icon\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("Unable to write app icon: \(error.localizedDescription)\n", stderr)
    exit(1)
}

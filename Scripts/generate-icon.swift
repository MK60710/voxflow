#!/usr/bin/env swift
// Draws VoxFlow's app icon (waveform glyph on Direction D's accent blue,
// see docs/window-ux-plan.md / plans/voxflow-windowed-ui.md Step 8) and
// packages it into Resources/AppIcon.icns. Visual design here is exempt
// from tdd-and-fixing's Iron Law (generated-code exception, approved by
// Mihir — see .claude-state/app-icon/ledger.md); Scripts/test-icon.sh
// covers the packaging/wiring this script feeds into.
//
// One-shot generator, not app runtime code: run with `swift
// Scripts/generate-icon.swift` whenever the icon design changes.

import AppKit
import Foundation

let canvasSize = 1024.0
let cornerRadius = canvasSize * 0.2237 // Apple's standard macOS icon corner ratio
// Direction D's accent blue (VoxFlowTheme.accent's light-mode value) — app
// icons are a single fixed design, not light/dark adaptive like in-app UI.
let accentColor = NSColor(red: 0x0A / 255.0, green: 0x5F / 255.0, blue: 0xD6 / 255.0, alpha: 1.0)

let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
image.lockFocus()

let bounds = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
let background = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
accentColor.setFill()
background.fill()

// Waveform glyph: 5 vertical bars, rounded caps, matching the sidebar's
// own "waveform" SF Symbol silhouette — heights mirror a natural
// speech-waveform shape (low-high-highest-high-low).
let barWidth = canvasSize * 0.052
let barSpacing = canvasSize * 0.048
let barHeights: [Double] = [0.28, 0.48, 0.66, 0.48, 0.28].map { $0 * canvasSize }
let totalWidth = Double(barHeights.count) * barWidth + Double(barHeights.count - 1) * barSpacing
var x = (canvasSize - totalWidth) / 2

NSColor.white.setFill()
for height in barHeights {
    let barRect = NSRect(x: x, y: (canvasSize - height) / 2, width: barWidth, height: height)
    let bar = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
    bar.fill()
    x += barWidth + barSpacing
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to render icon to PNG\n".data(using: .utf8)!)
    exit(1)
}

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resourcesDir = repoRoot.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

let masterPNG = resourcesDir.appendingPathComponent("AppIcon-1024.png")
try pngData.write(to: masterPNG)
print("Wrote master icon: \(masterPNG.path)")

// Package into a real .icns via sips (per-size downsampling) + iconutil
// (iconset -> icns), the standard macOS toolchain for this — no
// third-party dependency.
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

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
    ("icon_512x512@2x.png", 1024)
]

func run(_ launchPath: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    try? process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        FileHandle.standardError.write("Command failed: \(launchPath) \(arguments.joined(separator: " "))\n".data(using: .utf8)!)
        exit(1)
    }
}

for size in sizes {
    let outPath = iconsetDir.appendingPathComponent(size.name).path
    run("/usr/bin/sips", ["-z", "\(size.pixels)", "\(size.pixels)", masterPNG.path, "--out", outPath])
}

let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns").path
run("/usr/bin/iconutil", ["-c", "icns", iconsetDir.path, "-o", icnsPath])
print("Wrote icon: \(icnsPath)")

try? FileManager.default.removeItem(at: iconsetDir)

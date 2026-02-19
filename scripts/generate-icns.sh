#!/usr/bin/env bash
set -euo pipefail

# Generate SBBender.icns from the programmatic AppIcon.
# Requires: swift (to run AppIcon generation), iconutil
#
# Uses sips to convert if needed, then iconutil to produce .icns

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ICONSET_DIR="$PROJECT_DIR/dist/SBBender.iconset"
OUTPUT_ICNS="$PROJECT_DIR/dist/SBBender.icns"

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
step()  { bold "→ $*"; }

# Create iconset directory
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Generate icon PNGs using a Swift script that calls AppIcon.generate()
step "Generating icon PNGs via Swift..."

cat > /tmp/generate_icons.swift << 'SWIFT'
import AppKit

// Minimal recreation of AppIcon for CLI context
func generateIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.2

    // Background gradient
    let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.9, alpha: 1.0),
        NSColor(calibratedRed: 0.5, green: 0.2, blue: 0.9, alpha: 1.0),
    ])
    gradient?.draw(in: path, angle: 135)

    // SB text
    let fontSize = size * 0.42
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let text = "SB" as NSString
    let textSize = text.size(withAttributes: attrs)
    let textPoint = NSPoint(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2
    )
    text.draw(at: textPoint, withAttributes: attrs)

    image.unlockFocus()
    return image
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let outputDir = CommandLine.arguments[1]

for (name, size) in sizes {
    let icon = generateIcon(size: size)
    guard let tiff = icon.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to generate PNG for \(name)")
    }
    let path = "\(outputDir)/\(name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("  Generated \(name).png (\(Int(size))x\(Int(size)))")
}
SWIFT

swift /tmp/generate_icons.swift "$ICONSET_DIR"

# Convert to .icns
step "Creating .icns..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

# Cleanup
rm -rf "$ICONSET_DIR"
rm -f /tmp/generate_icons.swift

step "Done: $OUTPUT_ICNS"

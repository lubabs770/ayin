#!/bin/bash

# Generate application icons for Iris.app
# Creates all required icon sizes based on Contents.json

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/Iris"
ICON_DIR="$PROJECT_DIR/Iris/Assets.xcassets/AppIcon.appiconset"
CONTENTS_JSON="$ICON_DIR/Contents.json"

echo "🎨 Generating application icons..."

# Check if icon directory exists
if [ ! -d "$ICON_DIR" ]; then
    echo "❌ Error: Icon directory not found: $ICON_DIR"
    exit 1
fi

# Create a temporary Swift script to generate icons
TEMP_SCRIPT=$(mktemp /tmp/generate_icons.XXXXXX.swift)
cat > "$TEMP_SCRIPT" << 'SWIFT_SCRIPT'
import Foundation
import Cocoa

let iconDir = CommandLine.arguments[1]

// Icon sizes to generate (size in points, scale factor, filename)
let iconSizes: [(size: CGFloat, scale: Int, filename: String, jsonSize: String)] = [
    (16, 1, "icon_16x16.png", "16x16"),
    (32, 2, "icon_16x16@2x.png", "16x16"),
    (32, 1, "icon_32x32.png", "32x32"),
    (64, 2, "icon_32x32@2x.png", "32x32"),
    (128, 1, "icon_128x128.png", "128x128"),
    (256, 2, "icon_128x128@2x.png", "128x128"),
    (256, 1, "icon_256x256.png", "256x256"),
    (512, 2, "icon_256x256@2x.png", "256x256"),
    (512, 1, "icon_512x512.png", "512x512"),
    (1024, 2, "icon_512x512@2x.png", "512x512"),
]

// Generate app icon: concentric rings on a light disc (matches the menu bar icon)
func generateAppIcon(size: CGSize) -> NSImage {
    let image = NSImage(size: size, flipped: false) { rect in
        let d = min(size.width, size.height)
        let center = NSPoint(x: rect.midX, y: rect.midY)

        func circle(_ r: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }

        let bg = circle(d * 0.48)
        NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.88, alpha: 1)])?
            .draw(in: bg, angle: -90)

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let outer = circle(d * 0.36)
        outer.lineWidth = max(1, d * 0.055)
        outer.stroke()

        let middle = circle(d * 0.225)
        middle.lineWidth = max(1, d * 0.045)
        middle.stroke()

        circle(d * 0.09).fill()

        return true
    }
    return image
}

// Generate all icons and collect JSON entries
var jsonEntries: [[String: String]] = []

for iconSpec in iconSizes {
    let size = CGSize(width: iconSpec.size, height: iconSpec.size)
    let image = generateAppIcon(size: size)

    guard let tiffData = image.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData) else {
        print("Error: Failed to create bitmap for \(iconSpec.filename)")
        exit(1)
    }

    guard let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
        print("Error: Failed to create PNG for \(iconSpec.filename)")
        exit(1)
    }

    let outputPath = (iconDir as NSString).appendingPathComponent(iconSpec.filename)
    let url = URL(fileURLWithPath: outputPath)

    do {
        try pngData.write(to: url)
        print("✅ Generated \(iconSpec.filename)")

        // Create JSON entry
        let scaleStr = iconSpec.scale == 1 ? "1x" : "2x"
        jsonEntries.append([
            "filename": iconSpec.filename,
            "idiom": "mac",
            "scale": scaleStr,
            "size": iconSpec.jsonSize
        ])
    } catch {
        print("Error: Failed to write \(iconSpec.filename): \(error)")
        exit(1)
    }
}

// Create JSON structure
let jsonDict: [String: Any] = [
    "images": jsonEntries,
    "info": [
        "author": "xcode",
        "version": 1
    ]
]

// Write JSON
let jsonData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
let jsonString = String(data: jsonData, encoding: .utf8)!
let jsonURL = URL(fileURLWithPath: (iconDir as NSString).appendingPathComponent("Contents.json"))
try jsonString.write(to: jsonURL, atomically: true, encoding: .utf8)

print("✅ Updated Contents.json")
print("✅ All icons generated successfully!")
SWIFT_SCRIPT

# Run the Swift script
swift "$TEMP_SCRIPT" "$ICON_DIR"

# Clean up
rm "$TEMP_SCRIPT"

echo "✅ Icon generation complete!"

import AppKit

/// Generates a Bender-inspired app icon programmatically.
/// Metallic robot head with antenna, visor eyes, and mouth grid.
enum AppIcon {
    static func generate(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let s = size // shorthand
        let center = s / 2

        // Background — dark rounded rect
        let bgRect = CGRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0))
        ctx.fillPath()

        // Head — metallic gray oval
        let headRect = CGRect(x: s * 0.18, y: s * 0.15, width: s * 0.64, height: s * 0.65)
        let headGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.75, green: 0.78, blue: 0.82, alpha: 1.0),
                CGColor(red: 0.55, green: 0.58, blue: 0.63, alpha: 1.0),
                CGColor(red: 0.40, green: 0.42, blue: 0.47, alpha: 1.0),
            ] as CFArray,
            locations: [0.0, 0.5, 1.0]
        )!

        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.drawLinearGradient(
            headGradient,
            start: CGPoint(x: center, y: headRect.maxY),
            end: CGPoint(x: center, y: headRect.minY),
            options: []
        )
        ctx.restoreGState()

        // Head outline
        ctx.addEllipse(in: headRect)
        ctx.setStrokeColor(CGColor(red: 0.3, green: 0.32, blue: 0.36, alpha: 1.0))
        ctx.setLineWidth(s * 0.008)
        ctx.strokePath()

        // Antenna — stalk
        let antennaBaseX = center
        let antennaBaseY = headRect.maxY - s * 0.02
        let antennaTipY = s * 0.92

        ctx.setStrokeColor(CGColor(red: 0.6, green: 0.63, blue: 0.67, alpha: 1.0))
        ctx.setLineWidth(s * 0.02)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: antennaBaseX, y: antennaBaseY))
        ctx.addLine(to: CGPoint(x: antennaBaseX, y: antennaTipY))
        ctx.strokePath()

        // Antenna ball — glowing blue
        let ballRadius = s * 0.035
        let ballCenter = CGPoint(x: antennaBaseX, y: antennaTipY)

        // Glow
        let glowGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 0.6),
                CGColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 0.0),
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            glowGradient,
            startCenter: ballCenter, startRadius: 0,
            endCenter: ballCenter, endRadius: ballRadius * 3,
            options: []
        )

        // Ball
        ctx.addArc(center: ballCenter, radius: ballRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setFillColor(CGColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1.0))
        ctx.fillPath()

        // Visor — dark rounded rectangle across eyes
        let visorRect = CGRect(x: s * 0.22, y: s * 0.42, width: s * 0.56, height: s * 0.2)
        let visorPath = CGPath(roundedRect: visorRect, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil)
        ctx.addPath(visorPath)
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0))
        ctx.fillPath()

        // Visor border
        ctx.addPath(visorPath)
        ctx.setStrokeColor(CGColor(red: 0.35, green: 0.37, blue: 0.42, alpha: 1.0))
        ctx.setLineWidth(s * 0.006)
        ctx.strokePath()

        // Eyes — two glowing circles inside visor
        let eyeRadius = s * 0.06
        let eyeY = visorRect.midY
        let leftEyeX = center - s * 0.12
        let rightEyeX = center + s * 0.12

        for eyeX in [leftEyeX, rightEyeX] {
            let eyeCenter = CGPoint(x: eyeX, y: eyeY)

            // Eye glow
            let eyeGlow = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    CGColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 0.4),
                    CGColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 0.0),
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            ctx.drawRadialGradient(
                eyeGlow,
                startCenter: eyeCenter, startRadius: 0,
                endCenter: eyeCenter, endRadius: eyeRadius * 2,
                options: []
            )

            // Eye circle
            ctx.addArc(center: eyeCenter, radius: eyeRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.setFillColor(CGColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 1.0))
            ctx.fillPath()

            // Pupil
            ctx.addArc(center: eyeCenter, radius: eyeRadius * 0.4, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0))
            ctx.fillPath()

            // Highlight
            let hlCenter = CGPoint(x: eyeX - eyeRadius * 0.25, y: eyeY + eyeRadius * 0.25)
            ctx.addArc(center: hlCenter, radius: eyeRadius * 0.18, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.7))
            ctx.fillPath()
        }

        // Mouth — grid of horizontal lines
        let mouthRect = CGRect(x: s * 0.3, y: s * 0.2, width: s * 0.4, height: s * 0.12)
        let mouthPath = CGPath(roundedRect: mouthRect, cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil)
        ctx.addPath(mouthPath)
        ctx.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0))
        ctx.fillPath()

        // Mouth grid lines
        ctx.setStrokeColor(CGColor(red: 0.45, green: 0.47, blue: 0.52, alpha: 1.0))
        ctx.setLineWidth(s * 0.004)
        let gridSpacing = mouthRect.height / 4
        for i in 1..<4 {
            let y = mouthRect.minY + gridSpacing * CGFloat(i)
            ctx.move(to: CGPoint(x: mouthRect.minX + s * 0.02, y: y))
            ctx.addLine(to: CGPoint(x: mouthRect.maxX - s * 0.02, y: y))
        }
        ctx.strokePath()

        // Vertical mouth lines
        let vSpacing = mouthRect.width / 6
        for i in 1..<6 {
            let x = mouthRect.minX + vSpacing * CGFloat(i)
            ctx.move(to: CGPoint(x: x, y: mouthRect.minY + s * 0.01))
            ctx.addLine(to: CGPoint(x: x, y: mouthRect.maxY - s * 0.01))
        }
        ctx.strokePath()

        // Mouth border
        ctx.addPath(mouthPath)
        ctx.setStrokeColor(CGColor(red: 0.35, green: 0.37, blue: 0.42, alpha: 1.0))
        ctx.setLineWidth(s * 0.006)
        ctx.strokePath()

        // "SB" text on forehead — subtle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: s * 0.06, weight: .bold),
            .foregroundColor: NSColor(red: 0.5, green: 0.52, blue: 0.56, alpha: 0.6),
        ]
        let text = NSAttributedString(string: "SB", attributes: attrs)
        let textSize = text.size()
        let textPoint = NSPoint(x: center - textSize.width / 2, y: s * 0.66)
        text.draw(at: textPoint)

        image.unlockFocus()
        return image
    }
}

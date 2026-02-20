import AppKit

/// App icon: warm amber-rose-indigo gradient with a single luminous HAL-inspired iris.
/// One perfect circle. Maximum restraint. Maximum impact.
///
/// NOTE: We do NOT clip to a rounded rect here. The macOS Dock applies the squircle
/// mask automatically to all app icons. Clipping ourselves first would double-clip
/// (our shape vs the system squircle) and produce visible misalignment.
/// We paint the full square canvas; the system handles the shape.
enum AppIcon {
    static func generate(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let s = size
        let cx = s / 2
        // Optically center the eye slightly above geometric center
        let cy = s / 2 + s * 0.018

        // MARK: - Background: warm amber → deep rose → rich indigo, diagonal

        let bgGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.95, green: 0.52, blue: 0.20, alpha: 1.0),  // warm amber
                CGColor(red: 0.75, green: 0.20, blue: 0.42, alpha: 1.0),  // deep rose
                CGColor(red: 0.24, green: 0.08, blue: 0.55, alpha: 1.0),  // rich indigo
            ] as CFArray,
            locations: [0.0, 0.50, 1.0]
        )!
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: s * 0.90, y: s * 0.90),
            end:   CGPoint(x: s * 0.10, y: s * 0.10),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        // Warm radial bloom at center
        let bloomGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1.0, green: 0.78, blue: 0.55, alpha: 0.22),
                CGColor(red: 1.0, green: 0.78, blue: 0.55, alpha: 0.0),
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            bloomGradient,
            startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
            endCenter:   CGPoint(x: cx, y: cy), endRadius: s * 0.52,
            options: []
        )

        // MARK: - Eye

        let eye = CGPoint(x: cx, y: cy)
        // Sized so the ring fills ~56% of the icon diameter — bold, like other pro icons
        let ringR  = s * 0.280
        let irisR  = s * 0.220
        let pupilR = s * 0.078

        // ── Outer halo (soft white glow around the ring)
        let haloGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16),
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            haloGradient,
            startCenter: eye, startRadius: ringR * 0.80,
            endCenter:   eye, endRadius:   ringR * 1.70,
            options: []
        )

        // ── Ring stroke (crisp white circle)
        ctx.addArc(center: eye, radius: ringR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.92))
        ctx.setLineWidth(s * 0.018)
        ctx.strokePath()

        // ── Thin inner accent ring — adds glass thickness illusion
        ctx.addArc(center: eye, radius: ringR - s * 0.024, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18))
        ctx.setLineWidth(s * 0.006)
        ctx.strokePath()

        // ── Iris fill: white radial gradient, bright centre, fading to translucent
        let irisGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.82),
                CGColor(red: 1.00, green: 0.96, blue: 0.94, alpha: 0.42),
                CGColor(red: 1.00, green: 0.90, blue: 0.88, alpha: 0.08),
            ] as CFArray,
            locations: [0.0, 0.60, 1.0]
        )!
        ctx.saveGState()
        ctx.addArc(center: eye, radius: irisR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.clip()
        ctx.drawRadialGradient(
            irisGradient,
            startCenter: eye, startRadius: 0,
            endCenter:   eye, endRadius: irisR,
            options: []
        )
        ctx.restoreGState()

        // ── Pupil: deep dark gradient revealing depth
        let pupilGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.10, green: 0.04, blue: 0.28, alpha: 0.96),
                CGColor(red: 0.20, green: 0.08, blue: 0.45, alpha: 0.72),
                CGColor(red: 0.30, green: 0.12, blue: 0.60, alpha: 0.0),
            ] as CFArray,
            locations: [0.0, 0.55, 1.0]
        )!
        ctx.saveGState()
        ctx.addArc(center: eye, radius: pupilR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.clip()
        ctx.drawRadialGradient(
            pupilGradient,
            startCenter: eye, startRadius: 0,
            endCenter:   eye, endRadius: pupilR,
            options: []
        )
        ctx.restoreGState()

        // Thin white ring around pupil edge
        ctx.addArc(center: eye, radius: pupilR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.22))
        ctx.setLineWidth(s * 0.005)
        ctx.strokePath()

        // ── Primary specular: bright reflection, upper-left of iris
        let specCenter = CGPoint(
            x: eye.x - irisR * 0.30,
            y: eye.y + irisR * 0.28
        )
        let specGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.88),
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            specGradient,
            startCenter: specCenter, startRadius: 0,
            endCenter:   specCenter, endRadius: irisR * 0.26,
            options: []
        )

        // ── Secondary micro-specular: tiny dot, opposite side
        let spec2 = CGPoint(x: eye.x + irisR * 0.35, y: eye.y - irisR * 0.32)
        let spec2Gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.22),
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            spec2Gradient,
            startCenter: spec2, startRadius: 0,
            endCenter:   spec2, endRadius: irisR * 0.14,
            options: []
        )

        image.unlockFocus()
        return image
    }
}

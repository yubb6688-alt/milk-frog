import AppKit

/// Uses the generated image only as a local arm patch, never as a full pose.
/// All coordinates are normalized to the unchanged typing bitmap (top-left).
enum ThinkingPose {
    static func weight(x: Double, y: Double) -> Double {
        let raised = polygonWeight(x: x, y: y, points: [
            CGPoint(x: 0.115, y: 0.488), CGPoint(x: 0.116, y: 0.420),
            CGPoint(x: 0.165, y: 0.345), CGPoint(x: 0.194, y: 0.300),
            CGPoint(x: 0.238, y: 0.272), CGPoint(x: 0.291, y: 0.271),
            CGPoint(x: 0.309, y: 0.291), CGPoint(x: 0.305, y: 0.322),
            CGPoint(x: 0.290, y: 0.336), CGPoint(x: 0.318, y: 0.361),
            CGPoint(x: 0.319, y: 0.403), CGPoint(x: 0.288, y: 0.445),
            CGPoint(x: 0.287, y: 0.493)
        ])
        // Restore the belly/keys formerly hidden by the far arm. The near hand
        // and the laptop screen stay outside this region.
        let vacated = polygonWeight(x: x, y: y, points: [
            CGPoint(x: 0.275, y: 0.468), CGPoint(x: 0.375, y: 0.475),
            CGPoint(x: 0.440, y: 0.500), CGPoint(x: 0.475, y: 0.550),
            CGPoint(x: 0.490, y: 0.550), CGPoint(x: 0.525, y: 0.550),
            CGPoint(x: 0.583, y: 0.562), CGPoint(x: 0.580, y: 0.590),
            CGPoint(x: 0.550, y: 0.621), CGPoint(x: 0.551, y: 0.666),
            CGPoint(x: 0.450, y: 0.666), CGPoint(x: 0.420, y: 0.612),
            CGPoint(x: 0.395, y: 0.535)
        ])
        return max(raised, vacated)
    }

    static func protectsLaptop(x: Double, y: Double) -> Bool {
        // Front screen and its rim. The keyboard is already outside the arm
        // patch except for the newly revealed area beneath the old fingers.
        polygonWeight(x: x, y: y, points: [
            CGPoint(x: 0, y: 0.460), CGPoint(x: 0.390, y: 0.508),
            CGPoint(x: 0.483, y: 0.789), CGPoint(x: 0.055, y: 0.713)
        ]) > 0
    }

    private static func polygonWeight(x: Double, y: Double, points: [CGPoint]) -> Double {
        var inside = false
        var distance = Double.infinity
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            if (a.y > y) != (b.y > y), x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            let dx = b.x - a.x, dy = b.y - a.y
            let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy)))
            distance = min(distance, hypot(x - a.x - t * dx, y - a.y - t * dy))
        }
        return inside ? min(1, distance / 0.005) : 0
    }

    static func make(base: IdleFrame, patchURL: URL) -> IdleFrame? {
        guard let patchImage = NSImage(contentsOf: patchURL),
              let patch = IdleFrame(image: patchImage),
              let data = base.image.tiffRepresentation,
              let original = NSBitmapImageRep(data: data),
              let result = original.copy() as? NSBitmapImageRep,
              let resized = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: original.pixelsWide,
                  pixelsHigh: original.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                  hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                  bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: resized) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        patch.image.draw(in: NSRect(x: 0, y: 0, width: original.pixelsWide, height: original.pixelsHigh),
                         from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        for y in 0..<original.pixelsHigh {
            for x in 0..<original.pixelsWide {
                let amount = weight(x: Double(x) / Double(original.pixelsWide), y: Double(y) / Double(original.pixelsHigh))
                guard amount > 0,
                      let old = original.colorAt(x: x, y: y)?.usingColorSpace(.genericRGB),
                      let new = resized.colorAt(x: x, y: y)?.usingColorSpace(.genericRGB),
                      old.alphaComponent > 0.95, new.alphaComponent > 0.95 else { continue }
                // Preserve every visible laptop pixel, including its screen rim.
                let isLaptop = protectsLaptop(x: Double(x) / Double(original.pixelsWide), y: Double(y) / Double(original.pixelsHigh))
                if isLaptop { continue }
                let color = NSColor(calibratedRed: old.redComponent * (1 - amount) + new.redComponent * amount,
                                    green: old.greenComponent * (1 - amount) + new.greenComponent * amount,
                                    blue: old.blueComponent * (1 - amount) + new.blueComponent * amount,
                                    alpha: old.alphaComponent)
                result.setColor(color, atX: x, y: y)
            }
        }
        let image = NSImage(size: base.image.size)
        image.addRepresentation(result)
        return IdleFrame(image: image, targetHeight: 120)
    }
}

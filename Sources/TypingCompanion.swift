import AppKit

struct TypingSnapshot {
    let focused: Bool
    let frameIndex: Int
}

struct TypingActivity {
    static let thinkingDelay: TimeInterval = 1.2
    private(set) var focused = false
    private var lastStroke: TimeInterval?
    private var nextHand = 1
    private var pressedHand = 1

    mutating func setFocused(_ value: Bool) {
        if focused != value {
            focused = value
            lastStroke = nil
            nextHand = 1
        }
    }

    mutating func recordStroke(at time: TimeInterval) {
        guard focused else { return }
        pressedHand = nextHand
        nextHand = nextHand == 1 ? 2 : 1
        lastStroke = time
    }

    func snapshot(at time: TimeInterval) -> TypingSnapshot {
        guard focused, let lastStroke else { return TypingSnapshot(focused: focused, frameIndex: 0) }
        let elapsed = time - lastStroke
        if elapsed >= Self.thinkingDelay {
            return TypingSnapshot(focused: true, frameIndex: TypingAnimation.thinkingIndex)
        }
        // An immediate press remains visible even during fast typing. The half
        // press then eases the hand back without moving the computer or body.
        let pose = elapsed >= 0 && elapsed < 0.11 ? 2 : (elapsed >= 0.11 && elapsed < 0.20 ? 1 : 0)
        return TypingSnapshot(focused: focused, frameIndex: pose == 0 ? 0 : (pressedHand - 1) * 2 + pose)
    }
}

struct TypingApproach {
    let startX: CGFloat
    let targetX: CGFloat
    let startedAt: TimeInterval
    let duration: TimeInterval

    init(startX: CGFloat, screen: NSRect, at time: TimeInterval) {
        self.startX = startX
        let left = screen.minX + 8
        let right = max(left, screen.maxX - 208)
        targetX = min(max(startX, left), right)
        startedAt = time
        duration = min(0.65, Double(abs(targetX - startX) / 600))
    }

    func hasArrived(at time: TimeInterval) -> Bool { time - startedAt >= duration }

    func sample(at time: TimeInterval, frameIndex: Int) -> PetMotion {
        if hasArrived(at: time) {
            return PetMotion(x: targetX, activity: .working, facingRight: true,
                             phase: "working", spriteIndex: frameIndex)
        }
        let progress = CGFloat(max(0, time - startedAt) / duration)
        return PetMotion(x: startX + (targetX - startX) * progress,
                         activity: .walking, facingRight: targetX > startX, phase: "typing-enter")
    }
}

enum TypingAnimation {
    static let typingCount = 5
    static let thinkingIndex = 5
    static let count = 6
    static func load(from url: URL, thinkingURL: URL) -> [IdleFrame] {
        // Every pose comes from the same image. Independent generated cells have
        // slightly different laptops, so never use them as full typing frames.
        guard let base = WalkCycle.loadSheet(from: url, columns: 3, rows: 1, frameHeight: 120).first,
              let data = base.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else { return [] }
        var frames = [base]
        for index in 1..<typingCount {
            let hand = (index - 1) / 2
            let depth = index % 2 == 0 ? 0.055 : 0.0275
            guard let pressed = bitmap.copy() as? NSBitmapImageRep else { return [] }
            let width = bitmap.pixelsWide
            let height = bitmap.pixelsHigh
            for y in 0..<height {
                for x in 0..<width {
                    let point = CGPoint(x: Double(x) / Double(width), y: Double(y) / Double(height))
                    let amount = handWeight(at: point, hand: hand)
                    guard amount > 0, let original = bitmap.colorAt(x: x, y: y), original.alphaComponent > 0.95 else { continue }
                    let sourceY = max(0, Double(y) - amount * Double(height) * depth)
                    let y0 = Int(sourceY)
                    let y1 = min(height - 1, y0 + 1)
                    guard let a = bitmap.colorAt(x: x, y: y0)?.usingColorSpace(.genericRGB),
                          let b = bitmap.colorAt(x: x, y: y1)?.usingColorSpace(.genericRGB),
                          isHand(a), isHand(b) else { continue }
                    let t = sourceY - Double(y0)
                    let color = NSColor(calibratedRed: a.redComponent * (1 - t) + b.redComponent * t,
                                        green: a.greenComponent * (1 - t) + b.greenComponent * t,
                                        blue: a.blueComponent * (1 - t) + b.blueComponent * t, alpha: 1)
                    pressed.setColor(color, atX: x, y: y)
                }
            }
            let image = NSImage(size: base.image.size)
            image.addRepresentation(pressed)
            guard let frame = IdleFrame(image: image, targetHeight: 120) else { return [] }
            frames.append(frame)
        }
        guard let thinking = ThinkingPose.make(base: base, patchURL: thinkingURL) else { return [] }
        frames.append(thinking)
        return frames
    }

    // Coordinates in the cropped reference pose, with y measured from the top.
    // Deformation fades to zero at the wrists. Only yellow hand pixels may be
    // sampled: fingertips can cover keys as they press, but the laptop itself
    // is never translated, resampled, resized, or replaced by another pose.
    static func handWeight(at point: CGPoint, hand: Int) -> Double {
        let center = hand == 0 ? CGPoint(x: 0.504, y: 0.624) : CGPoint(x: 0.623, y: 0.666)
        let radius = hand == 0 ? CGSize(width: 0.080, height: 0.095) : CGSize(width: 0.100, height: 0.110)
        let dx = (point.x - center.x) / radius.width
        let dy = (point.y - center.y) / radius.height
        let weight = max(0, 1 - dx * dx - dy * dy)
        return weight * weight
    }

    static func isHand(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.genericRGB) else { return false }
        // Include the warm finger shadows so they travel with the fingertips,
        // while rejecting the neutral grey keyboard and laptop casing.
        let red = (rgb.redComponent * 255).rounded()
        let green = (rgb.greenComponent * 255).rounded()
        let blue = (rgb.blueComponent * 255).rounded()
        return rgb.alphaComponent > 0.95 && red >= 64 && green >= 36 && blue <= (green * 0.80).rounded()
    }
}

import AppKit
import QuartzCore

struct IdleFrame {
    let image: NSImage
    let drawingRect: NSRect

    init?(image: NSImage) {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let cgImage = bitmap.cgImage else { return nil }

        // Ignore near-invisible export residue when measuring the character.
        // Cropping changes only transparent margins; scale stays proportional.
        var left = bitmap.pixelsWide
        var top = bitmap.pixelsHigh
        var right = -1
        var bottom = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 16.0 / 255.0 {
                    left = min(left, x)
                    top = min(top, y)
                    right = max(right, x)
                    bottom = max(bottom, y)
                }
            }
        }
        guard right >= left, bottom >= top else { return nil }
        let crop = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        guard let cropped = cgImage.cropping(to: crop) else { return nil }
        self.image = NSImage(cgImage: cropped, size: crop.size)

        // Match the previous on-screen size; every pose has the same height,
        // horizontal center and ground line inside the unchanged 200 × 200 window.
        let height: CGFloat = 132
        let width = crop.width * height / crop.height
        drawingRect = NSRect(x: (200 - width) / 2, y: 32, width: width, height: height)
    }
}

final class IdleAnimationView: NSView {
    private let frames: [IdleFrame]
    private let walkingFrames: [IdleFrame]
    private var motion = PetMotion(x: 0, activity: .idle, facingRight: true)
    var onTick: ((TimeInterval) -> PetMotion)?
    private var poseStartedAt: CFTimeInterval = 0
    private var timer: Timer?
    private var startedAt: CFTimeInterval = 0
    private let frameDuration: CFTimeInterval = 0.4
    private let transitionDuration: CFTimeInterval = 0.12

    override var isOpaque: Bool { false }

    init(frames: [IdleFrame], walkingFrames: [IdleFrame]) {
        precondition(!frames.isEmpty && walkingFrames.count == WalkCycle.count)
        self.frames = frames
        self.walkingFrames = walkingFrames
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    }

    required init?(coder: NSCoder) { nil }

    func start() {
        stop()
        startedAt = CACurrentMediaTime()
        poseStartedAt = startedAt
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = CACurrentMediaTime()
            if let next = self.onTick?(now - self.startedAt) {
                if next.activity != self.motion.activity || next.facingRight != self.motion.facingRight {
                    self.poseStartedAt = now
                }
                self.motion = next
            }
            self.needsDisplay = true
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        needsDisplay = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high
        guard motion.activity != .hidden else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: 100, yBy: 100)
        transform.rotate(byDegrees: motion.rotation)
        transform.scaleX(by: motion.facingRight ? 1 : -1, yBy: 1)
        transform.translateX(by: -100, yBy: -100)
        transform.concat()

        if motion.activity == .peeking {
            let head = frames[3]
            head.image.draw(in: head.drawingRect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
        // Derive the frame from a monotonic clock so delayed redraws cannot
        // accumulate timing drift. Include the last-to-first transition.
        let elapsed = max(0, CACurrentMediaTime() - poseStartedAt)
        if motion.activity == .walking {
            // A complete alternating-leg stride. Don't dissolve between feet:
            // overlapping planted/swinging legs would look like extra limbs.
            let frame = walkingFrames[WalkCycle.frameIndex(at: elapsed)]
            frame.image.draw(in: frame.drawingRect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
        let index = Int(elapsed / frameDuration) % frames.count
        let phase = elapsed.truncatingRemainder(dividingBy: frameDuration)
        let progress = max(0, min(1, (phase - (frameDuration - transitionDuration)) / transitionDuration))
        let blend = CGFloat(progress * progress * (3 - 2 * progress))

        // Add weighted premultiplied pixels on a cleared transparent surface,
        // preserving opacity where both poses overlap during the short dissolve.
        frames[index].image.draw(in: frames[index].drawingRect, from: .zero,
                                 operation: .plusLighter, fraction: 1 - blend)
        if blend > 0 {
            let next = frames[(index + 1) % frames.count]
            next.image.draw(in: next.drawingRect, from: .zero,
                            operation: .plusLighter, fraction: blend)
        }
    }
}

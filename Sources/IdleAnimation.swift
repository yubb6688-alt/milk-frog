import AppKit
import QuartzCore

struct IdleFrame {
    let image: NSImage
    let drawingRect: NSRect
    private let hitBitmap: NSBitmapImageRep

    init?(image: NSImage, targetHeight: CGFloat = 132) {
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
        hitBitmap = NSBitmapImageRep(cgImage: cropped)

        // Match the previous on-screen size; every pose has the same height,
        // horizontal center and ground line inside the unchanged 200 × 200 window.
        let height = targetHeight
        let width = crop.width * height / crop.height
        drawingRect = NSRect(x: (200 - width) / 2, y: 32, width: width, height: height)
    }

    func contains(_ point: NSPoint) -> Bool {
        guard drawingRect.contains(point) else { return false }
        let u = (point.x - drawingRect.minX) / drawingRect.width
        let v = (point.y - drawingRect.minY) / drawingRect.height
        let x = min(hitBitmap.pixelsWide - 1, Int(u * CGFloat(hitBitmap.pixelsWide)))
        let y = min(hitBitmap.pixelsHigh - 1, Int((1 - v) * CGFloat(hitBitmap.pixelsHigh)))
        return (hitBitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1
    }
}

final class IdleAnimationView: NSView {
    private let frames: [IdleFrame]
    private let walkingFrames: [IdleFrame]
    private let heldFrames: [IdleFrame]
    private let workingFrames: [IdleFrame]
    private let cheeringFrames: [IdleFrame]
    var onGreeting: (() -> Void)?
    var onChat: (() -> Void)?
    var onTogglePause: (() -> Void)?
    private var clock = AnimationClock()
    var isPaused: Bool { clock.isPaused }
    private var animationNow: TimeInterval { clock.now(at: CACurrentMediaTime()) }

    func setPaused(_ value: Bool) {
        if value { finishDrag(allowClickReaction: false) }
        clock.setPaused(value, at: CACurrentMediaTime())
        needsDisplay = true
    }
    private var dragSession = PetDragSession()
    var onDrop: ((NSPoint, TimeInterval) -> Void)?
    private var motion = PetMotion(x: 0, activity: .idle, facingRight: true)
    var onTick: ((TimeInterval) -> PetMotion)?
    private var poseStartedAt: CFTimeInterval = 0
    private var workingTransitionFrom: Int?
    private var workingTransitionAt: CFTimeInterval = 0
    private var timer: Timer?
    private var startedAt: CFTimeInterval = 0
    private let frameDuration: CFTimeInterval = 0.4
    private let transitionDuration: CFTimeInterval = 0.12

    override var isOpaque: Bool { false }

    init(frames: [IdleFrame], walkingFrames: [IdleFrame], heldFrames: [IdleFrame], workingFrames: [IdleFrame], cheeringFrames: [IdleFrame]) {
        precondition(!frames.isEmpty && walkingFrames.count == WalkCycle.count && heldFrames.count == HandRaise.count
                     && workingFrames.count == TypingAnimation.count && cheeringFrames.count == 4)
        self.frames = frames
        self.walkingFrames = walkingFrames
        self.heldFrames = heldFrames
        self.workingFrames = workingFrames
        self.cheeringFrames = cheeringFrames
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        guard containsCharacter(at: convert(event.locationInWindow, from: nil)) else { return }
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let greeting = NSMenuItem(title: "打招呼", action: #selector(greet), keyEquivalent: "")
        greeting.target = self
        menu.addItem(greeting)
        let chat = NSMenuItem(title: "聊天", action: #selector(openChat), keyEquivalent: "")
        chat.target = self
        menu.addItem(chat)
        let pause = NSMenuItem(title: isPaused ? "继续" : "暂停", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc private func greet() { onGreeting?() }
    @objc private func openChat() { onChat?() }
    @objc private func togglePause() { onTogglePause?() }

    override func mouseDown(with event: NSEvent) {
        guard !isPaused, !dragSession.isActive, let window = window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard containsCharacter(at: point) else { return }
        dragSession.begin(mouse: window.convertPoint(toScreen: event.locationInWindow),
                          windowOrigin: window.frame.origin)
        motion = PetMotion(x: window.frame.minX, activity: .held, facingRight: true)
        poseStartedAt = animationNow
        NSCursor.closedHand.push()
        needsDisplay = true
        if CommandLine.arguments.contains("--debug-drag") {
            NSLog("Drag: begin x=%.2f y=%.2f activity=held", window.frame.minX, window.frame.minY)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window,
              let origin = dragSession.update(mouse: window.convertPoint(toScreen: event.locationInWindow)) else { return }
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        finishDrag()
    }

    private func finishDrag(allowClickReaction: Bool = true) {
        guard dragSession.isActive else { return }
        let now = animationNow
        let finishClick = allowClickReaction && !dragSession.didMove
            && HandRaise.clickFrameIndex(at: now - poseStartedAt) != nil
        dragSession.end()
        NSCursor.pop()
        if let origin = window?.frame.origin {
            onDrop?(origin, now - startedAt)
            motion = PetMotion(x: origin.x, activity: finishClick ? .clicked : .idle, facingRight: true)
            if CommandLine.arguments.contains("--debug-drag") {
                NSLog("Drag: end x=%.2f y=%.2f activity=%@", origin.x, origin.y, motion.activity.rawValue)
            }
        }
        if !finishClick { poseStartedAt = now }
        needsDisplay = true
    }

    private func containsCharacter(at point: NSPoint) -> Bool {
        guard motion.activity != .hidden else { return false }
        let transform = NSAffineTransform()
        transform.translateX(by: 100, yBy: 100)
        transform.rotate(byDegrees: motion.rotation)
        transform.scaleX(by: motion.facingRight ? 1 : -1, yBy: 1)
        transform.translateX(by: -100, yBy: -100)
        transform.invert()
        let point = transform.transform(point)
        let elapsed = max(0, animationNow - poseStartedAt)
        switch motion.activity {
        case .walking:
            return walkingFrames[WalkCycle.frameIndex(at: elapsed)].contains(point)
        case .peeking:
            return frames[3].contains(point)
        case .held:
            return heldFrames[HandRaise.heldFrameIndex(at: elapsed)].contains(point)
        case .clicked:
            return heldFrames[HandRaise.clickFrameIndex(at: elapsed) ?? 0].contains(point)
        case .working:
            return workingFrames[motion.spriteIndex].contains(point)
        case .celebrating:
            return cheeringFrames[motion.spriteIndex].contains(point)
        default:
            let index = Int(elapsed / frameDuration) % frames.count
            return frames[index].contains(point) || frames[(index + 1) % frames.count].contains(point)
        }
    }

    func start() {
        stop()
        startedAt = animationNow
        poseStartedAt = startedAt
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            let now = self.animationNow
            let finishingClick = self.motion.activity == .clicked
                && HandRaise.clickFrameIndex(at: now - self.poseStartedAt) != nil
            if !self.dragSession.isActive && !finishingClick, let next = self.onTick?(now - self.startedAt) {
                if self.motion.activity == .clicked, CommandLine.arguments.contains("--debug-drag") {
                    NSLog("Click: complete activity=%@", next.activity.rawValue)
                }
                if next.activity != self.motion.activity || next.facingRight != self.motion.facingRight {
                    self.poseStartedAt = now
                }
                if next.activity == .working && self.motion.activity == .working {
                    if next.spriteIndex != self.motion.spriteIndex
                        && (next.spriteIndex == TypingAnimation.thinkingIndex
                            || self.motion.spriteIndex == TypingAnimation.thinkingIndex) {
                        self.workingTransitionFrom = self.motion.spriteIndex
                        self.workingTransitionAt = now
                    }
                } else {
                    self.workingTransitionFrom = nil
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
        finishDrag(allowClickReaction: false)
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
        if motion.activity == .held || motion.activity == .clicked {
            let elapsed = animationNow - poseStartedAt
            let held = motion.activity == .held
            let index = held ? HandRaise.heldFrameIndex(at: elapsed) : (HandRaise.clickFrameIndex(at: elapsed) ?? 0)
            let pose = held ? HeldPose.sample(at: elapsed) : HeldPose(angle: 0, offset: .zero)
            let anchor = dragSession.grabOffset ?? NSPoint(x: 100, y: 120)
            let struggle = NSAffineTransform()
            struggle.translateX(by: anchor.x + pose.offset.x, yBy: anchor.y + pose.offset.y)
            struggle.rotate(byDegrees: pose.angle)
            struggle.translateX(by: -anchor.x, yBy: -anchor.y)
            struggle.concat()
            let frame = heldFrames[index]
            frame.image.draw(in: frame.drawingRect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
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
        if motion.activity == .working {
            let frame = workingFrames[motion.spriteIndex]
            let progress = min(1, max(0, (animationNow - workingTransitionAt) / 0.14))
            if let previous = workingTransitionFrom, progress < 1 {
                let old = workingFrames[previous]
                old.image.draw(in: old.drawingRect, from: .zero, operation: .plusLighter, fraction: 1 - progress)
                frame.image.draw(in: frame.drawingRect, from: .zero, operation: .plusLighter, fraction: progress)
            } else {
                frame.image.draw(in: frame.drawingRect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return
        }
        if motion.activity == .celebrating {
            let frame = cheeringFrames[motion.spriteIndex]
            frame.image.draw(in: frame.drawingRect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
        // Derive the frame from a monotonic clock so delayed redraws cannot
        // accumulate timing drift. Include the last-to-first transition.
        let elapsed = max(0, animationNow - poseStartedAt)
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

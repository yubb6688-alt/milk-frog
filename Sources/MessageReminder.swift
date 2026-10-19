import AppKit
import QuartzCore

// A local demo only. It does not read notifications or messages from other apps.
enum MessageCelebration {
    static let duration: TimeInterval = 6
    static let sequence = [0, 2, 1, 2, 3, 2, 1, 2, 3]

    static func frameIndex(at elapsed: TimeInterval) -> Int {
        guard elapsed < 3.6 else { return 3 }
        return sequence[Int(max(0, elapsed) / 0.20) % sequence.count]
    }

    static func overlayFrame(pet: NSRect) -> NSRect {
        NSRect(x: pet.midX - 150, y: pet.minY, width: 300, height: 278)
    }
}

final class MessageReminderController {
    private weak var petWindow: NSWindow?
    private let window: NSWindow
    private let content = MessageReminderView(frame: NSRect(x: 0, y: 0, width: 300, height: 278))
    private var timer: Timer?
    private var startedAt: CFTimeInterval?
    private var clock = AnimationClock()
    private var now: TimeInterval { clock.now(at: CACurrentMediaTime()) }
    var isActive: Bool { startedAt.map { now - $0 < MessageCelebration.duration } ?? false }
    var isCelebrating: Bool { isActive && content.celebrates }

    func setPaused(_ value: Bool) {
        clock.setPaused(value, at: CACurrentMediaTime())
    }
    var frameIndex: Int { MessageCelebration.frameIndex(at: elapsed) }
    private var elapsed: TimeInterval { startedAt.map { now - $0 } ?? 0 }

    init(petWindow: NSWindow) {
        self.petWindow = petWindow
        window = NSWindow(contentRect: MessageCelebration.overlayFrame(pet: petWindow.frame),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.title = "奶蛙消息提醒"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = content
    }

    func show(message: String, title: String = "新消息来啦！", celebrates: Bool = true) {
        timer?.invalidate()
        startedAt = now
        content.message = message
        content.heading = title
        content.celebrates = celebrates
        if let petWindow { petWindow.addChildWindow(window, ordered: .above) }
        refresh()
        window.orderFrontRegardless()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard isActive, let petWindow else { stop(); return }
        window.setFrame(MessageCelebration.overlayFrame(pet: petWindow.frame), display: false)
        content.elapsed = elapsed
        // The bubble fades, but neither the pet nor the overlay changes scale.
        window.alphaValue = clock.isPaused ? 1 : min(1, elapsed / 0.15, (MessageCelebration.duration - elapsed) / 0.35)
        content.needsDisplay = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        petWindow?.removeChildWindow(window)
        window.orderOut(nil)
    }

    deinit { timer?.invalidate() }
}

final class MessageReminderView: NSView {
    var message = "你有一条新消息，记得看看哦！"
    var heading = "新消息来啦！"
    var celebrates = true
    var elapsed: TimeInterval = 0
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let bubble = NSRect(x: 20, y: 184, width: 260, height: 82)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor(calibratedRed: 1, green: 0.98, blue: 0.90, alpha: 1).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 18, yRadius: 18).fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 139, y: 186))
        tail.line(to: NSPoint(x: 150, y: 174))
        tail.line(to: NSPoint(x: 161, y: 186))
        tail.close()
        tail.fill()
        NSGraphicsContext.restoreGraphicsState()
        (heading as NSString).draw(at: NSPoint(x: 38, y: 235), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.13, alpha: 1)
        ])
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (message as NSString).draw(in: NSRect(x: 38, y: 197, width: 224, height: 33), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray,
            .paragraphStyle: paragraph
        ])

        // Two short showers of petals originate beside the raised hands.
        // Deterministic particles avoid jitter between redraws.
        guard celebrates else { return }
        let colors: [NSColor] = [.systemPink, .systemOrange, .systemYellow, .systemMint, .systemPurple]
        for burst in 0..<2 {
            for i in 0..<28 {
                let age = elapsed - Double(burst) * 1.8 - Double(i % 7) * 0.035 - 0.25
                guard age >= 0 && age < 1.7 else { continue }
                let side: CGFloat = i % 2 == 0 ? -1 : 1
                let vx = side * CGFloat(18 + (i * 17) % 50)
                let vy = CGFloat(66 + (i * 23) % 70)
                let t = CGFloat(age)
                let point = NSPoint(x: 150 + side * 43 + vx * t,
                                    y: 132 + vy * t - 90 * t * t)
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: point.x, yBy: point.y)
                transform.rotate(byDegrees: CGFloat(i * 29) + t * 140)
                transform.concat()
                colors[i % colors.count].withAlphaComponent(min(1, (1.7 - age) / 0.4)).setFill()
                NSBezierPath(ovalIn: NSRect(x: -2, y: -4, width: 4, height: 8)).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

import AppKit

@main
struct TypingTests {
    static func main() throws {
        var input = TypingActivity()
        input.recordStroke(at: 0)
        assert(!input.snapshot(at: 0).focused && input.snapshot(at: 0).frameIndex == 0)
        input.setFocused(true)
        assert(input.snapshot(at: 1).focused && input.snapshot(at: 1).frameIndex == 0)
        for (index, time) in [1.0, 1.1, 1.2, 1.3].enumerated() {
            input.recordStroke(at: time)
            assert(input.snapshot(at: time + 0.01).frameIndex == (index % 2 == 0 ? 2 : 4))
        }
        assert(input.snapshot(at: 1.6).frameIndex == 0 && input.snapshot(at: 1.6).focused)
        input.setFocused(false)
        assert(!input.snapshot(at: 1.7).focused && input.snapshot(at: 1.7).frameIndex == 0)
        input.setFocused(true)
        input.recordStroke(at: 2)
        assert(input.snapshot(at: 2).frameIndex == 2)
        assert(input.snapshot(at: 2.12).frameIndex == 1)
        assert(input.snapshot(at: 2.21).frameIndex == 0)
        input.recordStroke(at: 3)
        assert(input.snapshot(at: 3).frameIndex == 4)
        assert(input.snapshot(at: 3.12).frameIndex == 3)
        assert(input.snapshot(at: 3.21).frameIndex == 0)
        assert(input.snapshot(at: 4.19).frameIndex == 0)
        assert(input.snapshot(at: 4.21).frameIndex == TypingAnimation.thinkingIndex)
        assert(input.snapshot(at: 30).frameIndex == TypingAnimation.thinkingIndex)
        input.recordStroke(at: 30)
        assert(input.snapshot(at: 30).frameIndex == 2, "Resume typing immediately leaves thinking")
        input.setFocused(false)
        assert(input.snapshot(at: 40).frameIndex == 0 && !input.snapshot(at: 40).focused)
        input.setFocused(true)
        assert(input.snapshot(at: 50).frameIndex == 0, "Focus alone must not reuse an old thinking timer")
        print("PASS: 1.2s typing pause enters thinking; short pauses rest hands; typing resumes immediately; blur clears thinking")
        print("PASS: focus takes out laptop; each keystroke alternates hands; stopped typing rests hands; lost focus stops work")

        let screen = NSRect(x: 100, y: 0, width: 1280, height: 800)
        let inPlace = TypingApproach(startX: 600, screen: screen, at: 10)
        let sitting = inPlace.sample(at: 10, frameIndex: 1)
        assert(inPlace.duration == 0 && sitting.activity == .working && sitting.x == 600)
        for x: CGFloat in [-108, 50, 1300, 1388, 3000] {
            let plan = TypingApproach(startX: x, screen: screen, at: 10)
            assert(plan.duration > 0 && plan.duration <= 0.65)
            let start = plan.sample(at: 10, frameIndex: 0)
            assert(start.activity == .walking && start.x == x)
            assert(start.facingRight == (plan.targetX > x))
            let midway = plan.sample(at: 10 + plan.duration / 2, frameIndex: 2)
            assert(midway.activity == .walking)
            let finish = plan.sample(at: 10 + plan.duration + 0.001, frameIndex: 2)
            assert(finish.activity == .working && finish.spriteIndex == 2)
            assert(finish.x >= screen.minX + 8 && finish.x + 200 <= screen.maxX - 8)
        }
        print("PASS: moving pet sits exactly in place; both screen edges return inward before sitting; entry takes at most 0.65 s")

        _ = NSApplication.shared
        let frames = TypingAnimation.load(from: URL(fileURLWithPath: CommandLine.arguments[1]),
                                          thinkingURL: URL(fileURLWithPath: CommandLine.arguments[2]))
        assert(frames.count == 6 && Set(frames.compactMap { $0.image.tiffRepresentation }).count == 6)
        let reference = NSBitmapImageRep(data: frames[0].image.tiffRepresentation!)!
        for index in 1..<TypingAnimation.typingCount {
            let pressed = NSBitmapImageRep(data: frames[index].image.tiffRepresentation!)!
            assert(frames[index].drawingRect == frames[0].drawingRect)
            assert(pressed.pixelsWide == reference.pixelsWide && pressed.pixelsHigh == reference.pixelsHigh)
            var changed = 0
            for y in 0..<reference.pixelsHigh {
                for x in 0..<reference.pixelsWide {
                    let before = reference.colorAt(x: x, y: y)!
                    let after = pressed.colorAt(x: x, y: y)!
                    if before != after {
                        changed += 1
                        let point = CGPoint(x: Double(x) / Double(reference.pixelsWide),
                                            y: Double(y) / Double(reference.pixelsHigh))
                        assert(TypingAnimation.handWeight(at: point, hand: (index - 1) / 2) > 0,
                               "Head, body, laptop screen and chassis must remain pixel-identical")
                        let rgb = after.usingColorSpace(.genericRGB)!
                        assert(rgb.redComponent > rgb.blueComponent * 1.3 && rgb.greenComponent > rgb.blueComponent * 1.18,
                               "Only a yellow fingertip may cover a key; laptop pixels must never move: \(before) -> \(after)")
                    }
                }
            }
            assert(changed > 100, "Each hand needs a visible press pose")
            assert(changed < reference.pixelsWide * reference.pixelsHigh / 20)
        }
        print("PASS: fixed laptop/body pixels, identical drawing bounds, and isolated alternating hand presses")
        let thinkingFrame = frames[TypingAnimation.thinkingIndex]
        let thinking = NSBitmapImageRep(data: thinkingFrame.image.tiffRepresentation!)!
        assert(thinkingFrame.drawingRect == frames[0].drawingRect)
        assert(thinking.pixelsWide == reference.pixelsWide && thinking.pixelsHigh == reference.pixelsHigh)
        var changedThinking = 0
        for y in 0..<reference.pixelsHigh {
            for x in 0..<reference.pixelsWide {
                let before = reference.colorAt(x: x, y: y)!
                let after = thinking.colorAt(x: x, y: y)!
                if before != after {
                    changedThinking += 1
                    assert(ThinkingPose.weight(x: Double(x) / Double(reference.pixelsWide),
                                               y: Double(y) / Double(reference.pixelsHigh)) > 0,
                           "Thinking must not change head/body/feet or pixels outside the arm patch")
                    assert(!ThinkingPose.protectsLaptop(x: Double(x) / Double(reference.pixelsWide),
                                                       y: Double(y) / Double(reference.pixelsHigh)),
                           "Existing laptop pixels must remain identical")
                }
            }
        }
        assert(changedThinking > 1000 && changedThinking < reference.pixelsWide * reference.pixelsHigh / 8)
        try thinking.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "/tmp/milkfrog-thinking-fixed.png"))
        print("PASS: thinking changes only the arm patch; head, body, visible laptop pixels, feet, size and drawing bounds stay identical")
        let preview = NSImage(size: NSSize(width: 1200, height: 200))
        preview.lockFocus()
        NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 200).fill()
        for (index, frame) in frames.enumerated() {
            assert(frame.drawingRect.height == 120 && frame.drawingRect.minY == 32)
            assert(NSRect(x: 0, y: 0, width: 200, height: 200).contains(frame.drawingRect))
            frame.image.draw(in: frame.drawingRect.offsetBy(dx: CGFloat(index) * 200, dy: 0))
        }
        preview.unlockFocus()
        let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "/tmp/milkfrog-typing-preview.png"))
        print("PASS: neutral/left/right keyboard frames load, share size/ground line, and fit the transparent window")
    }
}

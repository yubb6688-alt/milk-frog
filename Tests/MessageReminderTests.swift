import AppKit

@main
struct MessageReminderTests {
    static func main() throws {
        _ = NSApplication.shared
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let frames = (1...4).map { index -> IdleFrame in
            let url = source.appendingPathComponent(String(format: "cheer_%02d.png", index))
            return IdleFrame(image: NSImage(contentsOf: url)!)!
        }
        for frame in frames {
            assert(frame.drawingRect.height == 132 && frame.drawingRect.minY == 32)
            assert(NSRect(x: 0, y: 0, width: 200, height: 200).contains(frame.drawingRect))
        }
        assert(MessageCelebration.frameIndex(at: 0) == 0)
        assert(MessageCelebration.frameIndex(at: 0.21) == 2)
        assert(MessageCelebration.frameIndex(at: 0.41) == 1)
        assert(MessageCelebration.frameIndex(at: 5.9) == 3)
        let pet = PetWindow(contentRect: NSRect(x: 200, y: 200, width: 200, height: 200),
                            styleMask: .borderless, backing: .buffered, defer: false)
        pet.isReleasedWhenClosed = false
        let original = pet.frame
        let controller = MessageReminderController(petWindow: pet)
        controller.show(message: "演示消息")
        assert(controller.isActive && pet.frame == original)
        assert(pet.childWindows?.count == 1)
        let overlay = pet.childWindows![0]
        assert(overlay.ignoresMouseEvents && !overlay.isOpaque)
        assert(overlay.frame == MessageCelebration.overlayFrame(pet: pet.frame))
        controller.show(message: "第二条演示消息")
        assert(pet.childWindows?.count == 1 && pet.frame == original)
        controller.stop()
        assert(!controller.isActive && (pet.childWindows?.isEmpty ?? true))
        assert(pet.frame == original)
        controller.setPaused(true)
        controller.show(message: "呱呱呱", title: "奶蛙说", celebrates: false)
        assert(controller.isActive && !controller.isCelebrating)
        let greetingWindow = pet.childWindows![0]
        let greetingView = greetingWindow.contentView as! MessageReminderView
        assert(greetingWindow.isVisible && greetingWindow.alphaValue == 1)
        assert(greetingView.message == "呱呱呱" && greetingView.heading == "奶蛙说")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        assert(greetingView.elapsed == 0, "Paused overlay animation must also freeze")
        controller.setPaused(false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        assert(greetingView.elapsed > 0)
        controller.stop()
        print("PASS: greeting shows exact text without celebration, remains visible while paused, and resumes its timer")
        print("PASS: 200×200 pet unchanged; all happy poses at 132px; overlay is separate, click-through, repeatable and dismissible")

        let preview = NSImage(size: NSSize(width: 900, height: 278))
        preview.lockFocus()
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 900, height: 278).fill()
        for (i, time) in [0.0, 0.55, 2.35].enumerated() {
            NSGraphicsContext.saveGraphicsState()
            let shift = NSAffineTransform()
            shift.translateX(by: CGFloat(i) * 300, yBy: 0)
            shift.concat()
            let pose = frames[MessageCelebration.frameIndex(at: time)]
            pose.image.draw(in: pose.drawingRect.offsetBy(dx: 50, dy: 0))
            let overlayView = MessageReminderView(frame: NSRect(x: 0, y: 0, width: 300, height: 278))
            overlayView.elapsed = time
            let image = NSImage(size: overlayView.frame.size)
            image.lockFocus()
            overlayView.draw(overlayView.bounds)
            image.unlockFocus()
            image.draw(in: overlayView.frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        preview.unlockFocus()
        let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/milkfrog-message-preview.png"))
        print("PASS: generated ready/throw/celebrate preview with bubble above head")
    }
}

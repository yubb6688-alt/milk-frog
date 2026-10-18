import AppKit

@main
struct HandRaiseTests {
    static func main() throws {
        let clickFrames = (0..<6).map {
            HandRaise.clickFrameIndex(at: (Double($0) + 0.5) * HandRaise.frameDuration)!
        }
        assert(clickFrames == [0, 1, 2, 2, 1, 0])
        assert(HandRaise.clickFrameIndex(at: 0.01) == 0)
        assert(HandRaise.clickFrameIndex(at: 0.35) == 2)
        assert(HandRaise.clickFrameIndex(at: HandRaise.clickDuration) == nil)
        assert(HandRaise.heldFrameIndex(at: 0) == 0)
        assert(HandRaise.heldFrameIndex(at: 0.2) == 1)
        assert(HandRaise.heldFrameIndex(at: 100) == 2)
        print("PASS: quick tap plays all 3 poses before ending; a long hold keeps hands raised")

        var drag = PetDragSession()
        drag.begin(mouse: NSPoint(x: 100, y: 100), windowOrigin: .zero)
        _ = drag.update(mouse: NSPoint(x: 101, y: 101))
        assert(!drag.didMove, "Small click jitter must not cancel the reaction")
        _ = drag.update(mouse: NSPoint(x: 130, y: 140))
        assert(drag.didMove)
        _ = drag.update(mouse: NSPoint(x: 100, y: 100))
        assert(drag.didMove, "A drag back to its starting point is still a drag")
        drag.end()
        drag.begin(mouse: .zero, windowOrigin: .zero)
        assert(!drag.didMove)
        print("PASS: click jitter, drag release, and repeated presses are distinguished")

        _ = NSApplication.shared
        let frames = HandRaise.load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
        assert(frames.count == 3)
        assert(Set(frames.compactMap { $0.image.tiffRepresentation }).count == 3)
        let preview = NSImage(size: NSSize(width: 600, height: 200))
        preview.lockFocus()
        NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 600, height: 200).fill()
        for (index, frame) in frames.enumerated() {
            assert(frame.drawingRect.height == 132 && frame.drawingRect.minY == 32)
            assert(frame.drawingRect.minX > 10 && frame.drawingRect.maxX < 190)
            assert(frame.contains(NSPoint(x: 100, y: 100)))
            frame.image.draw(in: frame.drawingRect.offsetBy(dx: CGFloat(index) * 200, dy: 0))
        }
        preview.unlockFocus()
        let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "/tmp/milkfrog-hands-preview.png"))
        print("PASS: three distinct images; matching height and baseline; hands fit inside canvas; body remains clickable")
    }
}

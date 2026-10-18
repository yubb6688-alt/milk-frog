import AppKit

@main
struct WalkCycleTests {
    static func main() throws {
        _ = NSApplication.shared
        let baseURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let passingURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let frames = WalkCycle.load(from: baseURL, passingFramesURL: passingURL)
        assert(frames.count == 10)
        let original = WalkCycle.loadSheet(from: baseURL, columns: 4, rows: 2)
        let originalPositions = [0, 2, 3, 4, 5, 6, 7, 9]
        for (index, position) in originalPositions.enumerated() {
            assert(frames[position].image.tiffRepresentation == original[index].image.tiffRepresentation,
                   "Original feet and arm-swing frames must remain unchanged")
        }
        assert(abs(Double(frames.count) * WalkCycle.frameDuration - 0.64) < 0.000001)
        for cycle in 0..<3 {
            let actual = (0..<10).map { index in
                WalkCycle.frameIndex(at: (Double(cycle * 10 + index) + 0.5) * WalkCycle.frameDuration)
            }
            assert(actual == Array(0..<10), "Each loop must include both passing frames in order")
        }
        for frame in frames {
            assert(frame.drawingRect.height == 132 && frame.drawingRect.minY == 32)
            assert(abs(frame.drawingRect.midX - 100) < 0.001)
            assert(NSRect(x: 0, y: 0, width: 200, height: 200).contains(frame.drawingRect))
            let ratio = frame.image.size.width / frame.image.size.height
            assert(abs(frame.drawingRect.width / frame.drawingRect.height - ratio) < 0.001)
        }
        let missingURL = URL(fileURLWithPath: "/nonexistent/walk.png")
        assert(WalkCycle.load(from: missingURL, passingFramesURL: passingURL).isEmpty)
        assert(WalkCycle.load(from: baseURL, passingFramesURL: missingURL).isEmpty)
        let preview = NSImage(size: NSSize(width: 1000, height: 400))
        preview.lockFocus()
        NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 400).fill()
        for (index, frame) in frames.enumerated() {
            let x = CGFloat(index % 5) * 200
            let y = CGFloat(1 - index / 5) * 200
            frame.image.draw(in: frame.drawingRect.offsetBy(dx: x, dy: y))
            "\(index + 1)".draw(at: NSPoint(x: x + 8, y: y + 180),
                               withAttributes: [.foregroundColor: NSColor.black])
        }
        preview.unlockFocus()
        let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "/tmp/milkfrog-walk-v4-preview.png"))
        print("PASS: 10 frames with 2 passing poses; original 8 preserved; 0.64-second stride preserved; fixed height/baseline; proportional rendering; missing assets handled.")
    }
}

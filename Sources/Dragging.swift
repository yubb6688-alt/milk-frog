import AppKit

struct PetDragSession {
    private(set) var grabOffset: NSPoint?
    private var startOrigin: NSPoint?
    private(set) var didMove = false
    var isActive: Bool { grabOffset != nil }

    mutating func begin(mouse: NSPoint, windowOrigin: NSPoint) {
        grabOffset = NSPoint(x: mouse.x - windowOrigin.x, y: mouse.y - windowOrigin.y)
        startOrigin = windowOrigin
        didMove = false
    }

    func windowOrigin(for mouse: NSPoint) -> NSPoint? {
        guard let offset = grabOffset else { return nil }
        return NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y)
    }

    mutating func update(mouse: NSPoint) -> NSPoint? {
        guard let origin = windowOrigin(for: mouse), let start = startOrigin else { return nil }
        let dx = origin.x - start.x
        let dy = origin.y - start.y
        didMove = didMove || dx * dx + dy * dy > 16
        return origin
    }

    mutating func end() {
        grabOffset = nil
        startOrigin = nil
        didMove = false
    }
}

struct HeldPose {
    let angle: CGFloat
    let offset: NSPoint

    static func sample(at elapsed: TimeInterval) -> HeldPose {
        // Gentle struggling; keep the sprite's scale unchanged and its movement
        // small enough to remain inside the transparent 200 × 200 canvas.
        let phase = max(0, elapsed) * .pi * 2 * 3
        return HeldPose(angle: CGFloat(sin(phase)) * 4.5,
                        offset: NSPoint(x: CGFloat(sin(phase * 2)) * 1.2,
                                        y: CGFloat(1 - cos(phase)) * 0.9))
    }
}

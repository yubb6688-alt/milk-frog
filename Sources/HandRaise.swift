import AppKit

enum HandRaise {
    static let count = 3
    static let frameDuration: TimeInterval = 0.14
    // Three original poses, played up, briefly held, then lowered after a tap.
    static let clickSequence = [0, 1, 2, 2, 1, 0]
    static let clickDuration = Double(clickSequence.count) * frameDuration

    static func heldFrameIndex(at elapsed: TimeInterval) -> Int {
        min(count - 1, Int(max(0, elapsed) / frameDuration))
    }

    static func clickFrameIndex(at elapsed: TimeInterval) -> Int? {
        guard elapsed < clickDuration else { return nil }
        return clickSequence[Int(max(0, elapsed) / frameDuration)]
    }

    static func load(from url: URL) -> [IdleFrame] {
        let frames = WalkCycle.loadSheet(from: url, columns: 3, rows: 1)
        return frames.count == count ? frames : []
    }
}

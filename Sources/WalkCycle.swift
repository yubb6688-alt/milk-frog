import AppKit

enum WalkCycle {
    static let count = 10
    // Keep the previous full-stride duration when adding the two passing poses.
    static let frameDuration: TimeInterval = 0.64 / Double(count)

    static func frameIndex(at elapsed: TimeInterval) -> Int {
        Int(max(0, elapsed) / frameDuration) % count
    }

    static func load(from url: URL, passingFramesURL: URL) -> [IdleFrame] {
        let original = loadSheet(from: url, columns: 4, rows: 2)
        let passing = loadSheet(from: passingFramesURL, columns: 2, rows: 1)
        guard original.count == 8, passing.count == 2 else { return [] }
        // Near leg passes between old frames 1/2; far leg passes between 7/8.
        // Reuse all eight existing frames, including their arm swing.
        return [original[0], passing[0]] + Array(original[1...6]) + [passing[1], original[7]]
    }

    static func loadSheet(from url: URL, columns: Int, rows: Int, frameHeight: CGFloat = 132) -> [IdleFrame] {
        guard let image = NSImage(contentsOf: url),
              let sheet = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        return (0..<(columns * rows)).compactMap { index in
            let column = index % columns
            let row = index / columns
            // Integer cell boundaries also handle sheets whose dimensions aren't
            // exact multiples of the grid size, without leaking neighboring cells.
            let x0 = column * sheet.width / columns
            let y0 = row * sheet.height / rows
            let x1 = (column + 1) * sheet.width / columns
            let y1 = (row + 1) * sheet.height / rows
            let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            guard let cell = sheet.cropping(to: rect) else { return nil }
            return IdleFrame(image: NSImage(cgImage: cell, size: rect.size), targetHeight: frameHeight)
        }
    }
}

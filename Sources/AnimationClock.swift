import Foundation

/// Excludes paused wall time so a resumed walk or animation cannot jump ahead.
struct AnimationClock {
    private var pausedAt: TimeInterval?
    private var pausedDuration: TimeInterval = 0
    var isPaused: Bool { pausedAt != nil }

    func now(at time: TimeInterval) -> TimeInterval {
        (pausedAt ?? time) - pausedDuration
    }

    mutating func setPaused(_ value: Bool, at time: TimeInterval) {
        guard value != isPaused else { return }
        if value {
            pausedAt = time
        } else if let pausedAt {
            pausedDuration += max(0, time - pausedAt)
            self.pausedAt = nil
        }
    }
}

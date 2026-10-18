import AppKit

enum PetActivity: String {
    case idle, walking, hidden, peeking
}

struct PetMotion {
    let x: CGFloat
    let activity: PetActivity
    let facingRight: Bool
    var rotation: CGFloat = 0
    var phase: String = "idle"
}

struct WalkingTrip {
    let origin: CGFloat
    let screen: NSRect
    let right: Bool
    let target: CGFloat
    let goesOutside: Bool
    let travelDuration: TimeInterval

    init(origin: CGFloat, screen: NSRect, right: Bool, distance: CGFloat, speed: CGFloat = 150) {
        self.origin = origin
        self.screen = screen
        self.right = right
        let proposed = origin + (right ? distance : -distance)
        goesOutside = proposed < screen.minX || proposed + 200 > screen.maxX
        target = goesOutside ? (right ? screen.maxX + 8 : screen.minX - 208) : proposed
        travelDuration = Double(abs(target - origin) / speed)
    }

    // 0.35 s hidden, 0.45 s reveal, 1.2 s looking, 0.35 s retract.
    var intermission: TimeInterval { goesOutside ? 2.35 : 0.35 }
    var duration: TimeInterval { travelDuration * 2 + intermission }

    func sample(at elapsed: TimeInterval) -> PetMotion {
        let t = max(0, elapsed)
        if t >= duration {
            return PetMotion(x: origin, activity: .idle, facingRight: true)
        }
        if t < travelDuration {
            return PetMotion(x: origin + (target - origin) * CGFloat(t / travelDuration),
                             activity: .walking, facingRight: right, phase: "outbound")
        }
        let pause = t - travelDuration
        if pause < intermission {
            if !goesOutside {
                return PetMotion(x: target, activity: .idle, facingRight: !right, phase: "turn")
            }
            let angle: CGFloat = right ? 90 : -90
            let peekX = right ? screen.maxX - 76 : screen.minX - 124
            if pause < 0.35 {
                return PetMotion(x: target, activity: .hidden, facingRight: true, rotation: angle, phase: "hidden")
            }
            let p = pause - 0.35
            let x: CGFloat
            let phase: String
            if p < 0.45 {
                x = target + (peekX - target) * ease(p / 0.45)
                phase = "peek-in"
            } else if p < 1.65 {
                // Two small bobs, with the body kept beyond the screen edge.
                let bob = CGFloat(sin((p - 0.45) / 1.2 * .pi * 4)) * 3
                x = peekX + bob
                phase = "peek-hold"
            } else {
                x = peekX + (target - peekX) * ease((p - 1.65) / 0.35)
                phase = "peek-out"
            }
            return PetMotion(x: x, activity: .peeking, facingRight: true, rotation: angle, phase: phase)
        }
        let progress = CGFloat((pause - intermission) / travelDuration)
        return PetMotion(x: target + (origin - target) * progress, activity: .walking,
                         facingRight: !right, phase: "return")
    }

    private func ease(_ value: Double) -> CGFloat {
        let t = max(0, min(1, value))
        return CGFloat(t * t * (3 - 2 * t))
    }
}

final class WanderSchedule {
    static let idleInterval: TimeInterval = 30
    private let origin: CGFloat
    private let screen: NSRect
    private var nextStart: TimeInterval
    private var trip: WalkingTrip?
    private var tripStart: TimeInterval = 0
    private var firstDirection: Bool?

    init(origin: CGFloat, screen: NSRect, demoDirection: Bool? = nil) {
        self.origin = origin
        self.screen = screen
        firstDirection = demoDirection
        nextStart = demoDirection == nil ? Self.idleInterval : 2
    }

    func sample(at elapsed: TimeInterval) -> PetMotion {
        if trip == nil, elapsed >= nextStart {
            let right = firstDirection ?? Bool.random()
            let distance: CGFloat = firstDirection != nil || Int.random(in: 0..<3) == 0
                ? screen.width + 240 : CGFloat.random(in: 280...480)
            firstDirection = nil
            trip = WalkingTrip(origin: origin, screen: screen, right: right, distance: distance)
            tripStart = elapsed
        }
        if let current = trip {
            let motion = current.sample(at: elapsed - tripStart)
            if elapsed - tripStart >= current.duration {
                trip = nil
                nextStart = elapsed + Self.idleInterval
            }
            return motion
        }
        return PetMotion(x: origin, activity: .idle, facingRight: true)
    }
}

final class PetWindow: NSWindow {
    // AppKit must allow the transparent window to move fully past an edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

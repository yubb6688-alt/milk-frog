import AppKit

@main
struct WanderingTests {
    static func main() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        for right in [false, true] {
            for distance: CGFloat in [280, 1800] {
                let trip = WalkingTrip(origin: 620, screen: screen, right: right, distance: distance)
                let outbound = trip.sample(at: trip.travelDuration / 2)
                assert(outbound.activity == .walking && outbound.facingRight == right)
                let returning = trip.sample(at: trip.travelDuration + trip.intermission + trip.travelDuration / 2)
                assert(returning.activity == .walking && returning.facingRight != right)
                assert(abs(returning.x - outbound.x) < 0.001)
                let end = trip.sample(at: trip.duration)
                assert(end.activity == .idle && end.x == trip.origin)
                assert(trip.sample(at: trip.duration + 100).x == trip.origin)

                var previous = trip.sample(at: 0)
                for tick in 1...Int(ceil(trip.duration * 120)) {
                    let current = trip.sample(at: Double(tick) / 120)
                    if current.activity == .walking && previous.activity == .walking {
                        let dx = current.x - previous.x
                        assert(current.facingRight ? dx >= -0.001 : dx <= 0.001)
                        assert(abs(dx) <= 150.0 / 120.0 + 0.001)
                    }
                    previous = current
                }
                if trip.goesOutside {
                    assert(right ? trip.target > screen.maxX : trip.target + 200 < screen.minX)
                    assert(trip.sample(at: trip.travelDuration + 0.1).activity == .hidden)
                    let peek = trip.sample(at: trip.travelDuration + 0.8)
                    assert(peek.activity == .peeking)
                    assert(peek.rotation == (right ? 90 : -90))
                    // The rotated crown is visible but the body baseline remains outside.
                    assert(right ? peek.x + 36 < screen.maxX : peek.x + 164 > screen.minX)
                    assert(right ? peek.x + 168 > screen.maxX : peek.x + 32 < screen.minX)
                } else {
                    assert(trip.sample(at: trip.travelDuration + 0.1).phase == "turn")
                }
                print("PASS: \(right ? "right" : "left"), \(trip.goesOutside ? "offscreen + peek" : "onscreen"), exact return")
            }
        }
        let schedule = WanderSchedule(origin: 620, screen: screen)
        assert(schedule.sample(at: 0).activity == .idle)
        assert(schedule.sample(at: 29.999).activity == .idle)
        assert(schedule.sample(at: 30).activity == .walking)
        // Even a late timer tick/sleep must settle exactly at home, then wait again.
        assert(schedule.sample(at: 1000).x == 620)
        assert(schedule.sample(at: 1029.999).activity == .idle)
        assert(schedule.sample(at: 1030).activity == .walking)
        print("PASS: 30-second idle interval, late timer recovery, next walk scheduling")
    }
}

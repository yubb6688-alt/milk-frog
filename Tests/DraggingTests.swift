import AppKit

@main
struct DraggingTests {
    static func main() {
        var drag = PetDragSession()
        assert(!drag.isActive && drag.windowOrigin(for: .zero) == nil)
        drag.begin(mouse: NSPoint(x: 1110, y: 220), windowOrigin: NSPoint(x: 1040, y: 120))
        assert(drag.isActive)
        assert(drag.windowOrigin(for: NSPoint(x: 1110, y: 220)) == NSPoint(x: 1040, y: 120))
        assert(drag.windowOrigin(for: NSPoint(x: 810, y: 420)) == NSPoint(x: 740, y: 320))
        assert(drag.windowOrigin(for: NSPoint(x: -110, y: 420)) == NSPoint(x: -180, y: 320))
        drag.end()
        assert(!drag.isActive && drag.windowOrigin(for: .zero) == nil)
        print("PASS: mouse grab offset preserved; both axes and negative screen coordinates; release ends dragging")

        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let schedule = WanderSchedule(origin: 1040, screen: screen, demoDirection: false)
        assert(schedule.sample(at: 2).activity == .walking)
        schedule.reset(origin: 740, screen: screen, at: 3)
        for time in [3.0, 20, 32.999] {
            let motion = schedule.sample(at: time)
            assert(motion.activity == .idle && motion.x == 740)
        }
        assert(schedule.sample(at: 33).activity == .walking)
        assert(schedule.sample(at: 1000).x == 740)
        schedule.reset(origin: -600, screen: NSRect(x: -1440, y: 0, width: 1440, height: 900), at: 1001)
        assert(schedule.sample(at: 1030.99).x == -600)
        print("PASS: dropping cancels current trip; new home persists; next walk waits 30 seconds; new monitor supported")

        assert(HeldPose.sample(at: 0).angle == 0)
        var angles = Set<Int>()
        for tick in 0..<240 {
            let pose = HeldPose.sample(at: Double(tick) / 120)
            assert(abs(pose.angle) <= 4.5 && abs(pose.offset.x) <= 1.2)
            assert(pose.offset.y >= 0 && pose.offset.y <= 1.8)
            angles.insert(Int(pose.angle * 10))
        }
        assert(angles.count > 10)
        _ = NSApplication.shared
        let image = NSImage(contentsOfFile: CommandLine.arguments[1])!
        let frame = IdleFrame(image: image)!
        assert(frame.contains(NSPoint(x: 100, y: 100)))
        assert(!frame.contains(.zero) && !frame.contains(NSPoint(x: 195, y: 195)))
        print("PASS: surprise sprite has a usable body hit area; transparent corners ignored; struggle stays subtle")
    }
}

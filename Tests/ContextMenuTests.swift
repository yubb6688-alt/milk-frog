import AppKit

@main
struct ContextMenuTests {
    static func main() {
        var clock = AnimationClock()
        assert(clock.now(at: 10) == 10)
        clock.setPaused(true, at: 12)
        assert(clock.now(at: 200) == 12)
        clock.setPaused(true, at: 210)
        clock.setPaused(false, at: 220)
        assert(clock.now(at: 221) == 13)
        clock.setPaused(false, at: 230)
        assert(clock.now(at: 231) == 23)
        clock.setPaused(true, at: 240)
        clock.setPaused(false, at: 250)
        assert(clock.now(at: 251) == 33)
        print("PASS: repeated pause/resume excludes paused time and never jumps the animation clock")

        _ = NSApplication.shared
        let frame = IdleFrame(image: NSImage(contentsOfFile: CommandLine.arguments[1])!)!
        let view = IdleAnimationView(frames: Array(repeating: frame, count: 4),
            walkingFrames: Array(repeating: frame, count: WalkCycle.count),
            heldFrames: Array(repeating: frame, count: HandRaise.count),
            workingFrames: Array(repeating: frame, count: TypingAnimation.count),
            cheeringFrames: Array(repeating: frame, count: 4))
        var chatted = false
        view.onChat = { chatted = true }
        var greeted = false
        view.onGreeting = { greeted = true }
        view.onTogglePause = { [weak view] in
            guard let view else { return }
            view.setPaused(!view.isPaused)
        }
        let menu = view.makeContextMenu()
        assert(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["打招呼", "聊天", "暂停", "退出"])
        assert(menu.items.allSatisfy { $0.view == nil }, "Menu must use native macOS rows")
        assert(menu.items.last!.action == #selector(NSApplication.terminate(_:)))
        menu.performActionForItem(at: 0)
        assert(greeted)
        menu.performActionForItem(at: 1)
        assert(chatted)
        var ticks = 0
        view.onTick = { _ in ticks += 1; return PetMotion(x: 0, activity: .idle, facingRight: true) }
        view.start()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        assert(ticks > 0)
        menu.performActionForItem(at: 2)
        let pausedTicks = ticks
        assert(view.isPaused && view.makeContextMenu().items[2].title == "继续")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        assert(ticks == pausedTicks, "Paused pet must stop updates and wandering")
        view.makeContextMenu().performActionForItem(at: 2)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        assert(!view.isPaused && ticks > pausedTicks)
        assert(view.makeContextMenu().items[2].title == "暂停")
        view.stop()
        print("PASS: native greeting/pause/continue/quit actions; no timer updates during pause; updates resume")
    }
}

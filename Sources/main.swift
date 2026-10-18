import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindow: NSWindow?
    private var idleFrames: [IdleFrame] = []
    private var animationView: IdleAnimationView?
    private var schedule: WanderSchedule?

    func applicationDidFinishLaunching(_ notification: Notification) {
        func loadFrames(_ prefix: String) -> [IdleFrame] {
            (1...4).compactMap { index in
            let name = String(format: "\(prefix)_%02d", index)
            guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
                return nil
            }
            guard let image = NSImage(contentsOf: url) else { return nil }
            return IdleFrame(image: image)
            }
        }
        idleFrames = loadFrames("scratch")
        let walkingFrames: [IdleFrame]
        if let baseURL = Bundle.main.url(forResource: "walk-cycle-v3-arms", withExtension: "png"),
           let passingURL = Bundle.main.url(forResource: "walk-passing-v4", withExtension: "png") {
            walkingFrames = WalkCycle.load(from: baseURL, passingFramesURL: passingURL)
        } else {
            walkingFrames = []
        }
        guard idleFrames.count == 4, walkingFrames.count == WalkCycle.count else {
            NSLog("奶蛙：需要完整的四帧待机、八帧走路和两帧换脚过渡素材。")
            NSApp.terminate(nil)
            return
        }

        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出奶蛙", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        NSApp.mainMenu = menu

        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        let window = PetWindow(
            contentRect: NSRect(x: frame.maxX - 240, y: frame.minY + 30, width: 200, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.title = "奶蛙"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let animationView = IdleAnimationView(frames: idleFrames, walkingFrames: walkingFrames)
        window.contentView = animationView
        window.orderFrontRegardless()
        petWindow = window

        self.animationView = animationView
        let origin = window.frame.origin
        let screenBounds = NSScreen.main?.frame ?? frame
        let demoDirection: Bool? = CommandLine.arguments.contains("--demo-right") ? true
            : (CommandLine.arguments.contains("--demo-left") ? false : nil)
        let schedule = WanderSchedule(origin: origin.x, screen: screenBounds, demoDirection: demoDirection)
        self.schedule = schedule
        var lastPhase = ""
        // Developer preview: inspect a full stride without the pet leaving the screen.
        let previewWalk = CommandLine.arguments.contains("--preview-walk")
        animationView.onTick = { [weak window] elapsed in
            let motion = previewWalk
                ? PetMotion(x: origin.x, activity: .walking, facingRight: Int(elapsed / 5) % 2 == 0)
                : schedule.sample(at: elapsed)
            window?.setFrameOrigin(NSPoint(x: motion.x, y: origin.y))
            if demoDirection != nil, motion.phase != lastPhase {
                NSLog("Motion: %@ x=%.2f facing=%@ actualX=%.2f", motion.phase, motion.x,
                      motion.facingRight ? "right" : "left", window?.frame.origin.x ?? 0)
                lastPhase = motion.phase
            }
            return motion
        }
        animationView.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        animationView?.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

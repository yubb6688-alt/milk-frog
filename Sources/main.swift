import AppKit

private final class TypingTestField: NSTextField {
    var onFocus: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var petWindow: NSWindow?
    private var idleFrames: [IdleFrame] = []
    private var animationView: IdleAnimationView?
    private var schedule: WanderSchedule?
    private var inputMonitor: InputActivityMonitor?
    private var typingTestWindow: NSWindow?

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
        let heldFrames = Bundle.main.url(forResource: "click-hands-v1", withExtension: "png")
            .map { HandRaise.load(from: $0) } ?? []
        let workingFrames = Bundle.main.url(forResource: "typing-v1", withExtension: "png")
            .map { TypingAnimation.load(from: $0) } ?? []
        guard idleFrames.count == 4, walkingFrames.count == WalkCycle.count,
              heldFrames.count == HandRaise.count, workingFrames.count == TypingAnimation.count else {
            NSLog("奶蛙：缺少待机、走路、换脚、举手或打字素材。")
            NSApp.terminate(nil)
            return
        }

        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let accessItem = NSMenuItem(title: "启用输入陪伴…", action: #selector(enableTypingAccess), keyEquivalent: "")
        accessItem.target = self
        appMenu.addItem(accessItem)
        appMenu.addItem(.separator())
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

        let animationView = IdleAnimationView(frames: idleFrames, walkingFrames: walkingFrames,
                                             heldFrames: heldFrames, workingFrames: workingFrames)
        window.contentView = animationView
        window.orderFrontRegardless()
        petWindow = window

        self.animationView = animationView
        var origin = window.frame.origin
        let screenBounds = NSScreen.main?.frame ?? frame
        var homeScreen = screenBounds
        let testMode = CommandLine.arguments.contains("--typing-test")
        if testMode, CommandLine.arguments.contains("--offscreen-right") {
            window.setFrameOrigin(NSPoint(x: screenBounds.maxX + 8, y: origin.y))
        } else if testMode, CommandLine.arguments.contains("--offscreen-left") {
            window.setFrameOrigin(NSPoint(x: screenBounds.minX - 208, y: origin.y))
        }
        let inputMonitor = InputActivityMonitor(testMode: testMode)
        self.inputMonitor = inputMonitor
        inputMonitor.onTrustChanged = { trusted in
            accessItem.title = trusted ? "输入陪伴已启用" : "启用输入陪伴…"
            NSLog("Typing access: %@", trusted ? "granted" : "required")
        }
        accessItem.title = inputMonitor.isTrusted ? "输入陪伴已启用" : "启用输入陪伴…"
        var typingApproach: TypingApproach?
        let demoDirection: Bool? = CommandLine.arguments.contains("--demo-right") ? true
            : (CommandLine.arguments.contains("--demo-left") ? false : nil)
        let schedule = WanderSchedule(origin: origin.x, screen: screenBounds, demoDirection: demoDirection)
        self.schedule = schedule
        var lastPhase = ""
        // Developer preview: inspect a full stride without the pet leaving the screen.
        let previewWalk = CommandLine.arguments.contains("--preview-walk")
        let previewHeld = CommandLine.arguments.contains("--preview-held")
        animationView.onDrop = { [weak window] newOrigin, elapsed in
            origin = newOrigin
            let center = NSPoint(x: newOrigin.x + 100, y: newOrigin.y + 100)
            let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? window?.screen ?? NSScreen.main
            homeScreen = screen?.frame ?? screenBounds
            typingApproach = nil
            schedule.reset(origin: newOrigin.x, screen: homeScreen, at: elapsed)
        }
        animationView.onTick = { [weak window] elapsed in
            let typing = inputMonitor.snapshot()
            let finishingEntry = typingApproach.map { !$0.hasArrived(at: elapsed) } ?? false
            let motion: PetMotion
            if !previewHeld && !previewWalk && (typing.focused || finishingEntry) {
                if typingApproach == nil {
                    let currentX = window?.frame.minX ?? origin.x
                    typingApproach = TypingApproach(startX: currentX, screen: homeScreen, at: elapsed)
                    schedule.reset(origin: currentX, screen: homeScreen, at: elapsed)
                }
                motion = typingApproach!.sample(at: elapsed, frameIndex: typing.frameIndex)
                if motion.activity == .working { origin.x = motion.x }
            } else {
                if typingApproach != nil {
                    origin = window?.frame.origin ?? origin
                    typingApproach = nil
                    schedule.reset(origin: origin.x, screen: homeScreen, at: elapsed)
                }
                // The test window starts with the pet outside until focus arrives.
                if testMode && (CommandLine.arguments.contains("--offscreen-left") || CommandLine.arguments.contains("--offscreen-right"))
                    && !typing.focused && lastPhase.isEmpty {
                    return PetMotion(x: window?.frame.minX ?? origin.x, activity: .idle, facingRight: true)
                }
                motion = previewHeld
                ? PetMotion(x: origin.x, activity: .held, facingRight: true)
                : previewWalk
                ? PetMotion(x: origin.x, activity: .walking, facingRight: Int(elapsed / 5) % 2 == 0)
                : schedule.sample(at: elapsed)
            }
            window?.setFrameOrigin(NSPoint(x: motion.x, y: origin.y))
            if demoDirection != nil || CommandLine.arguments.contains("--debug-typing"), motion.phase != lastPhase {
                NSLog("Motion: %@ x=%.2f facing=%@ actualX=%.2f", motion.phase, motion.x,
                      motion.facingRight ? "right" : "left", window?.frame.origin.x ?? 0)
                lastPhase = motion.phase
            }
            return motion
        }
        inputMonitor.start()
        animationView.start()
        NSLog("Typing access: %@", inputMonitor.isTrusted ? "granted" : "required")
        if testMode { showTypingTest() }
        else if !inputMonitor.isTrusted { inputMonitor.requestAccess() }
    }

    @objc private func enableTypingAccess() {
        guard let monitor = inputMonitor, !monitor.isTrusted else { return }
        monitor.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showTypingTest() {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 480, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "奶蛙输入联动测试"
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "点击下方输入框，再打字，奶蛙会同步按键。")
        label.frame = NSRect(x: 24, y: 132, width: 430, height: 24)
        let field = TypingTestField(frame: NSRect(x: 24, y: 82, width: 430, height: 32))
        field.placeholderString = "在这里测试输入"
        field.delegate = self
        field.onFocus = { [weak self] in self?.inputMonitor?.localTestFieldFocused = true }
        let stop = NSButton(title: "结束输入", target: self, action: #selector(endTypingTest))
        stop.frame = NSRect(x: 24, y: 26, width: 110, height: 32)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(field)
        window.contentView?.addSubview(stop)
        window.initialFirstResponder = stop
        typingTestWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        inputMonitor?.localTestFieldFocused = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        inputMonitor?.localTestFieldFocused = false
    }

    @objc private func endTypingTest() {
        typingTestWindow?.makeFirstResponder(nil)
        inputMonitor?.localTestFieldFocused = false
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputMonitor?.stop()
        animationView?.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindow: NSWindow?
    private var idleFrames: [IdleFrame] = []
    private var animationView: IdleAnimationView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        idleFrames = (1...4).compactMap { index in
            let name = String(format: "scratch_%02d", index)
            guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
                return nil
            }
            guard let image = NSImage(contentsOf: url) else { return nil }
            return IdleFrame(image: image)
        }
        guard idleFrames.count == 4 else {
            NSLog("奶蛙：待机动画需要 scratch_01.png 至 scratch_04.png 四张素材。")
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
        let window = NSWindow(
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

        let animationView = IdleAnimationView(frames: idleFrames)
        window.contentView = animationView
        window.orderFrontRegardless()
        petWindow = window

        self.animationView = animationView
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

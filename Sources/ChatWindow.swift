import AppKit

enum ChatStyle {
    static let cream = NSColor(calibratedRed: 1, green: 0.98, blue: 0.90, alpha: 1)
    static let paper = NSColor(calibratedRed: 1, green: 0.995, blue: 0.965, alpha: 1)
    static let yellow = NSColor(calibratedRed: 1, green: 0.87, blue: 0.43, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.36, green: 0.28, blue: 0.16, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.58, green: 0.53, blue: 0.43, alpha: 1)

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = ink
        return label
    }
}

final class ChatInputView: NSTextView {
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Let the input method finish its candidate before treating Return as send.
        if [36, 76].contains(Int(event.keyCode)), !hasMarkedText(),
           !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.option) {
            onSend?()
            return
        }
        super.keyDown(with: event)
    }
}

final class ChatTranscriptView: NSView {
    override var isFlipped: Bool { true }
    private var rows: [(ChatMessage, NSTextField, NSView, NSTextField)] = []
    private let welcomeImage = NSImageView()
    private let welcomeTitle = ChatStyle.label("想说什么，都可以。", size: 18, weight: .semibold)
    private let welcomeDetail = ChatStyle.label("从一句「你好」开始吧", size: 12)
    private(set) var messages: [ChatMessage] = []

    init(avatar: NSImage) {
        super.init(frame: .zero)
        welcomeImage.image = avatar
        welcomeImage.imageScaling = .scaleProportionallyUpOrDown
        welcomeDetail.textColor = ChatStyle.muted
        welcomeTitle.alignment = .center
        welcomeDetail.alignment = .center
        [welcomeImage, welcomeTitle, welcomeDetail].forEach(addSubview)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ messages: [ChatMessage], viewport: NSSize) {
        self.messages = messages
        if rows.count == messages.count, zip(rows, messages).allSatisfy({ $0.0.0.isUser == $0.1.isUser }) {
            for index in messages.indices {
                rows[index].0 = messages[index]
                rows[index].3.stringValue = messages[index].text.isEmpty ? "…" : messages[index].text
            }
            arrange(viewport: viewport)
            return
        }
        for (_, name, bubble, _) in rows { name.removeFromSuperview(); bubble.removeFromSuperview() }
        rows = messages.map { message in
            let name = ChatStyle.label(message.isUser ? "你" : "奶蛙", size: 11, weight: .medium)
            name.textColor = ChatStyle.muted
            name.alignment = message.isUser ? .right : .left
            let bubble = NSView()
            bubble.wantsLayer = true
            bubble.layer?.cornerRadius = 16
            bubble.layer?.backgroundColor = (message.isUser ? ChatStyle.yellow.withAlphaComponent(0.55) : NSColor.white).cgColor
            let text = ChatStyle.label(message.text.isEmpty ? "…" : message.text, size: 14)
            text.isSelectable = true
            bubble.addSubview(text)
            addSubview(name)
            addSubview(bubble)
            return (message, name, bubble, text)
        }
        arrange(viewport: viewport)
    }

    func arrange(viewport: NSSize) {
        let width = max(280, viewport.width)
        let maximum = width * 0.78
        var y: CGFloat = 12
        for (message, name, bubble, label) in rows {
            let measured = (message.text as NSString).boundingRect(with: NSSize(width: maximum - 36, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 14)])
            let bubbleWidth = min(maximum, max(66, ceil(measured.width) + 38))
            let bubbleHeight = max(42, ceil(measured.height) + 28)
            let x = message.isUser ? width - bubbleWidth - 6 : 6
            name.frame = NSRect(x: x + 3, y: y, width: bubbleWidth - 6, height: 17)
            bubble.frame = NSRect(x: x, y: y + 21, width: bubbleWidth, height: bubbleHeight)
            label.frame = NSRect(x: 14, y: 10, width: bubbleWidth - 28, height: bubbleHeight - 20)
            y += bubbleHeight + 40
        }
        setFrameSize(NSSize(width: width, height: max(viewport.height, y + 10)))
        let empty = messages.isEmpty
        [welcomeImage, welcomeTitle, welcomeDetail].forEach { $0.isHidden = !empty }
        let centerY = max(80, viewport.height * 0.38)
        welcomeImage.frame = NSRect(x: (width - 88) / 2, y: centerY - 65, width: 88, height: 88)
        welcomeTitle.frame = NSRect(x: 10, y: centerY + 35, width: width - 20, height: 28)
        welcomeDetail.frame = NSRect(x: 10, y: centerY + 68, width: width - 20, height: 24)
    }
}

final class ChatContentView: NSView, NSTextViewDelegate {
    override var isFlipped: Bool { true }
    private let avatar = NSImageView()
    private let avatarBackground = NSView()
    private let title = ChatStyle.label("和奶蛙聊聊天", size: 20, weight: .semibold)
    private let subtitle = ChatStyle.label("慢慢说，蛙蛙在呢", size: 12)
    private let divider = NSView()
    private let composer = NSView()
    private let hint = ChatStyle.label("回车发送 · Shift + 回车换行", size: 10)
    private let placeholder = ChatStyle.label("想对蛙蛙说些什么…", size: 14)
    let input = ChatInputView()
    let sendButton = NSButton(title: "发送", target: nil, action: nil)
    let transcript: ChatTranscriptView
    private let scroll = NSScrollView()
    private let inputScroll = NSScrollView()
    let session: ChatSession
    private let store: DeepSeekConfigurationStore
    private var settings: ChatSettingsController?
    let settingsButton = NSButton(title: "设置", target: nil, action: nil)

    init(avatar image: NSImage, store: DeepSeekConfigurationStore = DeepSeekConfigurationStore(), session: ChatSession = ChatSession()) {
        self.store = store
        self.session = session
        transcript = ChatTranscriptView(avatar: image)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 560))
        wantsLayer = true
        layer?.backgroundColor = ChatStyle.paper.cgColor
        avatarBackground.wantsLayer = true
        avatarBackground.layer?.backgroundColor = ChatStyle.cream.cgColor
        avatarBackground.layer?.cornerRadius = 28
        avatar.image = image
        avatar.imageScaling = .scaleProportionallyUpOrDown
        subtitle.textColor = ChatStyle.muted
        hint.textColor = ChatStyle.muted
        placeholder.textColor = ChatStyle.muted
        divider.wantsLayer = true
        divider.layer?.backgroundColor = ChatStyle.ink.withAlphaComponent(0.08).cgColor
        composer.wantsLayer = true
        composer.layer?.backgroundColor = NSColor.white.cgColor
        composer.layer?.cornerRadius = 18
        composer.layer?.borderWidth = 1
        composer.layer?.borderColor = ChatStyle.ink.withAlphaComponent(0.12).cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = transcript
        inputScroll.drawsBackground = false
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.documentView = input
        input.isRichText = false
        input.importsGraphics = false
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.allowsUndo = true
        input.font = .systemFont(ofSize: 14)
        input.textColor = ChatStyle.ink
        input.insertionPointColor = ChatStyle.ink
        input.drawsBackground = false
        input.textContainerInset = NSSize(width: 0, height: 4)
        input.textContainer?.lineFragmentPadding = 0
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.delegate = self
        input.setAccessibilityLabel("聊天输入框")
        input.onSend = { [weak self] in if self?.session.isBusy == false { self?.send() } }
        sendButton.isBordered = false
        sendButton.wantsLayer = true
        sendButton.layer?.cornerRadius = 13
        sendButton.layer?.backgroundColor = ChatStyle.yellow.cgColor
        sendButton.font = .systemFont(ofSize: 13, weight: .semibold)
        sendButton.contentTintColor = ChatStyle.ink
        sendButton.target = self
        sendButton.action = #selector(send)
        sendButton.setAccessibilityLabel("发送消息")
        [avatarBackground, avatar, title, subtitle, divider, scroll, composer, inputScroll, placeholder, sendButton, hint].forEach(addSubview)
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)
        settingsButton.bezelStyle = .rounded
        settingsButton.setAccessibilityLabel("AI 设置")
        addSubview(settingsButton)
        session.onChange = { [weak self] in self?.refreshSession() }
        refreshInputState()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height
        avatarBackground.frame = NSRect(x: 22, y: 36, width: 56, height: 56)
        avatar.frame = NSRect(x: 28, y: 41, width: 44, height: 46)
        title.frame = NSRect(x: 92, y: 41, width: width - 165, height: 29)
        settingsButton.frame = NSRect(x: width - 68, y: 41, width: 54, height: 28)
        subtitle.frame = NSRect(x: 93, y: 72, width: width - 110, height: 36)
        divider.frame = NSRect(x: 22, y: 111, width: width - 44, height: 1)
        scroll.frame = NSRect(x: 16, y: 124, width: width - 32, height: max(100, height - 252))
        transcript.arrange(viewport: scroll.contentSize)
        composer.frame = NSRect(x: 18, y: height - 112, width: width - 36, height: 78)
        inputScroll.frame = NSRect(x: 31, y: height - 101, width: width - 130, height: 55)
        input.setFrameSize(NSSize(width: inputScroll.contentSize.width, height: max(55, input.frame.height)))
        placeholder.frame = NSRect(x: 31, y: height - 97, width: width - 130, height: 22)
        sendButton.frame = NSRect(x: width - 84, y: height - 91, width: 54, height: 36)
        hint.frame = NSRect(x: 25, y: height - 25, width: width - 50, height: 18)
    }

    func textDidChange(_ notification: Notification) { refreshInputState() }

    private func refreshInputState() {
        placeholder.isHidden = !input.string.isEmpty
        sendButton.title = session.isBusy ? "停止" : "发送"
        sendButton.setAccessibilityLabel(session.isBusy ? "停止回复" : "发送消息")
        sendButton.isEnabled = session.isBusy || !input.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        settingsButton.isEnabled = !session.isBusy
        sendButton.alphaValue = sendButton.isEnabled ? 1 : 0.45
    }

    private func refreshSession() {
        subtitle.stringValue = session.status
        refreshInputState()
        let followsBottom = scroll.contentView.bounds.maxY >= transcript.bounds.height - 45
        transcript.update(session.messages, viewport: scroll.contentSize)
        if followsBottom { scrollToBottom() }
    }

    private func scrollToBottom() {
        transcript.scrollToVisible(NSRect(x: 0, y: max(0, transcript.bounds.height - 1), width: 1, height: 1))
    }

    @objc func showSettings() {
        guard !session.isBusy, let window else { return }
        if settings == nil {
            settings = ChatSettingsController(store: store)
            settings?.onSave = { [weak self] in
                self?.subtitle.stringValue = "配置已保存，可以发送消息啦"
                self?.window?.makeFirstResponder(self?.input)
            }
        }
        settings?.present(on: window)
    }

    @objc func send() {
        if session.isBusy { session.stop(); return }
        guard !input.hasMarkedText(), !input.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try session.send(input.string, configuration: store.load())
            input.string = ""
            input.undoManager?.removeAllActions()
            refreshInputState()
            scrollToBottom()
            window?.makeFirstResponder(input)
        } catch {
            subtitle.stringValue = (error as? ChatServiceError)?.localizedDescription ?? "本地配置无法读取，请重新配置。"
            showSettings()
        }
    }
}

final class ChatWindowController: NSWindowController {
    let chat: ChatContentView

    init(avatar: NSImage, store: DeepSeekConfigurationStore = DeepSeekConfigurationStore(), session: ChatSession = ChatSession()) {
        chat = ChatContentView(avatar: avatar, store: store, session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "和奶蛙聊天"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = ChatStyle.paper
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 360, height: 460)
        window.isReleasedWhenClosed = false
        window.contentView = chat
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(chat.input)
    }
}

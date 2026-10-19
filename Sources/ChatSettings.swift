import AppKit

final class ChatSettingsController: NSWindowController {
    private let key = NSSecureTextField()
    private let model = NSTextField()
    private let address = NSTextField()
    private let errorLabel = ChatStyle.label("", size: 11)
    private let store: DeepSeekConfigurationStore
    var onSave: (() -> Void)?

    init(store: DeepSeekConfigurationStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 382), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "奶蛙 · AI 设置"
        window.backgroundColor = ChatStyle.paper
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = window.contentView!
        let title = ChatStyle.label("连接 DeepSeek", size: 20, weight: .semibold)
        title.frame = NSRect(x: 24, y: 330, width: 370, height: 28)
        content.addSubview(title)
        let note = ChatStyle.label("配置仅保存在这台 Mac。密钥请直接填在这里。", size: 12)
        note.textColor = ChatStyle.muted
        note.frame = NSRect(x: 24, y: 300, width: 375, height: 22)
        content.addSubview(note)
        let fields: [(String, NSTextField, String)] = [
            ("API key", key, "输入你的 API key"),
            ("模型名称", model, "例如 deepseek-flash"),
            ("接口地址", address, "https://api.deepseek.com")
        ]
        for (index, item) in fields.enumerated() {
            let y = CGFloat(242 - index * 65)
            let label = ChatStyle.label(item.0, size: 12, weight: .medium)
            label.frame = NSRect(x: 24, y: y + 29, width: 370, height: 18)
            item.1.frame = NSRect(x: 24, y: y, width: 372, height: 26)
            item.1.placeholderString = item.2
            item.1.font = .systemFont(ofSize: 13)
            item.1.setAccessibilityLabel(item.0)
            content.addSubview(label); content.addSubview(item.1)
        }
        errorLabel.textColor = .systemRed
        errorLabel.frame = NSRect(x: 24, y: 57, width: 372, height: 46)
        content.addSubview(errorLabel)
        let cancel = NSButton(title: "取消", target: self, action: #selector(dismiss))
        cancel.frame = NSRect(x: 235, y: 18, width: 75, height: 32)
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存", target: self, action: #selector(save))
        save.frame = NSRect(x: 318, y: 18, width: 80, height: 32)
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        content.addSubview(cancel); content.addSubview(save)
    }
    required init?(coder: NSCoder) { nil }
    func present(on parent: NSWindow) {
        guard let window, window.sheetParent == nil else { return }
        do {
            let config = try store.load()
            key.stringValue = config.apiKey; model.stringValue = config.model; address.stringValue = config.baseURL
            errorLabel.stringValue = ""
        } catch { errorLabel.stringValue = "本地配置无法读取，请重新填写并保存。" }
        parent.beginSheet(window)
        window.makeFirstResponder(key)
    }
    @objc private func dismiss() {
        if let window { window.sheetParent?.endSheet(window); window.orderOut(nil) }
        key.stringValue = ""
    }
    @objc private func save() {
        let config = DeepSeekConfiguration(apiKey: key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), model: model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), baseURL: address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try store.save(config)
            dismiss(); onSave?()
        } catch let error as ChatServiceError { errorLabel.stringValue = error.localizedDescription }
        catch { errorLabel.stringValue = "无法保存配置，请检查本地文件权限。" }
    }
}

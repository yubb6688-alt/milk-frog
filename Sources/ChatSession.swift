import Foundation

struct ChatMessage {
    let isUser: Bool
    var text: String
}

final class ChatSession {
    private(set) var messages: [ChatMessage] = []
    private(set) var isBusy = false
    private(set) var status = "慢慢说，蛙蛙在呢"
    var onChange: (() -> Void)?
    private let client: ChatStreaming
    private var requestID = UUID()
    private var pending = ""
    private var receivedAll = false
    private var completionError: Error?
    private var timer: Timer?
    private var completedHistory: [ChatMessage] = []
    private var question = ""

    init(client: ChatStreaming = DeepSeekClient()) { self.client = client }
    deinit { timer?.invalidate(); client.cancel() }

    func send(_ text: String, configuration: DeepSeekConfiguration) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !text.isEmpty else { return }
        _ = try configuration.endpoint()
        isBusy = true; status = "正在连接 DeepSeek…"
        question = text; pending = ""; receivedAll = false; completionError = nil
        messages.append(ChatMessage(isUser: true, text: text))
        messages.append(ChatMessage(isUser: false, text: ""))
        requestID = UUID()
        let id = requestID
        onChange?()
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in self?.advance() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        client.start(configuration: configuration, messages: completedHistory + [ChatMessage(isUser: true, text: text)], onText: { [weak self] text in
            guard let self, self.requestID == id, self.isBusy else { return }
            self.pending += text
            self.status = "奶蛙正在回复…"
        }, onComplete: { [weak self] error in
            guard let self, self.requestID == id, self.isBusy else { return }
            self.receivedAll = true; self.completionError = error
        })
    }

    // One extended grapheme cluster per tick; emojis and Chinese remain intact.
    func advance() {
        guard isBusy else { return }
        if !pending.isEmpty {
            messages[messages.count - 1].text.append(pending.removeFirst())
            onChange?()
        } else if receivedAll {
            if let completionError { status = completionError.localizedDescription }
            else if messages.last?.text.isEmpty == true { status = "没有收到回复，请检查模型后重试。" }
            else {
                completedHistory.append(ChatMessage(isUser: true, text: question))
                completedHistory.append(messages.last!)
                status = "慢慢说，蛙蛙在呢"
            }
            finish()
        }
    }
    func stop() {
        guard isBusy else { return }
        status = "已停止回复，可以重新发送。"
        requestID = UUID(); client.cancel(); pending = ""
        finish()
    }
    private func finish() {
        if messages.last?.text.isEmpty == true { messages.removeLast() }
        isBusy = false
        timer?.invalidate(); timer = nil
        onChange?()
    }
}

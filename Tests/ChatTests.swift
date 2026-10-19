import AppKit

final class MockStream: ChatStreaming {
    var text: ((String) -> Void)?
    var complete: ((Error?) -> Void)?
    var requests: [[ChatMessage]] = []
    var cancelled = false
    func start(configuration: DeepSeekConfiguration, messages: [ChatMessage], onText: @escaping (String) -> Void, onComplete: @escaping (Error?) -> Void) {
        requests.append(messages); text = onText; complete = onComplete
    }
    func cancel() { cancelled = true }
}

final class MockProtocol: URLProtocol {
    static var status = 200
    static var body = ""
    static var observed: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.observed = request
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        // Deliberately split every UTF-8 code point across packets.
        for byte in Self.body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct ChatTests {
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("milkfrog-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeepSeekConfigurationStore(directory: directory)
        assert(try! store.load().apiKey.isEmpty)
        let config = DeepSeekConfiguration(apiKey: "test-placeholder-only", model: "test-model", baseURL: "https://example.invalid/v1")
        try store.save(config)
        try store.save(config)
        assert(try! store.load().model == config.model)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as! NSNumber
        assert(permissions.intValue == 0o600)
        assert(try! config.endpoint().absoluteString == "https://example.invalid/v1/chat/completions")
        var full = config; full.baseURL = "https://example.invalid/chat/completions"
        assert(try! full.endpoint().absoluteString == full.baseURL)
        var unsafe = config; unsafe.baseURL = "http://example.invalid"
        do { _ = try unsafe.endpoint(); assertionFailure() } catch {}
        print("PASS: local configuration round-trip, private permissions, configurable HTTPS endpoint")

        let stream = ": keepalive\r\n\r\ndata: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\r\n\r\ndata: {\"choices\":[{\"delta\":{\"content\":\"你好🐸\"}}]}\n\ndata: [DONE]\n\n"
        var parser = DeepSeekStreamParser(); var parsed = ""
        for byte in stream.utf8 { parsed += try parser.consume(Data([byte])).joined() }
        assert(parsed == "你好🐸" && parser.done)
        let networkConfig = URLSessionConfiguration.ephemeral
        networkConfig.protocolClasses = [MockProtocol.self]
        let network = DeepSeekClient(configuration: networkConfig)
        func runNetwork(status: Int, body: String) -> (String, Error?) {
            MockProtocol.status = status; MockProtocol.body = body
            var result = ""; var done = false; var failure: Error?
            network.start(configuration: config, messages: [ChatMessage(isUser: true, text: "你好")], onText: { result += $0 }, onComplete: { failure = $0; done = true })
            let deadline = Date().addingTimeInterval(3)
            while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            assert(done)
            return (result, failure)
        }
        let success = runNetwork(status: 200, body: stream)
        assert(success.0 == "你好🐸" && success.1 == nil)
        assert(MockProtocol.observed?.httpMethod == "POST")
        assert(MockProtocol.observed?.value(forHTTPHeaderField: "Authorization") == "Bearer test-placeholder-only")
        let request = try DeepSeekClient.request(configuration: config, messages: [ChatMessage(isUser: true, text: "你好")])
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        assert(json["model"] as? String == "test-model" && json["stream"] as? Bool == true)
        assert(runNetwork(status: 401, body: "secret server response").1?.localizedDescription.contains("API key") == true)
        assert(runNetwork(status: 429, body: "").1?.localizedDescription.contains("频繁") == true)
        assert(runNetwork(status: 200, body: "data: invalid\n\n").1 != nil)
        assert(runNetwork(status: 200, body: "").1 != nil)
        print("PASS: streaming HTTP pipeline, UTF-8 splits, request format, auth/rate-limit/malformed/truncated errors")

        let mock = MockStream(); let session = ChatSession(client: mock)
        do { try session.send("你好", configuration: DeepSeekConfiguration()); assertionFailure() } catch {}
        assert(mock.requests.isEmpty && session.messages.isEmpty)
        try session.send("你好", configuration: config)
        try session.send("重复发送", configuration: config)
        assert(mock.requests.count == 1)
        mock.text?("你好👨‍👩‍👧‍👦"); mock.complete?(nil)
        session.advance(); assert(session.messages.last?.text == "你" && session.isBusy)
        session.advance(); session.advance(); session.advance()
        assert(session.messages.last?.text == "你好👨‍👩‍👧‍👦" && !session.isBusy)
        try session.send("再聊一句", configuration: config)
        assert(mock.requests.last?.count == 3)
        let staleText = mock.text; let staleCompletion = mock.complete
        session.stop()
        try session.send("新请求", configuration: config)
        staleText?("旧回复"); staleCompletion?(nil)
        session.advance(); assert(session.messages.last?.text == "")
        mock.text?("新回复"); mock.complete?(nil)
        for _ in 0..<4 { session.advance() }
        assert(session.messages.last?.text == "新回复" && !session.isBusy)
        print("PASS: no-key guard, grapheme typewriter, history, duplicate send, cancellation and stale callbacks")

        let avatar = NSImage(contentsOfFile: CommandLine.arguments[1])!
        let uiMock = MockStream(); let uiSession = ChatSession(client: uiMock)
        let controller = ChatWindowController(avatar: avatar, store: store, session: uiSession)
        controller.present()
        let chat = controller.chat
        chat.layoutSubtreeIfNeeded()
        assert(!chat.sendButton.isEnabled)
        chat.input.string = "你好，奶蛙！今天也一起加油吧。"; chat.send()
        assert(chat.input.string.isEmpty && chat.sendButton.title == "停止")
        uiMock.text?("你好呀！🐸 今天有什么想聊的？我会陪你一起慢慢想。\n现在收到的是流式回复，会一个字一个字地出现。"); uiMock.complete?(nil)
        for _ in 0..<100 { uiSession.advance() }
        assert(chat.transcript.messages.count == 2 && chat.sendButton.title == "发送")
        controller.window!.close(); controller.present()
        assert(chat.session.messages.count == 2)
        func capture(_ path: String) throws {
            chat.layoutSubtreeIfNeeded()
            let rep = chat.bitmapImageRepForCachingDisplay(in: chat.bounds)!
            chat.cacheDisplay(in: chat.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
        try capture("/tmp/milkfrog-ai-chat-preview.png")
        controller.window!.setContentSize(NSSize(width: 360, height: 460))
        try capture("/tmp/milkfrog-ai-chat-small.png")
        controller.window!.orderOut(nil)
        let missing = ChatWindowController(avatar: avatar, store: DeepSeekConfigurationStore(directory: directory.appendingPathComponent("missing")), session: ChatSession(client: MockStream()))
        missing.present(); missing.chat.input.string = "保留我的问题"; missing.chat.send()
        assert(missing.chat.input.string == "保留我的问题" && missing.window!.attachedSheet != nil)
        missing.window!.endSheet(missing.window!.attachedSheet!); missing.window!.orderOut(nil)
        print("PASS: UI sends, streams, resizes, preserves session; missing config opens settings and retains draft")
    }
}

import Foundation

struct DeepSeekConfiguration: Codable {
    var apiKey = ""
    var model = ""
    var baseURL = ""

    func endpoint() throws -> URL {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatServiceError.message("请先配置 API key，再和奶蛙聊天。")
        }
        guard !apiKey.contains(where: { $0.isWhitespace }), !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatServiceError.message("请填写有效的 API key 和模型名称。")
        }
        guard let url = URL(string: baseURL), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw ChatServiceError.message("请填写有效的 HTTPS 接口地址。")
        }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix("chat/completions")
            ? url : url.appendingPathComponent("chat/completions")
    }
}

struct DeepSeekConfigurationStore {
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MilkFrog", isDirectory: true)) {
        self.directory = directory
    }
    var file: URL { directory.appendingPathComponent("deepseek.local.json") }
    func load() throws -> DeepSeekConfiguration {
        guard FileManager.default.fileExists(atPath: file.path) else { return DeepSeekConfiguration() }
        return try JSONDecoder().decode(DeepSeekConfiguration.self, from: Data(contentsOf: file))
    }
    func save(_ configuration: DeepSeekConfiguration) throws {
        _ = try configuration.endpoint()
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Create the replacement with private permissions before writing any secret bytes.
        let temporary = directory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        guard fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ChatServiceError.message("无法保存本地配置。")
        }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.write(contentsOf: JSONEncoder().encode(configuration))
        try handle.synchronize()
        if fm.fileExists(atPath: file.path) {
            _ = try fm.replaceItemAt(file, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: file)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

enum ChatServiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    static func http(_ status: Int) -> ChatServiceError {
        switch status {
        case 401, 403: return .message("API key 无效或没有权限，请检查聊天设置。")
        case 402: return .message("DeepSeek 账户余额不足，请充值后重试。")
        case 429: return .message("请求太频繁，请稍后重试。")
        case 400, 404, 422: return .message("请求配置不正确，请检查模型名称和接口地址。")
        default: return .message("服务暂时不可用（HTTP \(status)），请稍后重试。")
        }
    }
}

// Buffer bytes until a whole SSE line arrives, including split UTF-8 characters.
struct DeepSeekStreamParser {
    private var buffer = Data()
    private var eventLines: [String] = []
    private(set) var done = false
    mutating func consume(_ data: Data) throws -> [String] {
        buffer.append(data)
        guard buffer.count < 4_000_000 else { throw ChatServiceError.message("回复数据过大，请重试。") }
        var output: [String] = []
        while let newline = buffer.firstIndex(of: 10) {
            let bytes = buffer[..<newline]
            guard let raw = String(data: bytes, encoding: .utf8) else { throw ChatServiceError.message("回复格式不正确，请重试。") }
            buffer.removeSubrange(...newline)
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.isEmpty {
                if !eventLines.isEmpty, !done {
                    let payload = eventLines.joined(separator: "\n")
                    eventLines.removeAll()
                    if payload == "[DONE]" { done = true; continue }
                    guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any], json["error"] == nil,
                          let choices = json["choices"] as? [[String: Any]] else {
                        throw ChatServiceError.message("回复格式不正确，请检查接口地址。")
                    }
                    if let delta = choices.first?["delta"] as? [String: Any], let content = delta["content"] as? String { output.append(content) }
                }
            } else if line.hasPrefix("data:") {
                let value = String(line.dropFirst(5))
                eventLines.append(value.hasPrefix(" ") ? String(value.dropFirst()) : value)
            }
        }
        return output
    }
}

protocol ChatStreaming: AnyObject {
    func start(configuration: DeepSeekConfiguration, messages: [ChatMessage], onText: @escaping (String) -> Void, onComplete: @escaping (Error?) -> Void)
    func cancel()
}

final class DeepSeekClient: NSObject, ChatStreaming, URLSessionDataDelegate {
    private let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
        super.init()
    }
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var parser = DeepSeekStreamParser()
    private var onText: ((String) -> Void)?
    private var onComplete: ((Error?) -> Void)?

    static func request(configuration: DeepSeekConfiguration, messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: try configuration.endpoint())
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model, "stream": true, "thinking": ["type": "disabled"],
            "messages": [["role": "system", "content": "你是桌宠奶蛙，用友好自然的中文与用户聊天，回答简洁，认真回答问题。"]] + messages.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] }
        ])
        return request
    }

    func start(configuration: DeepSeekConfiguration, messages: [ChatMessage], onText: @escaping (String) -> Void, onComplete: @escaping (Error?) -> Void) {
        cancel()
        self.onText = onText; self.onComplete = onComplete
        parser = DeepSeekStreamParser()
        do {
            let request = try Self.request(configuration: configuration, messages: messages)
            let config = self.configuration
            config.urlCache = nil; config.httpCookieStorage = nil
            config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 300
            session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
            task = session?.dataTask(with: request)
            task?.resume()
        } catch { finish(error) }
    }
    func cancel() {
        onText = nil; onComplete = nil
        task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
    }
    private func finish(_ error: Error?) {
        let callback = onComplete
        cancel()
        callback?(error)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard dataTask === task else { completionHandler(.cancel); return }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            completionHandler(.cancel)
            finish(ChatServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0)); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === task else { return }
        do {
            for text in try parser.consume(data) { onText?(text) }
            if parser.done { finish(nil) }
        } catch { finish(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task else { return }
        // Do not expose raw server responses, URLs, or credentials in errors/logs.
        let message = (error as? URLError)?.code == .timedOut ? "连接超时，请稍后重试。" : "连接中断，请检查网络后重试。"
        finish(ChatServiceError.message(message))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        guard task === self.task else { return }
        finish(ChatServiceError.message("接口发生重定向，请在设置中填写最终的 HTTPS 地址。"))
    }
}

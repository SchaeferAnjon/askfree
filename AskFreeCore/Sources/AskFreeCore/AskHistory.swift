import Foundation

/// 历史里的一轮问答。只存文字：截图只用于当次提问，从不落盘。
public struct AskHistoryTurn: Codable, Equatable, Sendable {
    /// 所属话题（回答面板的 threadID）：同一话题的追问归在一起
    public let thread: String
    public let at: Date
    public let question: String
    public let answer: String

    public init(thread: String, at: Date = Date(), question: String, answer: String) {
        self.thread = thread; self.at = at; self.question = question; self.answer = answer
    }
}

/// 一个话题：按时间排好的几轮问答
public struct AskHistoryThread: Equatable, Sendable, Identifiable {
    public let id: String
    public var turns: [AskHistoryTurn]
    public var startedAt: Date { turns[0].at }
    public var updatedAt: Date { turns[turns.count - 1].at }

    /// 问题或回答里含这些字（不分大小写）
    public func matches(_ query: String) -> Bool {
        turns.contains { $0.question.localizedCaseInsensitiveContains(query) || $0.answer.localizedCaseInsensitiveContains(query) }
    }
}

/// 问答历史：一行一轮的 JSON Lines（~/.config/askfree/history.jsonl，权限 0600）。
/// 追加只写一行；删除时整份重写。
public final class AskHistoryStore {
    public static let shared = AskHistoryStore(fileURL: AppIdentity.configDirectory.appendingPathComponent("history.jsonl"))

    public let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ turn: AskHistoryTurn) throws {
        lock.lock(); defer { lock.unlock() }
        var line = try Self.encoder.encode(turn)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(line)
        }
    }

    /// 全部话题，最近有动静的在前
    public func threads() -> [AskHistoryThread] {
        lock.lock(); defer { lock.unlock() }
        return Self.group(loadTurns())
    }

    public func deleteThread(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        let kept = loadTurns().filter { $0.thread != id }
        var data = Data()
        for turn in kept {
            data.append(try Self.encoder.encode(turn))
            data.append(0x0A)
        }
        try write(data)
    }

    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    static func group(_ turns: [AskHistoryTurn]) -> [AskHistoryThread] {
        var order: [String] = []
        var byThread: [String: [AskHistoryTurn]] = [:]
        for turn in turns {
            if byThread[turn.thread] == nil { order.append(turn.thread) }
            byThread[turn.thread, default: []].append(turn)
        }
        return order.map { AskHistoryThread(id: $0, turns: byThread[$0]!.sorted { $0.at < $1.at }) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 写到一半被打断（断电、强退）的残行读不出来：跳过它，不让一行坏掉整份历史
    private func loadTurns() -> [AskHistoryTurn] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? Self.decoder.decode(AskHistoryTurn.self, from: Data($0)) }
    }

    private func write(_ data: Data) throws {
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

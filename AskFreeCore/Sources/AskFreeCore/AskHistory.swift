import Foundation

/// 历史里的一轮问答。文字在 history.jsonl，这一轮发给模型的截图和找到的图的缩略图另存成文件（见 AskHistoryStore）。
public struct AskHistoryTurn: Codable, Equatable, Sendable {
    public let id: String
    /// 所属话题（回答面板的 threadID）：同一话题的追问归在一起
    public let thread: String
    public let at: Date
    public let question: String
    public let answer: String
    /// 存了这一轮发给模型的两张截图
    public var hasScreenshot: Bool
    /// 回答附的图（联网找到的）；缩略图另存了一份在本机
    public var images: [AskImage]
    /// 怎么问的：screen 看屏幕问、plain 只提问、type 打字问、panel 在回答面板上续聊。旧记录没有这一项
    public var via: String?
    /// 这一问联网查过
    public var searched: Bool?

    public init(id: String = UUID().uuidString, thread: String, at: Date = Date(), question: String, answer: String,
                hasScreenshot: Bool = false, images: [AskImage] = [], via: String? = nil, searched: Bool? = nil) {
        self.id = id; self.thread = thread; self.at = at; self.question = question; self.answer = answer
        self.hasScreenshot = hasScreenshot; self.images = images; self.via = via; self.searched = searched
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

/// 问答历史：一行一轮的 JSON Lines（~/.config/askfree/history.jsonl），
/// 截图和图的缩略图放在旁边的 history-images/，文件名以那一轮的 id 开头。都只有本人可读。
/// 追加只写一行；补图、删除时整份重写。
public final class AskHistoryStore {
    public static let shared = AskHistoryStore(fileURL: AppIdentity.configDirectory.appendingPathComponent("history.jsonl"))

    public let fileURL: URL
    public let imagesDirectory: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.imagesDirectory = fileURL.deletingLastPathComponent().appendingPathComponent("history-images", isDirectory: true)
    }

    /// screenshot：这一轮真发给了模型的两张截图（没看屏幕就是 nil）
    public func append(_ turn: AskHistoryTurn, screenshot: (overviewJPEG: Data, closeUpJPEG: Data)? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        var turn = turn
        if let screenshot {
            try writePrivate(screenshot.closeUpJPEG, to: screenshotURLs(turnID: turn.id).closeUp)
            try writePrivate(screenshot.overviewJPEG, to: screenshotURLs(turnID: turn.id).overview)
            turn.hasScreenshot = true
        }
        var line = try Self.encoder.encode(turn)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try writePrivate(line, to: fileURL)
        }
    }

    /// 图比回答晚到（模型在回答最后才点名要图）：补进已经记下的那一轮
    public func setImages(_ images: [AskImage], turnID: String) throws {
        lock.lock(); defer { lock.unlock() }
        var turns = loadTurns()
        guard let i = turns.firstIndex(where: { $0.id == turnID }) else { return }
        turns[i].images = images
        try rewrite(turns)
    }

    /// 把图的缩略图存一份到本机：网上的图过一阵可能就没了。一张没下下来不影响别的
    public func saveImageThumbs(_ images: [AskImage], turnID: String, session: URLSession = .shared,
                                completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for (i, image) in images.enumerated() {
            guard let url = URL(string: image.thumb) else { continue }
            group.enter()
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            session.dataTask(with: request) { [weak self] data, response, _ in
                defer { group.leave() }
                guard let self, let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                try? self.writePrivate(data, to: self.imageThumbURL(turnID: turnID, index: i))
            }.resume()
        }
        group.notify(queue: .main, execute: completion)
    }

    public func screenshotURLs(turnID: String) -> (closeUp: URL, overview: URL) {
        (imagesDirectory.appendingPathComponent("\(turnID)-closeup.jpg"),
         imagesDirectory.appendingPathComponent("\(turnID)-overview.jpg"))
    }

    public func imageThumbURL(turnID: String, index: Int) -> URL {
        imagesDirectory.appendingPathComponent("\(turnID)-image\(index).jpg")
    }

    /// 全部话题，最近有动静的在前
    public func threads() -> [AskHistoryThread] {
        lock.lock(); defer { lock.unlock() }
        return Self.group(loadTurns())
    }

    /// 历史旁边的笔记缓存（day-notes/）和导出的笔记页（notes/）：笔记里有问题、回答要点和截图，删历史时跟着删
    public var notesDirectory: URL { fileURL.deletingLastPathComponent().appendingPathComponent("day-notes", isDirectory: true) }
    public var exportedNotesDirectory: URL { fileURL.deletingLastPathComponent().appendingPathComponent("notes", isDirectory: true) }

    public func deleteThread(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        let all = loadTurns()
        try rewrite(all.filter { $0.thread != id })
        DayNotesStore(directory: notesDirectory).forget(thread: id)
        let removed = Set(all.filter { $0.thread == id }.map(\.id))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path)) ?? []
        for name in files where removed.contains(where: { name.hasPrefix($0 + "-") }) {
            try FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }

    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        for url in [fileURL, imagesDirectory, notesDirectory, exportedNotesDirectory] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
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

    private func rewrite(_ turns: [AskHistoryTurn]) throws {
        var data = Data()
        for turn in turns {
            data.append(try Self.encoder.encode(turn))
            data.append(0x0A)
        }
        try writePrivate(data, to: fileURL)
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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

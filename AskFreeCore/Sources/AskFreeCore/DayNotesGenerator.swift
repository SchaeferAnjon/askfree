import Foundation

/// 整理笔记要用的那一条模型通道（AskAI 就是它；测试里换成假的）
public protocol NotesCompleting: AnyObject {
    @discardableResult
    func complete(system: String, user: String, maxTokens: Int, member: AskMember?,
                  onPartial: ((String) -> Void)?, onFinishReason: ((String?) -> Void)?, completion: @escaping (Result<String, Error>) -> Void) -> AskRequestHandle
}

extension AskAI: NotesCompleting {}

public enum DayNotesError: LocalizedError, Equatable {
    /// 模型回了字，但一条笔记都读不出来
    case unreadable
    /// 没有可整理的问题
    case nothingToDo

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "模型回的不是笔记的格式，再整理一次试试"
        case .nothingToDo: return "这一天没有问题可以整理"
        }
    }
}

/// 一天的笔记：一个请求，模型把每个问题的要点、这一天的小结一起写出来。
/// 要点是一节一节收尾的，收尾一节就把它放进笔记并回调一次，界面上「整理好了第几个」跟着走。
/// 回调都在主线程
public final class DayNotesGenerator {
    private let ai: NotesCompleting
    public init(ai: NotesCompleting) { self.ai = ai }

    /// resume：停下或没整理完的那份；给了就只整理它缺的问题，没给就这一天整份重做。
    /// onUpdate：又收尾了一个问题（参数是现在的整份笔记，小结还没写时是空的）。
    /// completion：success 的笔记可能还缺几个问题（模型少写了、字数到头被截断），看 DayNotes.status
    @discardableResult
    public func run(day: HistoryDay, resume: DayNotes?, member: AskMember?, calendar: Calendar = .current,
                    onUpdate: @escaping (DayNotes) -> Void,
                    completion: @escaping (Result<DayNotes, Error>) -> Void) -> AskRequestHandle {
        let all = DayNotesPrompt.questions(for: day, calendar: calendar)
        var notes = resume ?? DayNotes.begin(day)
        // 接着整理时，历史里这期间新问的也一起整理，covered 跟上
        for thread in day.threads where !notes.covered.contains(where: { $0.thread == thread.id }) {
            notes.covered.append(DayNoteCoverage(thread: thread.id, turns: thread.turns.count))
        }
        let missing = all.filter { notes.item(for: $0.threadID) == nil }
        // 一个请求装不下全部时只放前面的：剩下的留给「接着整理」，不让请求大到发不出去、整天整理不出来
        let todo = DayNotesPrompt.fit(missing)
        guard !missing.isEmpty || notes.summary.isEmpty else {
            DispatchQueue.main.async { completion(.success(notes)) }
            return AskRequestHandle()
        }
        guard !all.isEmpty else {
            DispatchQueue.main.async { completion(.failure(DayNotesError.nothingToDo)) }
            return AskRequestHandle()
        }
        let byIndex = Dictionary(uniqueKeysWithValues: all.map { ($0.index, $0) })
        let finished = all.compactMap { q in notes.item(for: q.threadID).map { (index: q.index, title: $0.title) } }
        let request = DayNotesPrompt.request(todo: todo, total: all.count, dayLabel: day.key, finishedTitles: finished,
                                             language: DayNotesPrompt.languageName(of: all), later: missing.count - todo.count)
        let todoIndexes = Set(todo.map(\.index))
        // 读到哪些问题已经收尾；两个回调（出字、结束）都在这条串行队列上改 notes
        let queue = DispatchQueue(label: "askfree.daynotes")
        var working = notes
        func absorb(_ text: String, final: Bool) -> DayNotesParser.Result {
            let parsed = DayNotesParser.parse(text, final: final)
            for item in parsed.items where todoIndexes.contains(item.index) {
                guard let q = byIndex[item.index] else { continue }
                working.put(DayNoteItem(id: q.threadID, turnID: q.turnID,
                                        title: item.title.isEmpty ? Self.fallbackTitle(q.question) : item.title, points: item.points))
            }
            return parsed
        }
        var lastCount = working.items.count
        // 输出写到 max_tokens 就被截断，流是正常结束的：最后一节写了一半，不能算整理好
        var truncated = false
        return ai.complete(system: request.system, user: request.user, maxTokens: request.maxTokens, member: member,
                           onPartial: { text in
            queue.async {
                _ = absorb(text, final: false)
                guard working.items.count != lastCount else { return }
                lastCount = working.items.count
                let snapshot = working
                DispatchQueue.main.async { onUpdate(snapshot) }
            }
        }, onFinishReason: { reason in
            queue.async { truncated = reason == "length" }
        }, completion: { result in
            queue.async {
                switch result {
                case .success(let text):
                    // 开发版实测用：把模型回的原文存到这个目录（只在开发版，平时不记问答内容）
                    if AppIdentity.isDevBuild, let dir = ProcessInfo.processInfo.environment["ASKFREE_NOTES_RAW_DIR"] {
                        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                        try? text.write(toFile: dir + "/\(day.key)-\(Int(Date().timeIntervalSince1970)).txt", atomically: true, encoding: .utf8)
                    }
                    let parsed = absorb(text, final: !truncated)
                    guard parsed.sawSection, working.items.count > notes.items.count || parsed.summary != nil else {
                        DispatchQueue.main.async { completion(.failure(DayNotesError.unreadable)) }
                        return
                    }
                    // 小结等所有问题都整理好了才收：缺了几个时小结只说了一半的事，下次接着整理时再写
                    let stillMissing = all.contains { working.item(for: $0.threadID) == nil }
                    // 被截断时「记住这几条」多半没写完：连小结一起留到接着整理时再写
                    if !stillMissing && !(truncated && parsed.keep == nil) {
                        if let summary = parsed.summary { working.summary = summary }
                        if let keep = parsed.keep { working.keep = keep }
                    }
                    working.generatedAt = Date()
                    let done = working
                    DispatchQueue.main.async { completion(.success(done)) }
                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        })
    }

    /// 模型没给题名：用问题开头
    static func fallbackTitle(_ question: String) -> String {
        let line = question.split(separator: "\n").first.map(String.init) ?? question
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 16 ? String(trimmed.prefix(16)) + "…" : trimmed
    }
}

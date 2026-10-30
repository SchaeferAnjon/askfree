import Foundation

/// 历史里的一天：问过问题的那天，和那天的话题（按那天问的时间从早到晚）。
/// 分天的办法和「历史」列表一样：话题最后一次有动静是哪天，就归哪天
public struct HistoryDay: Equatable, Sendable, Identifiable {
    public var id: String { key }
    /// 本地日期 yyyy-MM-dd
    public let key: String
    /// 那天 0 点
    public let date: Date
    public let threads: [AskHistoryThread]

    public init(key: String, date: Date, threads: [AskHistoryThread]) {
        self.key = key
        self.date = date
        self.threads = threads
    }

    /// 本地日期的 yyyy-MM-dd（缓存文件名、笔记里的日期都用它）
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// yyyy-MM-dd 写回那天 0 点；格式不对返回 nil
    public static func date(forKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, key.count == 10 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// 全部话题按天分好，最近的一天在前；每天里按那天问的时间从早到晚
    public static func group(_ threads: [AskHistoryThread], calendar: Calendar = .current) -> [HistoryDay] {
        var byDay: [String: [AskHistoryThread]] = [:]
        var dates: [String: Date] = [:]
        for thread in threads {
            let start = calendar.startOfDay(for: thread.updatedAt)
            let key = key(for: start, calendar: calendar)
            byDay[key, default: []].append(thread)
            dates[key] = start
        }
        return byDay.keys.sorted(by: >).map { key in
            let date = dates[key]!
            let sorted = byDay[key]!.sorted { Self.moment(of: $0, on: date, calendar: calendar) < Self.moment(of: $1, on: date, calendar: calendar) }
            return HistoryDay(key: key, date: date, threads: sorted)
        }
    }

    /// 这个话题在 day 那天第一次问的时刻（话题是前一天开的、今天才追问的，取今天的第一轮）
    public static func moment(of thread: AskHistoryThread, on day: Date, calendar: Calendar = .current) -> Date {
        thread.turns.first { calendar.isDate($0.at, inSameDayAs: day) }?.at ?? thread.startedAt
    }
}

/// 一个问题（一个话题）整理出的笔记
public struct DayNoteItem: Codable, Equatable, Sendable, Identifiable {
    /// 话题 id
    public var id: String
    /// 话题第一轮的 id：截图按它找
    public var turnID: String
    /// 目录里的短题名
    public var title: String
    /// 回答的要点：Markdown 条目，里面可以有 `代码`、$公式$、代码块
    public var points: String

    public init(id: String, turnID: String, title: String, points: String) {
        self.id = id
        self.turnID = turnID
        self.title = title
        self.points = points
    }
}

/// 整理时这一天里有哪个话题、问到第几轮：之后和历史对不上，就是又问了新的
public struct DayNoteCoverage: Codable, Equatable, Sendable {
    public var thread: String
    public var turns: Int

    public init(thread: String, turns: Int) {
        self.thread = thread
        self.turns = turns
    }
}

/// 这一天的笔记。整理到一半停下，也存成这个样子（summary 空、items 比 covered 少），接着整理从缺的那几个开始
public struct DayNotes: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// yyyy-MM-dd
    public var day: String
    /// 这一天的小结；还没写（整理没完）是空的
    public var summary: String
    /// 「记住这几条」
    public var keep: [String]
    public var items: [DayNoteItem]
    public var covered: [DayNoteCoverage]
    public var generatedAt: Date

    public init(day: String, summary: String = "", keep: [String] = [], items: [DayNoteItem] = [],
                covered: [DayNoteCoverage], generatedAt: Date = Date()) {
        self.version = Self.currentVersion
        self.day = day
        self.summary = summary
        self.keep = keep
        self.items = items
        self.covered = covered
        self.generatedAt = generatedAt
    }

    /// 一次新的整理开始：这一天现有的话题都算在内，一条笔记都还没有
    public static func begin(_ day: HistoryDay, now: Date = Date()) -> DayNotes {
        DayNotes(day: day.key, covered: day.threads.map { DayNoteCoverage(thread: $0.id, turns: $0.turns.count) }, generatedAt: now)
    }

    /// 放进一条（同一个话题的旧条目换掉）
    public mutating func put(_ item: DayNoteItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
    }

    public func item(for threadID: String) -> DayNoteItem? {
        items.first { $0.id == threadID }
    }

    /// 和历史现在的样子比：整理好几个、有没有小结、又问了几个新问题、几个问题又追问了
    public func status(against day: HistoryDay) -> DayNotesStatus {
        let current = Dictionary(uniqueKeysWithValues: day.threads.map { ($0.id, $0.turns.count) })
        let coveredByID = Dictionary(covered.map { ($0.thread, $0.turns) }, uniquingKeysWith: { first, _ in first })
        let stillThere = covered.filter { current[$0.thread] != nil }
        return DayNotesStatus(
            done: items.filter { current[$0.id] != nil && coveredByID[$0.id] != nil }.count,
            total: stillThere.count,
            hasSummary: !summary.isEmpty,
            newQuestions: day.threads.filter { coveredByID[$0.id] == nil }.count,
            followedUp: day.threads.filter { coveredByID[$0.id] != nil && coveredByID[$0.id] != $0.turns.count }.count)
    }
}

/// 一天的笔记现在是什么情形
public struct DayNotesStatus: Equatable, Sendable {
    /// 整理好的问题数、整理时这一天的问题数（已经从历史里删掉的不算）
    public let done: Int
    public let total: Int
    public let hasSummary: Bool
    /// 整理之后这一天又问的新问题
    public let newQuestions: Int
    /// 整理之后又追问了的问题
    public let followedUp: Int

    /// 每个问题都整理好了、小结也写了
    public var isComplete: Bool { total > 0 && done >= total && hasSummary }
    /// 整理之后历史又有了新的：值得重新整理
    public var isOutdated: Bool { newQuestions + followedUp > 0 }
}

/// 笔记缓存文件和「已经导进 Anki」的记录，放在历史旁边的 day-notes/ 里，只有本人可读。
/// 删历史时笔记跟着删（AskHistoryStore.deleteThread / deleteAll）
public final class DayNotesStore: @unchecked Sendable {
    public static let shared = DayNotesStore(directory: AppIdentity.configDirectory.appendingPathComponent("day-notes", isDirectory: true))

    public let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
    }

    private func url(forDay day: String) -> URL { directory.appendingPathComponent("\(day).json") }
    private var ledgerURL: URL { directory.appendingPathComponent("anki.json") }

    /// 读不出来、版本比这个 App 新的当没有
    public func load(day: String) -> DayNotes? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url(forDay: day)),
              let notes = try? Self.decoder.decode(DayNotes.self, from: data),
              notes.version <= DayNotes.currentVersion else { return nil }
        return notes
    }

    public func save(_ notes: DayNotes) throws {
        lock.lock(); defer { lock.unlock() }
        try writePrivate(try Self.encoder.encode(notes), to: url(forDay: notes.day))
    }

    /// 哪几天有笔记（文件名里的日期）
    public func days() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { $0.hasSuffix(".json") && $0 != "anki.json" ? String($0.dropLast(5)) : nil }.sorted()
    }

    // MARK: 已经导进 Anki 的

    /// 话题 id → 导进去的时间
    public func ankiLedger() -> [String: Date] {
        lock.lock(); defer { lock.unlock() }
        return readLedger()
    }

    public func markInAnki(_ threadIDs: [String], at date: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }
        var all = readLedger()
        for id in threadIDs { all[id] = date }
        try writePrivate(try Self.encoder.encode(all), to: ledgerURL)
    }

    private func readLedger() -> [String: Date] {
        guard let data = try? Data(contentsOf: ledgerURL),
              let all = try? Self.decoder.decode([String: Date].self, from: data) else { return [:] }
        return all
    }

    // MARK: 删

    /// 历史里删了一个话题：各天笔记里它的那一条、导进 Anki 的记录一起去掉
    public func forget(thread id: String) {
        lock.lock(); defer { lock.unlock() }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".json") && name != "anki.json" {
            let file = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file), var notes = try? Self.decoder.decode(DayNotes.self, from: data),
                  notes.items.contains(where: { $0.id == id }) || notes.covered.contains(where: { $0.thread == id }) else { continue }
            notes.items.removeAll { $0.id == id }
            notes.covered.removeAll { $0.thread == id }
            if notes.covered.isEmpty { try? FileManager.default.removeItem(at: file); continue }
            if let data = try? Self.encoder.encode(notes) { try? writePrivate(data, to: file) }
        }
        var all = readLedger()
        if all.removeValue(forKey: id) != nil, let data = try? Self.encoder.encode(all) { try? writePrivate(data, to: ledgerURL) }
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory)
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
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

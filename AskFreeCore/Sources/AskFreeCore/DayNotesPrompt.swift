import Foundation

/// 交给模型整理的一个问题：问、答、追问
public struct NotesQuestion: Equatable, Sendable {
    /// 这一天里的第几个（从 1 起，和笔记页上的编号一致）
    public let index: Int
    public let threadID: String
    public let turnID: String
    /// HH:mm
    public let time: String
    public let question: String
    public let answer: String
    /// 追问和它们的回答
    public let followUps: [(question: String, answer: String)]

    public static func == (a: NotesQuestion, b: NotesQuestion) -> Bool {
        a.index == b.index && a.threadID == b.threadID && a.turnID == b.turnID && a.time == b.time
            && a.question == b.question && a.answer == b.answer
            && a.followUps.map { [$0.question, $0.answer] } == b.followUps.map { [$0.question, $0.answer] }
    }
}

/// 整理一天笔记的那一个请求：写什么、怎么写、回来怎么读
public enum DayNotesPrompt {
    /// 整个请求里问题和回答的字数上限：一天问得再多也不让请求大到发不出去
    static let totalBudget = 60_000
    static let followUpBudget = 700

    /// 这一天的问题，按那天问的时间排好编号
    public static func questions(for day: HistoryDay, calendar: Calendar = .current) -> [NotesQuestion] {
        let share = max(600, min(3000, totalBudget / max(1, day.threads.count)))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = calendar.timeZone
        return day.threads.enumerated().map { offset, thread in
            let first = thread.turns[0]
            return NotesQuestion(
                index: offset + 1, threadID: thread.id, turnID: first.id,
                time: formatter.string(from: HistoryDay.moment(of: thread, on: day.date, calendar: calendar)),
                question: clip(first.question, to: 400), answer: clip(first.answer, to: share),
                followUps: thread.turns.dropFirst().prefix(4).map { (clip($0.question, to: 300), clip($0.answer, to: followUpBudget)) })
        }
    }

    /// 超过字数就在段落边上截断，写明后面省略了
    static func clip(_ text: String, to limit: Int) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        let cut = head.range(of: "\n", options: .backwards).map { head[..<$0.lowerBound] }.flatMap { $0.count > limit / 2 ? String($0) : nil } ?? head
        return cut + "\n（后面省略）"
    }

    /// 笔记写成什么语言：多数问题是同一种非中文语言就用它，其余用中文
    public static func languageName(of questions: [NotesQuestion]) -> String? {
        var counts: [String: Int] = [:]
        for q in questions { if let name = AskReplyLanguage.languageName(of: q.question) { counts[name, default: 0] += 1 } }
        guard let top = counts.max(by: { $0.value < $1.value }), top.value * 2 > questions.count else { return nil }
        return top.key
    }

    static let system = """
    你在把用户今天问 AI 的问题整理成一页图文笔记。用户每个问题都带一张截图，笔记的读者就是用户自己，回头复习用。
    对每个问题写：一个不超过 14 个字的短题名（目录里用），和回答的要点——3 到 5 条，每条一句话，只留回答里真正要记住的结论和做法，不复述问题，不加客套。简单的问题 2 条也行。
    要点里原回答的 `代码`、命令、$公式$ 照原样保留；独立成行的公式写成单独一行的 $$…$$。原回答里有代码块时，把最关键的那一段（不超过 12 行）原样放在相关要点的后面，带上语言名，写成 ``` 代码块；没有代码块的不要自己编。不用表格、小标题。
    最后写这一天的小结：2 到 4 句话说清今天都弄明白了什么，不要逐个问题罗列；再写「记住这几条」：3 到 5 条跨问题最值得记的，每条一句话。
    严格按下面的格式输出，不要输出别的文字，也不要用代码围栏包住整份：

    ## 3
    标题：短题名
    - 要点一
    - 要点二

    ## 5
    标题：…
    - …

    ## 小结
    一小段话

    ## 记住
    - 一条
    - 一条

    「## 数字」里的数字就是问题前面的编号（只写需要整理的那几个，按编号从小到大）。
    """

    /// 一个请求：要整理 todo 里的这几个问题；finishedTitles 是已经整理好的（接着整理时，小结要把它们也算上）
    public static func request(todo: [NotesQuestion], total: Int, dayLabel: String, finishedTitles: [(index: Int, title: String)] = [],
                               language: String? = nil) -> (system: String, user: String, maxTokens: Int) {
        var user = "日期：\(dayLabel)\n这一天一共问了 \(total) 个问题"
        if todo.isEmpty {
            user += "，每个都已经整理好了，现在只要写小结和「记住这几条」。\n"
        } else {
            user += finishedTitles.isEmpty ? "，下面是全部 \(todo.count) 个。\n" : "，下面是还没整理的 \(todo.count) 个。\n"
        }
        if !finishedTitles.isEmpty {
            user += "已经整理好的（只用来写小结和「记住这几条」，不用再写）：" + finishedTitles.map { "\($0.index). \($0.title)" }.joined(separator: "；") + "\n"
        }
        for q in todo {
            user += "\n### 问题 \(q.index)（\(q.time)）\n问：\(q.question)\n答：\(q.answer)\n"
            for (i, f) in q.followUps.enumerated() {
                user += "追问\(i + 1)：\(f.question)\n追问\(i + 1)的回答：\(f.answer)\n"
            }
        }
        var system = Self.system
        if let language {
            system += "\n\nIMPORTANT: The questions are in \(language). Write the whole notes (titles, points, summary) in \(language); keep the section markers (## 3, ## 小结, ## 记住) and the line prefix 标题： exactly as shown."
        }
        // 每个问题大约 200 个字的要点，加上小结；会员后台一次最多放 8192
        return (system, user, min(8000, 600 * todo.count + 1200))
    }
}

/// 模型回来的文字读成笔记。流式的时候后面的还在长，只认已经收尾的节（后面又出现了「## 」）
public enum DayNotesParser {
    public struct Item: Equatable, Sendable {
        public let index: Int
        public let title: String
        public let points: String
    }

    public struct Result: Equatable, Sendable {
        public var items: [Item] = []
        public var summary: String?
        public var keep: [String]?
        /// 认出过至少一个「## 」节：没有就说明模型没按格式写
        public var sawSection = false
    }

    private enum Kind: Equatable { case item(Int), summary, keep, other }

    /// final：回答已经收完，最后一节也算收尾
    public static func parse(_ text: String, final: Bool) -> Result {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // 整份被 ```markdown 包着：剥掉最外面一层
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].trimmingCharacters(in: .whitespaces).range(of: #"^```(markdown|md|text)?$"#, options: .regularExpression) != nil {
            lines.remove(at: first)
            if let last = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
               lines[last].trimmingCharacters(in: .whitespaces) == "```" { lines.remove(at: last) }
        }
        var sections: [(kind: Kind, body: [String])] = []
        var inFence = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { inFence.toggle() }
            if !inFence, let kind = header(t) {
                sections.append((kind, []))
            } else if !sections.isEmpty {
                sections[sections.count - 1].body.append(line)
            }
        }
        var result = Result()
        result.sawSection = !sections.isEmpty
        for (i, section) in sections.enumerated() {
            // 最后一节在流式时还没写完
            if i == sections.count - 1 && !final { continue }
            let body = trimBlank(section.body)
            switch section.kind {
            case .item(let index):
                guard let item = item(index: index, body: body) else { continue }
                if let at = result.items.firstIndex(where: { $0.index == index }) { result.items[at] = item } else { result.items.append(item) }
            case .summary:
                let text = body.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
                if !text.isEmpty { result.summary = clean(text) }
            case .keep:
                let points = body.compactMap(bulletText)
                if !points.isEmpty { result.keep = points }
            case .other: break
            }
        }
        return result
    }

    private static func header(_ t: String) -> Kind? {
        guard t.hasPrefix("#") else { return nil }
        let title = t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        if title.isEmpty { return nil }
        if let m = title.range(of: #"^\d+"#, options: .regularExpression), let n = Int(title[m]) {
            let rest = title[m.upperBound...]
            // 「## 3」「## 3. 标题」「## 问题 3」都算；「## 2026 年的…」这种不算
            let digits = title[m].count
            if rest.isEmpty || rest.first.map({ ".、:：）)".contains($0) }) == true || (rest.first == " " && digits <= 2) { return .item(n) }
        }
        if let m = title.range(of: #"^(问题|Question|Q)\s*\d+"#, options: [.regularExpression, .caseInsensitive]),
           let n = Int(title[m].drop(while: { !$0.isNumber })) { return .item(n) }
        let lower = title.lowercased()
        // 模型有时写成「今日小结」「这一天的小结」「Key takeaways」：名字里带这几个词就算
        if ["记住", "要记", "最值得记", "takeaway", "remember"].contains(where: { lower.contains($0) }) { return .keep }
        if ["小结", "总结", "summary", "overview"].contains(where: { lower.contains($0) }) { return .summary }
        return .other
    }

    private static func item(index: Int, body: [String]) -> Item? {
        var rest = body
        var title = ""
        if let at = rest.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let t = rest[at].trimmingCharacters(in: .whitespaces)
            if let m = t.range(of: #"^(?:[-*•]\s*)?(?:\*\*)?(?:标题|题名|Title)(?:\*\*)?\s*[:：]\s*"#, options: [.regularExpression, .caseInsensitive]) {
                title = clean(String(t[m.upperBound...]))
                rest.remove(at: at)
            }
        }
        let points = trimBlank(rest).joined(separator: "\n")
        guard !points.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Item(index: index, title: String(title.prefix(30)), points: points)
    }

    private static func bulletText(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let m = t.range(of: #"^(?:[-*•·]|\d+[.、)）])\s+"#, options: .regularExpression) else { return nil }
        let text = clean(String(t[m.upperBound...]))
        return text.isEmpty ? nil : text
    }

    /// 题名、小结里偶尔夹着的 ** 去掉
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimBlank(_ lines: [String]) -> [String] {
        var lines = lines
        while let f = lines.first, f.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines
    }
}

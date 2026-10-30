import Foundation
import AskFreeCore
import AnswerRender

/// 一天的笔记排成一页自带一切的 HTML：截图内嵌、公式排好、样式和脚本都在里面，没网、拷到别的电脑都能看。
/// 浏览器里有能收起的目录和浅色 / 深色切换；导出 PDF 就是把同一页按打印样式排出来（见 App 里的 NotesPDF）
public enum NotesPage {
    /// 「2026-10-29 Ask Free 笔记.html」：浏览器页和 PDF 用同一个名字
    public static func fileName(day: String, ext: String) -> String { "\(day) Ask Free 笔记.\(ext)" }

    /// screenshot：这个话题发给 AI 的那张图（没有就 nil）。math：公式怎么排，默认 KaTeX；测试里可以换
    public static func html(notes: DayNotes, day: HistoryDay, screenshot: (AskHistoryThread) -> Data?,
                            exportedAt: Date = Date(), calendar: Calendar = .current,
                            math: ((String, Bool) -> String?)? = nil) -> String {
        let typeset = math ?? { KaTeXRenderer.shared.render($0, display: $1) }
        var usedMath = false
        let renderer = AnswerHTML(
            math: { tex, display in
                guard let html = typeset(tex, display) else { return nil }
                usedMath = true
                return html
            },
            code: { language, code in codeHTML(language: language, code: code) })

        // 编号是这一天里的第几个问题（没整理好的也占一个号），和 App 里笔记页上的一样
        let entries: [(n: Int, thread: AskHistoryThread, item: DayNoteItem)] = day.threads.enumerated().compactMap { offset, thread in
            notes.item(for: thread.id).map { (offset + 1, thread, $0) }
        }
        var anyShot = false
        var sections = ""
        var toc = ""
        for entry in entries {
            let n = entry.n
            let moment = HistoryDay.moment(of: entry.thread, on: day.date, calendar: calendar)
            let first = entry.thread.turns[0]
            var meta = [Self.time(moment, calendar), kindTitle(entry.thread)]
            if entry.thread.turns.contains(where: { $0.searched == true }) { meta.append("联网查过") }
            let shot = screenshot(entry.thread)
            var picture = ""
            if let shot {
                anyShot = true
                picture = "<figure class=\"shot\"><div class=\"pic\" role=\"button\" tabindex=\"0\" data-zoom aria-label=\"放大截图\">"
                    + "<img src=\"data:\(mime(shot));base64,\(shot.base64EncodedString())\" alt=\"问的时候发给 AI 的截图，红框是当时指着的地方\">"
                    + "<span class=\"zb\"><svg viewBox=\"0 0 16 16\"><path d=\"M9.5 2.5h4v4M6.5 13.5h-4v-4M13.5 2.5 9.2 6.8M2.5 13.5l4.3-4.3\"/></svg>放大</span></div></figure>"
            }
            toc += "<li><a href=\"#t\(n)\" class=\"ti\" data-tip=\"\(esc(entry.item.title))\"><span class=\"n\">\(n)</span><span class=\"w\">\(esc(entry.item.title))</span></a></li>\n"
            sections += """
            <section class="sec" id="t\(n)">
              <div class="keep"><header class="sech"><h2><span class="ix">\(n)</span>\(esc(first.question))</h2><div class="m">\(esc(meta.joined(separator: " · ")))</div></header>
              <div class="qb\(shot == nil ? " solo" : "")">\(picture)
              <div class="ptsw"><div class="lab">回答的要点</div>\(renderer.html(entry.item.points))</div></div></div>
            </section>

            """
        }

        let title = "\(day.key) Ask Free 笔记"
        let first = entries.first.map { HistoryDay.moment(of: $0.thread, on: day.date, calendar: calendar) }
        let last = entries.last.map { HistoryDay.moment(of: $0.thread, on: day.date, calendar: calendar) }
        var count = "\(entries.count) 个问题"
        if entries.count < day.threads.count { count += "（这一天问了 \(day.threads.count) 个，其余没整理）" }
        var metaLine = ["\(calendar.component(.year, from: day.date)) 年", count]
        if let first, let last { metaLine.append("\(Self.time(first, calendar)) 到 \(Self.time(last, calendar))") }

        var summary = ""
        if !notes.summary.isEmpty {
            summary = "<section class=\"sum\"><p>\(esc(notes.summary).replacingOccurrences(of: "\n", with: "<br>"))</p>"
            if !notes.keep.isEmpty {
                summary += "<div class=\"lab\">记住这几条</div><ul class=\"pts\">"
                    + notes.keep.map { "<li>\(renderer.inline($0))</li>" }.joined() + "</ul>"
            }
            summary += "</section>"
        }
        var foot = "Ask Free 整理 · \(Self.stamp(exportedAt, calendar)) 导出"
        if anyShot { foot += " · 截图里的红框是提问时指着的地方" }

        let heading = Self.heading(day.date, calendar)
        let css = resource("page/notes-page.css") + (usedMath ? (KaTeXRenderer.inlineCSS() ?? "") : "")
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="generator" content="Ask Free">
        <title>\(esc(title))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <div class="shell" id="shell">
        <nav class="toc" id="toc" aria-label="目录"><div class="toch"><b>目录</b><button class="tgl" type="button" id="tgl" aria-label="收起目录" title="收起目录"><svg viewBox="0 0 16 16"><rect x="2" y="2.8" width="12" height="10.4" rx="1.6"/><path d="M6.2 2.8v10.4"/></svg></button></div><ol class="toclist">
        <li><a href="#ov" class="ti on" data-tip="这一天"><span class="n"><svg viewBox="0 0 16 16"><path d="M5.5 4.5h8M5.5 8h8M5.5 11.5h8M2.5 4.5h.01M2.5 8h.01M2.5 11.5h.01"/></svg></span><span class="w">这一天</span></a></li>
        \(toc)</ol></nav>
        <main class="page">
          <header class="hd" id="ov"><div><div class="app">Ask Free 笔记</div><h1>\(esc(heading))</h1>
            <div class="meta">\(esc(metaLine.joined(separator: " · ")))</div></div>
            <div class="seg" role="group" aria-label="颜色"><button type="button" data-t="auto" class="on">自动</button><button type="button" data-t="light">浅色</button><button type="button" data-t="dark">深色</button></div></header>
          \(summary)
        \(sections)  <div class="foot">\(esc(foot))</div>
        </main>
        </div>
        <script>
        \(resource("page/notes-page.js"))
        </script>
        </body>
        </html>
        """
    }

    // MARK: 代码着色

    static func codeHTML(language: String, code: String) -> String? {
        guard let lines = CodeHighlighter.tokenLines(code, language: language) else { return nil }
        return lines.map { pieces in
            pieces.map { piece in
                let text = AnswerHTML.escape(piece.text)
                guard let token = piece.token else { return text }
                let cls: String
                switch token {
                case .keyword: cls = "k"
                case .string: cls = "s"
                case .comment: cls = "c"
                case .number: cls = "n"
                case .type: cls = "t"
                }
                return "<span class=\"\(cls)\">\(text)</span>"
            }.joined()
        }.joined(separator: "\n")
    }

    // MARK: 小工具

    private static func esc(_ s: String) -> String { AnswerHTML.escape(s) }

    private static func mime(_ data: Data) -> String {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
    }

    private static func kindTitle(_ thread: AskHistoryThread) -> String {
        switch thread.turns[0].via {
        case "type": return "打字问"
        case "plain": return "只提问"
        case "screen": return "看屏幕问"
        default: return thread.turns[0].hasScreenshot ? "看屏幕问" : "只提问"
        }
    }

    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    static func time(_ date: Date, _ calendar: Calendar) -> String { formatter("HH:mm", calendar).string(from: date) }
    static func stamp(_ date: Date, _ calendar: Calendar) -> String { formatter("yyyy-MM-dd HH:mm", calendar).string(from: date) }
    /// 10 月 29 日 周四的问答笔记
    static func heading(_ date: Date, _ calendar: Calendar) -> String { formatter("M 月 d 日 EEE", calendar).string(from: date) + "的问答笔记" }

    private static func resource(_ path: String) -> String {
        let name = (path as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: (name as NSString).lastPathComponent, withExtension: ext,
                                          subdirectory: "Resources/" + (name as NSString).deletingLastPathComponent),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}

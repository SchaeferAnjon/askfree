import Foundation

/// 回答（轻量 Markdown）排成 HTML：导出的笔记页和 Anki 卡片背面用。
/// 拆块、行内公式的切法和 App 里的排版（AnswerBlocks）是同一套；公式和代码块怎么画由调用方给
public struct AnswerHTML {
    /// 公式 → HTML；nil 表示排不出来，显示源码。display 是独立公式
    public var math: (_ tex: String, _ display: Bool) -> String?
    /// 代码 → 里面的 HTML（已经转义、着好色）；nil 表示不着色，按原文转义
    public var code: (_ language: String, _ code: String) -> String?

    public init(math: @escaping (String, Bool) -> String?, code: @escaping (String, String) -> String? = { _, _ in nil }) {
        self.math = math
        self.code = code
    }

    /// 笔记页：公式交给 KaTeX 排好的 HTML
    public func html(_ markdown: String) -> String {
        var out = ""
        var inList = false
        func closeList() { if inList { out += "</ul>"; inList = false } }
        func openList() { if !inList { out += "<ul class=\"pts\">"; inList = true } }
        for block in AnswerBlocks.parse(markdown, streaming: false) {
            switch block {
            case .heading(let text):
                closeList()
                out += "<p class=\"hd3\">\(inline(text))</p>"
            case .paragraph(let text):
                closeList()
                out += "<p class=\"para\">\(inline(text.replacingOccurrences(of: "\n", with: " ")))</p>"
            case .bullet(let text):
                openList()
                out += "<li>\(inline(text))</li>"
            case .numbered(let marker, let text):
                openList()
                out += "<li class=\"no\"><span class=\"nm\">\(Self.escape(marker))</span>\(inline(text))</li>"
            case .code(let language, let code, let attached):
                if attached != nil { openList(); out += "<li class=\"blk\">\(codeBlock(language, code))</li>" }
                else { closeList(); out += codeBlock(language, code) }
            case .math(let tex, let attached):
                if attached != nil { openList(); out += "<li class=\"blk\">\(displayMath(tex))</li>" }
                else { closeList(); out += displayMath(tex) }
            case .pending:
                break
            }
        }
        closeList()
        return out
    }

    func codeBlock(_ language: String, _ code: String) -> String {
        let label = language.isEmpty || language.lowercased() == "text" ? "代码" : Self.languageLabel(language)
        let body = self.code(language, code) ?? Self.escape(code)
        return "<div class=\"code\"><div class=\"code-h\"><span>\(Self.escape(label))</span>"
            + "<button class=\"copy\" type=\"button\" data-copy><svg viewBox=\"0 0 16 16\"><rect x=\"5.5\" y=\"5.5\" width=\"8\" height=\"8\" rx=\"1.5\"/>"
            + "<path d=\"M10.5 5.5V3.8c0-.7-.6-1.3-1.3-1.3H3.8c-.7 0-1.3.6-1.3 1.3v5.4c0 .7.6 1.3 1.3 1.3h1.7\"/></svg>复制</button></div>"
            + "<div class=\"scrollx\"><pre><code>\(body)</code></pre></div></div>"
    }

    func displayMath(_ tex: String) -> String {
        if let html = math(tex, true) { return "<div class=\"scrollx math\">\(html)</div>" }
        return "<div class=\"scrollx\"><pre class=\"texsrc\">\(Self.escape(tex))</pre></div>"
    }

    /// 行内：公式、`代码`、**加粗**、*斜体*、[链接](网址)
    public func inline(_ source: String) -> String {
        var out = ""
        for piece in AnswerBlocks.inline(source) {
            switch piece {
            case .math(let tex):
                out += math(tex, false) ?? "<code class=\"texsrc\">\(Self.escape(tex))</code>"
            case .text(let text):
                out += Self.inlineMarkdown(text)
            }
        }
        return out
    }

    // MARK: 行内 Markdown

    static func inlineMarkdown(_ text: String) -> String {
        // 先把反引号里的拿出来，免得里面的 * 被当成加粗
        var rest = Substring(text)
        var html = ""
        func flush(_ plain: String) { html += styled(plain) }
        while let open = rest.firstIndex(of: "`") {
            let n = rest[open...].prefix(while: { $0 == "`" }).count
            let fence = String(repeating: "`", count: n)
            let afterFence = rest.index(open, offsetBy: n)
            if let close = rest.range(of: fence, range: afterFence..<rest.endIndex) {
                flush(String(rest[..<open]))
                let code = String(rest[afterFence..<close.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " "))
                html += "<code>\(escape(code))</code>"
                rest = rest[close.upperBound...]
            } else {
                break
            }
        }
        flush(String(rest))
        return html
    }

    /// 转义后再套粗体、斜体、链接
    private static func styled(_ plain: String) -> String {
        var s = escape(plain)
        s = s.replacingOccurrences(of: #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\*\w])\*(?=[^\s*])([^*\n]+?)(?<=[^\s*])\*(?![\*\w])"#, with: "<em>$1</em>", options: .regularExpression)
        return linkify(s)
    }

    /// [文字](网址)：只认 http(s)、mailto
    private static func linkify(_ escaped: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(((?:https?://|mailto:)[^)\s]+)\)"#) else { return escaped }
        let ns = escaped as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: escaped, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += "<a href=\"\(ns.substring(with: m.range(at: 2)))\" target=\"_blank\" rel=\"noopener\">\(ns.substring(with: m.range(at: 1)))</a>"
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    // MARK: 小工具

    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for c in text {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    /// 代码块顶上的语言名：swift → Swift，js → JavaScript……认不出的原样大写开头
    static func languageLabel(_ raw: String) -> String {
        let names = ["swift": "Swift", "python": "Python", "py": "Python", "js": "JavaScript", "javascript": "JavaScript",
                     "ts": "TypeScript", "typescript": "TypeScript", "bash": "Bash", "sh": "Shell", "zsh": "Shell", "shell": "Shell",
                     "c": "C", "cpp": "C++", "c++": "C++", "java": "Java", "go": "Go", "rust": "Rust", "rs": "Rust", "json": "JSON",
                     "html": "HTML", "css": "CSS", "sql": "SQL", "yaml": "YAML", "yml": "YAML", "diff": "Diff", "kotlin": "Kotlin",
                     "ruby": "Ruby", "rb": "Ruby", "php": "PHP", "objc": "Objective-C", "console": "终端", "terminal": "终端"]
        return names[raw.lowercased()] ?? (raw.prefix(1).uppercased() + raw.dropFirst())
    }
}

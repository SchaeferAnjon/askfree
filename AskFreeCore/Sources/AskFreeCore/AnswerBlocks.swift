import Foundation

/// 代码块、独立公式跟在哪种条目下面（缩进到条目文字那一列）
public enum ListIndent: Equatable, Sendable { case bullet, numbered }

/// 回答拆成的一块。字符串都是行内源码（还带 **、反引号、$…$），由渲染那边再切
public enum AnswerBlock: Equatable, Sendable {
    case heading(String)
    case paragraph(String)
    case bullet(String)
    /// "3."，正文
    case numbered(String, String)
    case code(language: String, code: String, attachedTo: ListIndent?)
    case math(tex: String, attachedTo: ListIndent?)
    /// 流式中途还没收尾的独立公式或还没写完的围栏行：不显示、不占高
    case pending
}

public enum InlinePiece: Equatable, Sendable {
    case text(String)
    case math(String)
}

/// 回答的轻量 Markdown 拆块：空行分段、「### 」小标题、「- 」「1. 」条目，加 ``` 代码块、独立一行的 $$…$$ / \[…\] 公式。
/// 流式时（streaming）最后一块里没收尾的公式、还没写完的围栏行先不显示，收尾那一下整条出来；代码块边来边长。
/// 规则见 task-lue8s 的施工计划 §4；AnswerMarkdown（复制、预览）用同一套围栏和公式判断
public enum AnswerBlocks {
    /// 独立公式开头之后多少字、多少行之内必须收尾，超过就当普通段落（流式时在这之内先不显示）
    static let displayMathMaxChars = 500
    static let displayMathMaxLines = 15
    /// 流式时最后一行先不显示的行内字数上限，超过就原样显示
    static let inlineHoldMaxChars = 200

    // MARK: - 拆块

    public static func parse(_ markdown: String, streaming: Bool) -> [AnswerBlock] {
        var lines = splitLines(markdown)
        var out: [AnswerBlock] = []
        var para: [String] = []
        /// 下一个代码块 / 独立公式跟着哪种条目（上一块是条目，或跟着条目的公式、代码块，中间只隔空行）
        var follow: ListIndent?
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para.removeAll() }
        }
        let last = lines.count - 1
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)
            let isLast = i == last

            // 围栏开头
            if let fence = fenceOpen(t) {
                flush()
                if streaming && isLast { out.append(.pending); break }   // 围栏行还没写完：语言名可能还在长
                let indent = raw.prefix(while: { $0 == " " }).count
                var code: [String] = []
                var j = i + 1
                var closed = false
                while j < lines.count {
                    let line = lines[j]
                    let lt = line.trimmingCharacters(in: .whitespaces)
                    if isFenceClose(lt, count: fence.count) { closed = true; break }
                    // 流式时最后一行只有 1 到 3 个反引号：可能是收尾的围栏，先不显示
                    if streaming && j == last && !lt.isEmpty && lt.count < fence.count && lt.allSatisfy({ $0 == "`" }) { j += 1; continue }
                    code.append(dropIndent(line, upTo: indent))
                    j += 1
                }
                while let tail = code.last, tail.trimmingCharacters(in: .whitespaces).isEmpty { code.removeLast() }
                if !(code.isEmpty && !streaming) {   // 答完时开了围栏却一行内容都没有：丢掉
                    out.append(.code(language: fence.language, code: code.joined(separator: "\n"), attachedTo: follow))
                }
                i = closed ? j + 1 : lines.count
                continue
            }

            // 独立公式：这一行以 $$ 或 \[ 开头
            if let open = displayMathOpener(t) {
                switch findDisplayMath(lines, at: i, opener: open, streaming: streaming) {
                case .found(let tex, let endLine, let rest):
                    flush()
                    out.append(.math(tex: tex, attachedTo: follow))
                    if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                        i = endLine + 1
                    } else {
                        lines[endLine] = rest   // 收尾符后面同一行还有字：当新的一行接着处理
                        i = endLine
                    }
                    continue
                case .waiting:
                    flush()
                    out.append(.pending)
                    i = lines.count
                    continue
                case .notMath:
                    flush()   // 当普通的一行，另起一段：前面那段不会因为这里没收尾而变
                }
            }

            if t.isEmpty { flush(); i += 1; continue }

            // 流式时最后一行：没收尾的行内公式先不显示
            let visible = streaming && isLast ? streamingVisible(t) : t
            // 只剩 1、2 个反引号的最后一行：可能是围栏的开头，先不显示
            if streaming && isLast && !visible.isEmpty && visible.count < 3 && visible.allSatisfy({ $0 == "`" }) {
                i += 1
                continue
            }

            if visible.hasPrefix("#") {
                flush()
                follow = nil
                let title = visible.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { out.append(.heading(title)) }
                i += 1
                continue
            }
            if let r = visible.range(of: #"^(?:[-•·*]|\d+[.、)）])\s+"#, options: .regularExpression) {
                flush()
                let marker = String(visible[r]).trimmingCharacters(in: .whitespaces)
                let body = String(visible[r.upperBound...])
                if marker.first?.isNumber == true {
                    out.append(.numbered(marker.trimmingCharacters(in: CharacterSet(charactersIn: ".、)）")) + ".", body))
                    follow = .numbered
                } else {
                    out.append(.bullet(body))
                    follow = .bullet
                }
                i += 1
                continue
            }
            if !visible.isEmpty {
                para.append(visible)
                follow = nil
            }
            i += 1
        }
        flush()
        return out
    }

    // MARK: - 行内切分

    /// 一段行内源码切成文字和行内公式。文字部分还是行内 Markdown（**、反引号原样），`\$` 换成 `$`。
    /// 反引号里的不找公式；`$` 照 Pandoc 的规则（开头的后面不是空白，收尾的前面不是空白、后面不是数字）
    public static func inline(_ source: String) -> [InlinePiece] {
        var pieces: [InlinePiece] = []
        for span in scanInline(Array(stripPrivateUse(source))) {
            if span.isMath {
                pieces.append(.math(span.value))
            } else if case .text(let previous)? = pieces.last {
                pieces[pieces.count - 1] = .text(previous + span.value)
            } else {
                pieces.append(.text(span.value))
            }
        }
        return pieces
    }

    /// 行内的一段：文字或公式。raw 是原文（公式带分隔符）；value 是文字（`\$` 换成 `$`）或公式的 TeX（去掉首尾空白）
    struct InlineSpan: Equatable {
        var isMath: Bool
        var raw: String
        var value: String
    }

    /// 行内切分，复制（原样留公式）和预览（公式写成普通字符）也用这个
    static func scanInline(_ s: [Character]) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        var raw = ""
        var text = ""
        func flushText() {
            if !raw.isEmpty { spans.append(InlineSpan(isMath: false, raw: raw, value: text)); raw = ""; text = "" }
        }
        func emitMath(_ from: Int, _ to: Int, texFrom: Int, texTo: Int) {
            flushText()
            spans.append(InlineSpan(isMath: true, raw: String(s[from..<to]),
                                    value: String(s[texFrom..<texTo]).trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        func plain(_ from: Int, _ to: Int) {
            let piece = String(s[from..<to])
            raw += piece
            text += piece
        }
        var i = 0
        while i < s.count {
            let c = s[i]
            if c == "`" {
                let n = runLength(s, from: i, of: "`")
                if let close = findBacktickClose(s, from: i + n, count: n) {
                    plain(i, close + n)
                    i = close + n
                } else {
                    plain(i, i + n)
                    i += n
                }
                continue
            }
            if c == "\\", i + 1 < s.count {
                let d = s[i + 1]
                if d == "$" { raw += "\\$"; text += "$"; i += 2; continue }
                if d == "(", let close = findSequence(s, from: i + 2, ["\\", ")"], sameLine: true) {
                    emitMath(i, close + 2, texFrom: i + 2, texTo: close)
                    i = close + 2
                    continue
                }
                plain(i, i + 2)
                i += 2
                continue
            }
            if c == "$" {
                if i + 1 < s.count, s[i + 1] == "$" {
                    if let close = findSequence(s, from: i + 2, ["$", "$"], sameLine: true), close > i + 2 {
                        emitMath(i, close + 2, texFrom: i + 2, texTo: close)
                        i = close + 2
                        continue
                    }
                    plain(i, i + 2)
                    i += 2
                    continue
                }
                if case .close(let close) = findDollarClose(s, from: i) {
                    emitMath(i, close + 1, texFrom: i + 1, texTo: close)
                    i = close + 1
                    continue
                }
                plain(i, i + 1)
                i += 1
                continue
            }
            plain(i, i + 1)
            i += 1
        }
        flushText()
        return spans
    }

    /// 流式时最后一行能显示的部分：从第一个没配对的 `\(`、`$$`、后面跟着非数字的 `$` 起先不显示（不超过 200 字），
    /// 末尾单独的 `\`、`$` 也先不显示（可能是 `\(`、`$$` 的前半截）。行内代码没闭合时，这一行剩下的不找公式
    static func streamingVisible(_ line: String) -> String {
        let s = Array(line)
        var i = 0
        func hold(from start: Int) -> String {
            s.count - start > inlineHoldMaxChars ? line : String(s[..<start])
        }
        while i < s.count {
            let c = s[i]
            if c == "`" {
                let n = runLength(s, from: i, of: "`")
                guard let close = findBacktickClose(s, from: i + n, count: n) else { return line }
                i = close + n
                continue
            }
            if c == "\\" {
                if i + 1 >= s.count { return String(s[..<i]) }   // 末尾单独一个 \
                if s[i + 1] == "(" {
                    if let close = findSequence(s, from: i + 2, ["\\", ")"], sameLine: true) { i = close + 2; continue }
                    return hold(from: i)
                }
                i += 2
                continue
            }
            if c == "$" {
                if i + 1 >= s.count { return String(s[..<i]) }   // 末尾单独一个 $
                if s[i + 1] == "$" {
                    if let close = findSequence(s, from: i + 2, ["$", "$"], sameLine: true), close > i + 2 { i = close + 2; continue }
                    return hold(from: i)
                }
                switch findDollarClose(s, from: i) {
                case .close(let close): i = close + 1
                case .invalid: i += 1   // 后面第一个 $ 配不上：这个 $ 是普通字，再来字也不会变成公式
                case .none:
                    let next = s[i + 1]
                    if next.isWhitespace || next.isNumber { i += 1; continue }   // 价钱、普通的 $
                    return hold(from: i)
                }
                continue
            }
            i += 1
        }
        return line
    }

    // MARK: - 围栏、独立公式的判断（AnswerMarkdown 也用）

    struct Fence: Equatable { let count: Int; let language: String }

    /// t 以 3 个或更多反引号开头，后面是可选的语言名（只留 [A-Za-z0-9_+#.-]，最多 20 个字，不合规当空）
    static func fenceOpen(_ t: String) -> Fence? {
        let n = t.prefix(while: { $0 == "`" }).count
        guard n >= 3 else { return nil }
        let info = t.dropFirst(n).trimmingCharacters(in: .whitespaces)
        // 信息串里有反引号的不是围栏（CommonMark），当普通字
        guard !info.contains("`") else { return nil }
        let word = info.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+#.-")
        let ok = word.count <= 20 && word.unicodeScalars.allSatisfy { allowed.contains($0) }
        return Fence(count: n, language: ok ? word : "")
    }

    /// 一串反引号，个数不少于开头那行，后面没有别的字
    static func isFenceClose(_ t: String, count: Int) -> Bool {
        t.count >= count && t.allSatisfy { $0 == "`" }
    }

    enum DisplayMathOpener { case dollars, bracket }

    static func displayMathOpener(_ t: String) -> DisplayMathOpener? {
        if t.hasPrefix("$$") { return .dollars }
        if t.hasPrefix("\\[") { return .bracket }
        return nil
    }

    enum DisplayMathResult: Equatable {
        /// tex：分隔符之间去掉首尾空白；endLine：收尾符所在的行；rest：收尾符后面同一行剩下的字
        case found(tex: String, endLine: Int, rest: String)
        /// 流式中途还没收尾，也还没超过 500 字、15 行
        case waiting
        /// 超过 500 字、15 行还没收尾（答完时就是没收尾）：这一行当普通的字
        case notMath
    }

    /// 从第 i 行（去掉首尾空白后以 $$ 或 \[ 开头）往后找收尾符，同一行或后面几行都行，中间可以有空行
    static func findDisplayMath(_ lines: [String], at i: Int, opener: DisplayMathOpener, streaming: Bool) -> DisplayMathResult {
        let first = lines[i].trimmingCharacters(in: .whitespaces)
        let close = opener == .dollars ? "$$" : "\\]"
        var acc = String(first.dropFirst(2))
        var j = i
        while true {
            if let r = acc.range(of: close) {
                let tex = acc[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if tex.isEmpty { return .notMath }
                // rest 是收尾那一行收尾符后面的字：acc 的最后一行就是第 j 行（去掉了开头部分）
                let rest = String(acc[r.upperBound...])
                return .found(tex: tex, endLine: j, rest: rest)
            }
            if acc.count > displayMathMaxChars || j - i >= displayMathMaxLines { return .notMath }
            j += 1
            if j >= lines.count { return streaming ? .waiting : .notMath }
            acc += "\n" + lines[j]
        }
    }

    // MARK: - 小工具

    /// 按 \n 拆行，顺手去掉 \r
    static func splitLines(_ s: String) -> [String] {
        s.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    static func dropIndent(_ line: String, upTo n: Int) -> String {
        guard n > 0 else { return line }
        let spaces = min(n, line.prefix(while: { $0 == " " }).count)
        return String(line.dropFirst(spaces))
    }

    /// U+E000–U+F8FF 私用区：渲染时拿来给公式占位，输入里出现的先删掉
    static func stripPrivateUse(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { (0xE000...0xF8FF).contains($0.value) }) else { return s }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.filter { !(0xE000...0xF8FF).contains($0.value) })
        return String(scalars)
    }

    private static func runLength(_ s: [Character], from i: Int, of c: Character) -> Int {
        var j = i
        while j < s.count, s[j] == c { j += 1 }
        return j - i
    }

    /// 往后找正好 n 个反引号的一串（多一个少一个都不算），返回它的开头
    private static func findBacktickClose(_ s: [Character], from start: Int, count n: Int) -> Int? {
        var j = start
        while j < s.count {
            if s[j] == "`" {
                let m = runLength(s, from: j, of: "`")
                if m == n { return j }
                j += m
            } else {
                j += 1
            }
        }
        return nil
    }

    /// 往后找两个字的收尾符（`\)`、`$$`）；sameLine 时遇到换行就停。反斜杠后面那个字跳过（`\\`、`\$` 不算收尾）
    private static func findSequence(_ s: [Character], from start: Int, _ seq: [Character], sameLine: Bool) -> Int? {
        var j = start
        while j + 1 < s.count {
            if sameLine && s[j] == "\n" { return nil }
            if s[j] == seq[0] && s[j + 1] == seq[1] { return j }
            if s[j] == "\\" { j += 2; continue }
            j += 1
        }
        return nil
    }

    enum DollarClose: Equatable {
        case close(Int)
        /// 同一行里后面第一个 $ 配不上（前面是空白，或后面紧跟数字）
        case invalid
        /// 开头的后面是空白，或同一行里后面没有 $ 了
        case none
    }

    /// s[i] 是 `$`（后面不是 `$`）：开头的后面紧跟的不能是空白；同一行里后面第一个 `$` 是收尾的，
    /// 它前面紧跟的不能是空白、后面紧跟的不能是数字，不然这个 `$` 就是普通字（`$5 and $10`、`$x$5` 都不是公式）。`\x` 成对跳过
    private static func findDollarClose(_ s: [Character], from i: Int) -> DollarClose {
        guard i + 1 < s.count, !s[i + 1].isWhitespace else { return .none }
        var j = i + 1
        while j < s.count {
            let c = s[j]
            if c == "\n" { return .none }
            if c == "\\" { j += 2; continue }
            if c == "$" {
                let afterIsDigit = j + 1 < s.count && s[j + 1].isNumber
                return !s[j - 1].isWhitespace && !afterIsDigit ? .close(j) : .invalid
            }
            j += 1
        }
        return .none
    }
}

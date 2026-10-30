import AppKit
import SwiftUI

/// 代码块的小号着色：只分关键字、字符串、注释、数字、类型名（大写开头的标识符）五类，其余用正文色。
/// 颜色是浅色、深色各一套的动态色（Xcode 默认配色），按视图自己的外观取色：面板外观和系统不一样时也对。
/// 只认常见的几种语言，其他语言、text、plaintext 不着色，免得着错
@MainActor
public enum CodeHighlighter {
    public enum Token: CaseIterable { case keyword, string, comment, number, type }

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        func rgb(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
        let l = rgb(light), d = rgb(dark)
        return NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l }
    }

    public static let colors: [Token: NSColor] = [
        .keyword: dynamic(light: 0x9B2393, dark: 0xFC5FA3),
        .string: dynamic(light: 0xC41A16, dark: 0xFC6A5D),
        .comment: dynamic(light: 0x5D6C79, dark: 0x7F8C98),
        .number: dynamic(light: 0x1C00CF, dark: 0xD0BF69),
        .type: dynamic(light: 0x0B4F79, dark: 0x5DD8FF),
    ]
    private static let swiftUIColors: [Token: Color] = colors.mapValues { Color(nsColor: $0) }

    /// 超过就不着色
    nonisolated static let maxLines = 400
    nonisolated static let maxChars = 20_000

    struct Language: Sendable {
        var keywords: Set<String>
        var lineComment: [String] = ["//"]
        var hashComment = false
        var blockComment = true
        var tripleQuotes = false
        /// ' 只当字符字面量（'a'、'\n'），配不上就是普通字（Rust 的生命周期 'a）
        var singleQuoteIsChar = false
        var backtickStrings = false
        var types = true
        var caseInsensitive = false
        var onlyStringsAndNumbers = false
        var attributes = false
    }

    nonisolated private static let cFamilyTypes: Set<String> = ["int", "char", "void", "float", "double", "long", "short", "unsigned", "signed", "bool", "auto", "size_t"]

    nonisolated static func language(_ name: String) -> Language? {
        switch name.lowercased() {
        case "python", "py", "python3":
            return Language(keywords: ["import", "from", "as", "def", "class", "return", "if", "elif", "else", "for", "in", "while", "with",
                                       "try", "except", "finally", "raise", "lambda", "None", "True", "False", "and", "or", "not", "is",
                                       "pass", "break", "continue", "yield", "async", "await", "global", "nonlocal", "del", "assert", "match", "case", "self"],
                            lineComment: [], hashComment: true, blockComment: false, tripleQuotes: true, attributes: true)
        case "js", "javascript", "ts", "typescript", "jsx", "tsx", "mjs", "node":
            return Language(keywords: ["const", "let", "var", "function", "return", "if", "else", "for", "while", "do", "class", "new", "import",
                                       "export", "from", "default", "async", "await", "try", "catch", "finally", "throw", "null", "undefined",
                                       "true", "false", "this", "of", "in", "typeof", "instanceof", "switch", "case", "break", "continue",
                                       "extends", "super", "static", "interface", "type", "enum", "implements", "public", "private",
                                       "protected", "readonly", "as", "void", "yield", "delete"],
                            backtickStrings: true)
        case "swift":
            return Language(keywords: ["import", "struct", "class", "enum", "func", "var", "let", "if", "else", "guard", "return", "for", "in",
                                       "while", "repeat", "switch", "case", "default", "break", "continue", "private", "fileprivate",
                                       "public", "internal", "open", "final", "init", "deinit", "self", "Self", "some", "any", "await",
                                       "async", "try", "throws", "throw", "rethrows", "static", "extension", "protocol", "nil", "true",
                                       "false", "where", "do", "catch", "defer", "inout", "mutating", "override", "lazy", "weak",
                                       "unowned", "typealias", "associatedtype", "is", "as", "actor", "nonisolated", "super", "get", "set"],
                            tripleQuotes: true, singleQuoteIsChar: true, attributes: true)
        case "bash", "sh", "zsh", "shell", "console", "terminal":
            return Language(keywords: ["if", "then", "else", "elif", "fi", "for", "do", "done", "while", "until", "case", "esac", "function",
                                       "in", "return", "local", "export", "echo", "cd", "sudo", "exit", "source", "set", "unset", "read"],
                            lineComment: [], hashComment: true, blockComment: false, types: false)
        case "c", "cpp", "c++", "cc", "cxx", "h", "hpp", "objc", "objective-c", "objectivec":
            return Language(keywords: cFamilyTypes.union(["if", "else", "for", "while", "do", "return", "switch", "case", "default", "break",
                                                          "continue", "struct", "union", "enum", "typedef", "static", "const", "extern",
                                                          "sizeof", "goto", "volatile", "register", "inline", "class", "public", "private",
                                                          "protected", "virtual", "template", "typename", "namespace", "using", "new",
                                                          "delete", "this", "nullptr", "true", "false", "NULL", "const_cast", "static_cast",
                                                          "dynamic_cast", "reinterpret_cast", "try", "catch", "throw", "operator",
                                                          "#include", "#define", "#if", "#ifdef", "#ifndef", "#endif", "#else", "#pragma",
                                                          "@interface", "@implementation", "@end", "@property", "self", "nil", "YES", "NO"]),
                            singleQuoteIsChar: true)
        case "java", "kotlin", "kt":
            return Language(keywords: ["public", "private", "protected", "class", "interface", "enum", "extends", "implements", "static",
                                       "final", "void", "int", "long", "double", "float", "boolean", "char", "byte", "short", "new",
                                       "return", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue",
                                       "try", "catch", "finally", "throw", "throws", "import", "package", "this", "super", "null", "true",
                                       "false", "abstract", "synchronized", "var", "val", "fun", "when", "is", "in", "object", "companion",
                                       "data", "sealed", "override", "open", "lateinit", "suspend", "as", "record", "yield"],
                            singleQuoteIsChar: true, attributes: true)
        case "go", "golang":
            return Language(keywords: ["package", "import", "func", "var", "const", "type", "struct", "interface", "map", "chan", "if", "else",
                                       "for", "range", "return", "switch", "case", "default", "break", "continue", "go", "defer", "select",
                                       "fallthrough", "goto", "nil", "true", "false", "iota", "make", "new", "len", "cap", "append",
                                       "string", "int", "int64", "float64", "bool", "byte", "rune", "error"],
                            singleQuoteIsChar: true, backtickStrings: true)
        case "rust", "rs":
            return Language(keywords: ["fn", "let", "mut", "const", "static", "struct", "enum", "impl", "trait", "pub", "use", "mod", "crate",
                                       "self", "Self", "super", "if", "else", "match", "for", "in", "while", "loop", "break", "continue",
                                       "return", "as", "ref", "move", "where", "type", "unsafe", "async", "await", "dyn", "true", "false",
                                       "i32", "i64", "u8", "u32", "u64", "usize", "f32", "f64", "bool", "str", "char"],
                            singleQuoteIsChar: true)
        case "sql", "mysql", "postgresql", "postgres", "sqlite":
            return Language(keywords: ["select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete",
                                       "create", "table", "drop", "alter", "add", "index", "primary", "key", "foreign", "references",
                                       "join", "left", "right", "inner", "outer", "full", "on", "as", "group", "by", "order", "having",
                                       "limit", "offset", "distinct", "union", "all", "null", "is", "in", "like", "between", "case",
                                       "when", "then", "else", "end", "exists", "count", "sum", "avg", "min", "max", "asc", "desc",
                                       "default", "unique", "with", "integer", "int", "text", "varchar", "boolean", "true", "false"],
                            lineComment: ["--"], types: false, caseInsensitive: true)
        case "json", "jsonc":
            return Language(keywords: [], lineComment: [], blockComment: false, types: false, onlyStringsAndNumbers: true)
        default:
            return nil
        }
    }

    /// 跨行的状态：上一行结束时还在块注释、或者还没收尾的字符串（三引号、JS 模板字符串、Go 原始字符串；带的是收尾符）里
    enum LineState: Hashable, Sendable {
        case normal
        case blockComment
        case string(String)
    }

    private struct LineKey: Hashable { let language: String; let state: LineState; let line: String }
    private static var lineCache: [LineKey: (text: AttributedString, end: LineState)] = [:]
    static let lineCacheLimit = 4000

    static func resetCache() { lineCache.removeAll() }

    /// 着好色的代码，一行一段（没认出的语言、太长的代码就是不带颜色的原文）。
    /// 按行缓存（键里带上一行结束时的状态）：流式出字时前面的行都命中，只有最后一行重新分词
    public static func highlightLines(_ code: String, language: String) -> [AttributedString] {
        let lines = code.components(separatedBy: "\n")
        guard let lang = Self.language(language), code.count <= maxChars, lines.count <= maxLines else { return lines.map { AttributedString($0) } }
        var state = LineState.normal
        var out: [AttributedString] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            let key = LineKey(language: language, state: state, line: line)
            if let hit = lineCache[key] {
                out.append(hit.text)
                state = hit.end
                continue
            }
            let (pieces, end) = tokenizeLine(line, lang, state)
            var text = AttributedString()
            for (piece, token) in pieces {
                var run = AttributedString(piece)
                if let token { run.foregroundColor = swiftUIColors[token] }
                text += run
            }
            if lineCache.count >= lineCacheLimit { lineCache.removeAll() }
            lineCache[key] = (text, end)
            out.append(text)
            state = end
        }
        return out
    }

    /// 一段代码分好词，一行一个数组，每段（字, 类别）；类别 nil = 正文色。导出 HTML 用，不碰主线程上的缓存，哪个线程都能调。
    /// 没认出的语言、太长的代码返回 nil（调用方按原文放）
    nonisolated public static func tokenLines(_ code: String, language: String) -> [[(text: String, token: Token?)]]? {
        let lines = code.components(separatedBy: "\n")
        guard let lang = Self.language(language), code.count <= maxChars, lines.count <= maxLines else { return nil }
        var state = LineState.normal
        var out: [[(text: String, token: Token?)]] = []
        for line in lines {
            let (pieces, end) = tokenizeLine(line, lang, state)
            out.append(pieces.map { (text: $0.0, token: $0.1) })
            state = end
        }
        return out
    }

    /// 整段着色（各行接起来）：历史页的代码块是一整段字，能跨行选中
    public static func highlight(_ code: String, language: String) -> AttributedString {
        var out = AttributedString()
        for (k, line) in highlightLines(code, language: language).enumerated() {
            if k > 0 { out += AttributedString("\n") }
            out += line
        }
        return out
    }

    /// 一行分词：返回一段段（字, 类别）和这一行结束时的状态，类别 nil = 正文色。字拼起来等于这一行
    nonisolated static func tokenizeLine(_ line: String, _ lang: Language, _ entry: LineState) -> ([(String, Token?)], LineState) {
        let s = Array(line)
        var out: [(String, Token?)] = []
        var plain = ""
        func emit(_ from: Int, _ to: Int, _ token: Token?) {
            if token == nil { plain += String(s[from..<to]); return }
            if !plain.isEmpty { out.append((plain, nil)); plain = "" }
            out.append((String(s[from..<to]), token))
        }
        func flush() { if !plain.isEmpty { out.append((plain, nil)); plain = "" } }
        func starts(_ i: Int, _ p: String) -> Bool {
            let p = Array(p)
            return i + p.count <= s.count && Array(s[i..<(i + p.count)]) == p
        }
        func lineEnd(_ i: Int) -> Int {
            var j = i
            while j < s.count, s[j] != "\n" { j += 1 }
            return j
        }
        func isIdentChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        /// 从 j 往后找收尾符 q（跳过反斜杠转义）：返回收尾符后面的位置；这一行里没有返回 nil
        func closing(_ q: String, from j: Int, escapes: Bool) -> Int? {
            var k = j
            while k < s.count {
                if starts(k, q) { return k + q.count }
                if escapes, s[k] == "\\" { k += 1 }
                k += 1
            }
            return nil
        }
        var i = 0
        // 上一行留下的块注释、字符串
        switch entry {
        case .normal: break
        case .blockComment:
            guard let end = closing("*/", from: 0, escapes: false) else { emit(0, s.count, .comment); return (out, .blockComment) }
            emit(0, end, .comment); i = end
        case .string(let q):
            guard let end = closing(q, from: 0, escapes: true) else { emit(0, s.count, .string); return (out, entry) }
            emit(0, end, .string); i = end
        }
        while i < s.count {
            let c = s[i]
            // 注释
            if !lang.onlyStringsAndNumbers {
                if lang.lineComment.contains(where: { starts(i, $0) }) {
                    let end = lineEnd(i); emit(i, end, .comment); i = end; continue
                }
                if lang.hashComment, c == "#", i == 0 || s[i - 1].isWhitespace {
                    let end = lineEnd(i); emit(i, end, .comment); i = end; continue
                }
                if lang.blockComment, starts(i, "/*") {
                    guard let end = closing("*/", from: i + 2, escapes: false) else { emit(i, s.count, .comment); flush(); return (out, .blockComment) }
                    emit(i, end, .comment); i = end; continue
                }
            }
            // 字符串（三引号、反引号的可以跨行）
            if lang.tripleQuotes, starts(i, "\"\"\"") || starts(i, "'''") {
                let q = String(s[i..<(i + 3)])
                guard let end = closing(q, from: i + 3, escapes: true) else { emit(i, s.count, .string); flush(); return (out, .string(q)) }
                emit(i, end, .string); i = end; continue
            }
            if c == "`" && lang.backtickStrings {
                guard let end = closing("`", from: i + 1, escapes: true) else { emit(i, s.count, .string); flush(); return (out, .string("`")) }
                emit(i, end, .string); i = end; continue
            }
            if c == "\"" || (c == "'" && !lang.singleQuoteIsChar) {
                // 普通引号到行尾为止
                let end = closing(String(c), from: i + 1, escapes: true) ?? s.count
                emit(i, end, .string); i = end; continue
            }
            if c == "'" && lang.singleQuoteIsChar {
                // 'a'、'\n'、'\u{1F600}'
                var j = i + 1
                if j < s.count, s[j] == "\\" { j += 2; while j < s.count, j - i < 12, s[j] != "'" { j += 1 } } else { j += 1 }
                if j < s.count, s[j] == "'" {
                    emit(i, j + 1, .string); i = j + 1; continue
                }
                emit(i, i + 1, nil); i += 1; continue
            }
            if lang.onlyStringsAndNumbers {
                if c.isNumber || (c == "-" && i + 1 < s.count && s[i + 1].isNumber) {
                    var j = i + 1
                    while j < s.count, s[j].isNumber || ".eE+-".contains(s[j]) { j += 1 }
                    emit(i, j, .number); i = j; continue
                }
                emit(i, i + 1, nil); i += 1; continue
            }
            // 数字：前面不是标识符的一部分
            if c.isNumber, c.isASCII, i == 0 || !isIdentChar(s[i - 1]) {
                var j = i + 1
                while j < s.count, s[j].isLetter || s[j].isNumber || s[j] == "_" || (s[j] == "." && j + 1 < s.count && s[j + 1].isNumber) { j += 1 }
                emit(i, j, .number); i = j; continue
            }
            // 标识符、关键字、类型名
            if c.isLetter || c == "_" || ((c == "@" || c == "#") && i + 1 < s.count && s[i + 1].isLetter) {
                var j = i + 1
                while j < s.count, isIdentChar(s[j]) { j += 1 }
                let word = String(s[i..<j])
                let key = lang.caseInsensitive ? word.lowercased() : word
                if lang.keywords.contains(key) || (lang.attributes && c == "@") {
                    emit(i, j, .keyword)
                } else if lang.types, c.isUppercase {
                    emit(i, j, .type)
                } else {
                    emit(i, j, nil)
                }
                i = j
                continue
            }
            emit(i, i + 1, nil)
            i += 1
        }
        flush()
        return (out, .normal)
    }
}

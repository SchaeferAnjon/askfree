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
    static let maxLines = 400
    static let maxChars = 20_000
    static let cacheLimit = 64

    struct Language {
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

    private static let cFamilyTypes: Set<String> = ["int", "char", "void", "float", "double", "long", "short", "unsigned", "signed", "bool", "auto", "size_t"]

    static func language(_ name: String) -> Language? {
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

    private static var cache: [String: AttributedString] = [:]
    private static var order: [String] = []

    static func resetCache() { cache.removeAll(); order.removeAll() }

    /// 着好色的代码（没认出的语言、太长的代码就是不带颜色的原文）
    public static func highlight(_ code: String, language: String) -> AttributedString {
        let key = language + "\u{0}" + code
        if let hit = cache[key] { return hit }
        let result = make(code, language: language)
        cache[key] = result
        order.append(key)
        if order.count > cacheLimit { cache.removeValue(forKey: order.removeFirst()) }
        return result
    }

    private static func make(_ code: String, language name: String) -> AttributedString {
        guard let lang = language(name), code.count <= maxChars,
              code.utf8.reduce(0, { $1 == 10 ? $0 + 1 : $0 }) < maxLines else { return AttributedString(code) }
        var out = AttributedString()
        for (text, token) in tokenize(code, lang) {
            var piece = AttributedString(text)
            if let token { piece.foregroundColor = swiftUIColors[token] }
            out += piece
        }
        return out
    }

    /// 分词：返回一段段（字, 类别），类别 nil = 正文色。字拼起来等于原文
    static func tokenize(_ code: String, _ lang: Language) -> [(String, Token?)] {
        let s = Array(code)
        var out: [(String, Token?)] = []
        var plain = ""
        func emit(_ from: Int, _ to: Int, _ token: Token?) {
            if token == nil { plain += String(s[from..<to]); return }
            if !plain.isEmpty { out.append((plain, nil)); plain = "" }
            out.append((String(s[from..<to]), token))
        }
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
        var i = 0
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
                    var j = i + 2
                    while j < s.count, !starts(j, "*/") { j += 1 }
                    let end = min(s.count, j + 2)
                    emit(i, end, .comment); i = end; continue
                }
            }
            // 字符串
            if lang.tripleQuotes, starts(i, "\"\"\"") || starts(i, "'''") {
                let q = String(s[i..<(i + 3)])
                var j = i + 3
                while j < s.count, !starts(j, q) { if s[j] == "\\" { j += 1 }; j += 1 }
                let end = min(s.count, j + 3)
                emit(i, end, .string); i = end; continue
            }
            if c == "\"" || (c == "'" && !lang.singleQuoteIsChar) || (c == "`" && lang.backtickStrings) {
                var j = i + 1
                while j < s.count, s[j] != c, s[j] != "\n" || c == "`" { if s[j] == "\\" { j += 1 }; j += 1 }
                let end = min(s.count, j < s.count && s[j] == c ? j + 1 : j)
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
        if !plain.isEmpty { out.append((plain, nil)) }
        return out
    }
}

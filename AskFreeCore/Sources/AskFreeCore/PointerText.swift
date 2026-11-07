import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 指针底下的字：本机文字识别（Vision）认出来的那个词、它那一行、上下几行，或者用户选中的文字。
/// 截图上的框只能告诉模型「大概这一片」，一片里有十来个词时它只能猜（2026-11-07 用户：「问这个单词是什么意思，它识别不到我说的是哪个」）。
/// 用文字直接告诉它「指针下是 EOL，这一行是 …」，问词、问一行代码就不会对错地方。
public struct PointerText: Equatable, Sendable {
    /// 指针正下方的词（英文按单词，中文按一个字）；没认出来是 nil
    public var word: String?
    /// 这个词在截图里的位置（原图像素，原点左上）：截图上的框只框住它
    public var wordBox: CGRect?
    /// 词所在的那一行
    public var line: String?
    /// 上下文：从上到下几行，包含 line 本身
    public var context: [String]
    /// 用户选中的文字（辅助功能读到的）；有它就以它为准
    public var selection: String?
    /// 指针下这一片像代码（或者指针所在的 App 是编辑器、终端）
    public var looksLikeCode: Bool
    /// 指针所在窗口的 App 名字（「终端」「Visual Studio Code」），给模型一点背景
    public var appName: String?

    public init(word: String? = nil, wordBox: CGRect? = nil, line: String? = nil, context: [String] = [],
                selection: String? = nil, looksLikeCode: Bool = false, appName: String? = nil) {
        self.word = word
        self.wordBox = wordBox
        self.line = line
        self.context = context
        self.selection = selection
        self.looksLikeCode = looksLikeCode
        self.appName = appName
    }

    public var isEmpty: Bool { word == nil && line == nil && selection == nil }

    /// 发给模型的那段文字，放在两张截图后面、问题前面。认字可能有个别错，所以写明以截图为准
    public var promptText: String? {
        guard !isEmpty else { return nil }
        var parts: [String] = []
        if let appName { parts.append("指针所在的窗口是「\(appName)」。") }
        if let selection {
            parts.append("用户选中了这段文字（问「这个」「这段」「这句」时多半就是指它）：\n```\n\(selection)\n```")
        }
        if let word {
            var s = "指针正指着「\(word)」"
            if let line, line != word { s += "，在这一行：\(line)" }
            parts.append(s + "。问「这个词」「这是什么」「这行」时，指的就是它。")
        }
        if context.count > 1 {
            parts.append("指针周围的几行（本机认出来的文字，从上到下）：\n```\n\(context.joined(separator: "\n"))\n```")
        }
        parts.append("以上文字是本机认出来的，个别字符可能认错，和截图对不上时以截图为准。")
        return parts.joined(separator: "\n")
    }
}

/// 文字识别的一行：整行的字、整行的框，和切好的词（各带框）。坐标都是原图像素、原点左上
public struct OCRLine: Equatable, Sendable {
    public struct Token: Equatable, Sendable {
        public let text: String
        public let box: CGRect
        public init(text: String, box: CGRect) { self.text = text; self.box = box }
    }

    public let text: String
    public let box: CGRect
    public let tokens: [Token]

    public init(text: String, box: CGRect, tokens: [Token]) {
        self.text = text
        self.box = box
        self.tokens = tokens
    }

    /// 一行里能单独问的词：英文、数字、下划线连着的算一个词（snake_case、v1.2 这种带点的拆开），中日韩文字一个字一个。
    /// 返回 UTF-16 范围，好去问 Vision 每个词的框
    public static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if isCJK(c) {
                ranges.append(i..<text.index(after: i))
                i = text.index(after: i)
            } else if isWordChar(c) {
                var j = text.index(after: i)
                while j < text.endIndex, isWordChar(text[j]) || (text[j] == "'" && j < text.index(before: text.endIndex) && isWordChar(text[text.index(after: j)])) {
                    j = text.index(after: j)
                }
                ranges.append(i..<j)
                i = j
            } else {
                i = text.index(after: i)
            }
        }
        return ranges
    }

    static func isWordChar(_ c: Character) -> Bool {
        guard !isCJK(c) else { return false }
        return c.isLetter || c.isNumber || c == "_"
    }

    static func isCJK(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x3040...0x30FF).contains(v)
            || (0xAC00...0xD7AF).contains(v) || (0xF900...0xFAFF).contains(v)
    }
}

public enum PointerTextPicker {
    /// 指针离词多远（点）以内才算「指着它」。指针尖常常落在两行之间或字的边上
    public static let hitSlop: CGFloat = 6
    /// 上下文最多取上下各几行
    public static let contextLines = 4

    /// 从识别结果里挑出指针下的词、那一行和上下几行。scale：像素 / 点（Retina 是 2）
    public static func pick(lines: [OCRLine], pointer: CGPoint, scale: CGFloat) -> PointerText {
        let slop = hitSlop * scale
        var best: (distance: CGFloat, line: Int, token: OCRLine.Token)?
        for (li, line) in lines.enumerated() {
            for token in line.tokens {
                let d = distance(from: pointer, to: token.box)
                guard d <= slop else { continue }
                if best == nil || d < best!.distance { best = (d, li, token) }
            }
        }
        // 没有词在指针下，但指针落在一行字上（标点、符号之间）：也算指着这一行
        let lineIndex = best?.line ?? lines.indices.first { lines[$0].box.insetBy(dx: -slop, dy: -slop).contains(pointer) }
        guard let lineIndex else { return PointerText() }
        let hit = lines[lineIndex]
        let around = context(around: lineIndex, in: lines)
        // 像不像代码看指针那一行和紧挨着的上下两行：再远的常是讲解文字（Jupyter、教程页里代码夹在段落中间）
        let at = around.firstIndex(of: hit.text) ?? 0
        let near = Array(around[max(0, at - 2)...min(around.count - 1, at + 2)])
        let code = CodeLook.lineLooksLikeCode(hit.text) || CodeLook.looksLikeCode(lines: near)
        let fix: (String) -> String = code ? CodeLook.halfWidth : { $0 }
        return PointerText(word: best?.token.text, wordBox: best?.token.box, line: fix(hit.text), context: around.map(fix),
                           looksLikeCode: code)
    }

    /// 和这一行在同一栏（横向有重叠）、上下挨着的几行，从上到下
    static func context(around index: Int, in lines: [OCRLine]) -> [String] {
        let hit = lines[index]
        let lineHeight = max(hit.box.height, 1)
        let column = lines.enumerated().filter { _, line in
            line.box.maxX > hit.box.minX - lineHeight * 2 && line.box.minX < hit.box.maxX + lineHeight * 2
                && abs(line.box.midY - hit.box.midY) <= lineHeight * 2.2 * CGFloat(contextLines)
        }
        let sorted = column.sorted { $0.element.box.midY < $1.element.box.midY }
        guard let at = sorted.firstIndex(where: { $0.offset == index }) else { return [hit.text] }
        let lo = max(0, at - contextLines), hi = min(sorted.count - 1, at + contextLines)
        return sorted[lo...hi].map(\.element.text)
    }

    static func distance(from p: CGPoint, to r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// 指针下这一片是不是代码：看字面（括号、等号、关键字、行尾分号），或者指针所在的 App 是编辑器、终端
public enum CodeLook {
    /// 认中文时 Vision 会把代码里的标点认成全角（print（"Hello, Andrew！））：换回半角再判断、再交给模型
    public static func halfWidth(_ text: String) -> String {
        let map: [Character: Character] = ["（": "(", "）": ")", "！": "!", "，": ",", "：": ":", "；": ";", "＝": "=",
                                           "［": "[", "］": "]", "｛": "{", "｝": "}", "＜": "<", "＞": ">", "＂": "\"", "＇": "'",
                                           "“": "\"", "”": "\"", "‘": "'", "’": "'", "．": ".", "＿": "_", "＃": "#", "＄": "$"]
        return String(text.map { map[$0] ?? $0 })
    }

    /// 写代码、跑命令的 App（bundle id 前缀）
    public static let codeAppPrefixes = [
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode", "com.jetbrains.", "com.google.android.studio",
        "dev.zed.Zed", "com.sublimetext.", "com.panic.Nova", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp",
        "net.kovidgoyal.kitty", "io.alacritty", "com.mitchellh.ghostty", "com.github.wez.wezterm", "co.zeit.hyper", "org.vim.MacVim",
        "com.exafunction.windsurf", "dev.orca", "com.visualstudio.code.oss",
    ]

    public static func isCodeApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return codeAppPrefixes.contains { bundleID.hasPrefix($0) }
    }

    /// 只放英文句子里几乎不会出现的写法：「for 」「if 」「return」「let 」在普通英文里也常见，不算
    private static let keywords = [
        "def ", "func ", "function ", "const ", "fn ", "elif ", "if (", "for (", "while (", "print(", "console.", "#include",
        "public ", "private ", "static ", "async ", "await ", "lambda", "self.", "this.", "=>", "->", "::", "!=", "==", "+=",
        "&&", "||", "sudo ", "npm ", "git ", "pip ", "brew ", "Traceback", "Exception", "()", "</", "/>",
    ]

    /// 几行里有一半以上带代码的痕迹，就当是代码
    public static func looksLikeCode(lines: [String]) -> Bool {
        let meaningful = lines.filter { $0.trimmingCharacters(in: .whitespaces).count >= 3 }
        guard !meaningful.isEmpty else { return false }
        let hits = meaningful.filter(lineLooksLikeCode).count
        return hits * 2 >= meaningful.count
    }

    static func lineLooksLikeCode(_ line: String) -> Bool {
        let t = halfWidth(line).trimmingCharacters(in: .whitespaces)
        if keywords.contains(where: { t.contains($0) }) { return true }
        // 报错行：SyntaxError: …、TypeError: …、NullPointerException
        if t.range(of: #"\b[A-Z][A-Za-z]*(Error|Exception)\b"#, options: .regularExpression) != nil { return true }
        if t.hasSuffix(";") || t.hasSuffix("{") || t.hasSuffix("}") || t.hasSuffix(":") && t.contains("(") { return true }
        let symbols = t.filter { "(){}[]<>=;_.$#/\\|&*\"'`".contains($0) }.count
        // 符号占到一成以上、又不是一句带标点的中文
        let cjk = t.filter(OCRLine.isCJK).count
        return cjk * 3 < t.count && symbols * 10 >= t.count
    }
}

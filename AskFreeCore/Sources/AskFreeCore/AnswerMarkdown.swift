import Foundation

/// 回答是轻量 Markdown（面板会渲染），拿到别处用纯文本。
/// 代码块外：小标题去掉 #、加粗去掉 **、行内代码去掉反引号、条目统一成「• 」/「1. 」、多余空行合并；
/// 代码块（``` 之间）里的每一行原样保留，命令和模板字符串里的反引号、缩进、** 都不动
public enum AnswerMarkdown {
    /// 「复制」用：``` 那一行也留着，贴到别处还是代码块
    public static func plainText(_ md: String) -> String { convert(md, keepFences: true) }

    /// 追问时折起来的上一轮、历史列表的摘要用：再去掉 ``` 那一行，代码去掉首尾空格、跳过空行
    public static func preview(_ md: String) -> String { convert(md, keepFences: false) }

    private static func convert(_ md: String, keepFences: Bool) -> String {
        var lines: [String] = []
        var inCode = false
        for raw in md.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                if keepFences { lines.append(raw) }
                continue
            }
            if inCode {
                if keepFences { lines.append(raw) } else if !trimmed.isEmpty { lines.append(trimmed) }
                continue
            }
            var line = trimmed
            if line.hasPrefix("#") { line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            line = line.replacingOccurrences(of: "**", with: "")
            line = line.replacingOccurrences(of: "`", with: "")
            line = line.replacingOccurrences(of: #"^[-•·*]\s+"#, with: "• ", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^(\d+)[.、)）]\s+"#, with: "$1. ", options: .regularExpression)
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }   // 合并连续空行、去掉开头空行
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

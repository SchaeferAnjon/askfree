import Foundation

/// 回答是轻量 Markdown（面板会渲染）。复制到别处、追问时折起来的上一轮预览、历史列表的摘要用纯文本：
/// 小标题去掉 #、加粗去掉 **、行内代码去掉反引号、代码块的 ``` 那一行去掉、条目统一成「• 」/「1. 」、多余空行合并
public enum AnswerMarkdown {
    public static func plainText(_ md: String) -> String {
        var lines: [String] = []
        for raw in md.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { continue }
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

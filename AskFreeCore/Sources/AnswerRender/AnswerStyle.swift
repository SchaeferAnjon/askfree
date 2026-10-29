import AskFreeCore
import SwiftUI

/// 回答正文的一套排版：字号、行距、颜色。面板和历史页各一套（App 里 AnswerStyle+Theme 用 Theme 的动态色填）
public struct AnswerStyle: Hashable {
    /// 正文字号（面板 14、历史 13.5）
    public var bodySize: CGFloat
    /// 段落、条目的行距（面板 5、历史 3）
    public var lineSpacing: CGFloat
    /// 小标题的行距（面板 0、历史 3）
    public var headingLineSpacing: CGFloat
    /// 小标题上面多留的空（不是第一块时；面板 6、历史 2）
    public var headingTopPadding: CGFloat
    /// 块与块之间
    public var blockSpacing: CGFloat
    /// 公式字号：正文的 1.1 倍（面板 15.5、历史 15）
    public var mathSize: CGFloat
    /// 代码和排不出来的公式源码：等宽 12.5
    public var codeSize: CGFloat
    /// 文字能不能选中（历史页能、面板不能）
    public var selectable: Bool

    public var text: Color
    public var text2: Color
    public var text3: Color
    public var codeBackground: Color
    public var codeBorder: Color

    public init(bodySize: CGFloat, lineSpacing: CGFloat, headingLineSpacing: CGFloat, headingTopPadding: CGFloat,
                blockSpacing: CGFloat = 8, mathSize: CGFloat, codeSize: CGFloat = 12.5, selectable: Bool,
                text: Color, text2: Color, text3: Color, codeBackground: Color, codeBorder: Color) {
        self.bodySize = bodySize
        self.lineSpacing = lineSpacing
        self.headingLineSpacing = headingLineSpacing
        self.headingTopPadding = headingTopPadding
        self.blockSpacing = blockSpacing
        self.mathSize = mathSize
        self.codeSize = codeSize
        self.selectable = selectable
        self.text = text
        self.text2 = text2
        self.text3 = text3
        self.codeBackground = codeBackground
        self.codeBorder = codeBorder
    }

    /// 跟着条目的代码块、公式缩进到条目文字那一列：编号 18 宽 + 间距 8，圆点 3 + 4 + 8
    static func indent(_ attached: ListIndent?) -> CGFloat {
        switch attached {
        case .numbered: return 26
        case .bullet: return 15
        case nil: return 0
        }
    }
}

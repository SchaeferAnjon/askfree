import SwiftUI
#if canImport(AnswerRender)
import AnswerRender
#endif

/// 回答正文的两套排版（AnswerRender 的 AnswerBody 用），颜色全是 Theme 的动态色：面板切外观时不用重画
extension AnswerStyle {
    /// 回答面板：正文 14、行距 5，公式 15.5，不能选中
    static let panel = AnswerStyle(bodySize: 14, lineSpacing: 5, headingLineSpacing: 0, headingTopPadding: 6, mathSize: 15.5,
                                   selectable: false, text: Theme.text, text2: Theme.text2, text3: Theme.text3,
                                   codeBackground: Theme.hover, codeBorder: Theme.border)
    /// 历史详情：正文 13.5、行距 3，公式 15，文字能选中
    static let history = AnswerStyle(bodySize: 13.5, lineSpacing: 3, headingLineSpacing: 3, headingTopPadding: 2, mathSize: 15,
                                     selectable: true, text: Theme.text, text2: Theme.text2, text3: Theme.text3,
                                     codeBackground: Theme.hover, codeBorder: Theme.border)
}

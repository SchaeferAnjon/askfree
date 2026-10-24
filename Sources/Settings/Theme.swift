// Theme.swift
// Ask Free
//
// 主窗口和欢迎引导的设计 token（DESIGN.md）：和 GetNewWord 新版同一套灰阶、圆角和组件，
// 主色换成 Ask Free 图标里指针的墨黑：浅色黑底白字，深色反过来。
// 颜色全是动态色，跟着窗口的浅色 / 深色走（主窗口的深浅由「通用 → 外观」控制）。

import SwiftUI
import AppKit

enum Theme {
    private static func dyn(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    // MARK: 颜色
    static let bg        = dyn(light: rgb(250, 250, 251), dark: rgb(22, 23, 26))
    /// 侧栏、示意图的底
    static let surface   = dyn(light: rgb(244, 244, 246), dark: rgb(28, 29, 32))
    /// 卡片
    static let elevated  = dyn(light: rgb(255, 255, 255), dark: rgb(35, 36, 40))
    static let hover     = dyn(light: rgb(0, 0, 0, 0.04), dark: rgb(255, 255, 255, 0.04))
    static let selected  = dyn(light: rgb(0, 0, 0, 0.07), dark: rgb(255, 255, 255, 0.08))
    static let border    = dyn(light: rgb(0, 0, 0, 0.09), dark: rgb(255, 255, 255, 0.08))
    static let borderStrong = dyn(light: rgb(0, 0, 0, 0.16), dark: rgb(255, 255, 255, 0.14))

    static let text      = dyn(light: rgb(24, 25, 28), dark: rgb(237, 237, 239))
    static let text2     = dyn(light: rgb(95, 99, 108), dark: rgb(150, 155, 165))
    static let text3     = dyn(light: rgb(150, 154, 162), dark: rgb(100, 106, 118))

    /// 主色：墨黑（深色模式是近白）。只给实心主按钮、开着的开关、选中的单选和卡片、焦点框
    static let ink       = dyn(light: rgb(17, 17, 19), dark: rgb(237, 237, 239))
    /// 墨黑底上的字
    static let onInk     = dyn(light: rgb(255, 255, 255), dark: rgb(22, 23, 26))
    static let warn      = dyn(light: rgb(205, 125, 20), dark: rgb(242, 158, 64))
    static let danger    = dyn(light: rgb(200, 60, 60), dark: rgb(230, 92, 92))
    static let ok        = dyn(light: rgb(40, 150, 90), dark: rgb(92, 194, 133))
    /// 截图里标指针位置的细红框，只出现在示意图和截图里
    static let marker    = Color(nsColor: rgb(230, 60, 60))
}

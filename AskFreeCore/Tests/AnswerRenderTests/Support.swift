import AppKit
import SwiftUI
import XCTest
@testable import AnswerRender
@testable import AskFreeCore

/// 和 App 的 Theme（Sources/Settings/Theme.swift）同样的值：测试里不能引 App 的模块
enum TestTheme {
    static func dynNS(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    private static func dyn(light: NSColor, dark: NSColor) -> Color { Color(nsColor: dynNS(light: light, dark: dark)) }
    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
    static let bgNS = dynNS(light: rgb(250, 250, 251), dark: rgb(22, 23, 26))
    static let elevatedNS = dynNS(light: rgb(255, 255, 255), dark: rgb(35, 36, 40))
    static let hoverNS = dynNS(light: rgb(0, 0, 0, 0.04), dark: rgb(255, 255, 255, 0.04))
    static let textNS = dynNS(light: rgb(24, 25, 28), dark: rgb(237, 237, 239))
    static let bg = Color(nsColor: bgNS)
    static let elevated = Color(nsColor: elevatedNS)
    static let hover = Color(nsColor: hoverNS)
    static let border = dyn(light: rgb(0, 0, 0, 0.09), dark: rgb(255, 255, 255, 0.08))
    static let text = Color(nsColor: textNS)
    static let text2 = dyn(light: rgb(95, 99, 108), dark: rgb(150, 155, 165))
    static let text3 = dyn(light: rgb(150, 154, 162), dark: rgb(100, 106, 118))

    /// 和 App 的 AnswerStyle.panel / .history 一样
    static let panel = AnswerStyle(bodySize: 14, lineSpacing: 5, headingLineSpacing: 0, headingTopPadding: 6, mathSize: 15.5,
                                   selectable: false, text: text, text2: text2, text3: text3, codeBackground: hover, codeBorder: border)
    static let history = AnswerStyle(bodySize: 13.5, lineSpacing: 3, headingLineSpacing: 3, headingTopPadding: 2, mathSize: 15,
                                     selectable: true, text: text, text2: text2, text3: text3, codeBackground: hover, codeBorder: border)
}

/// 屏幕外的一个无边框窗口，NSHostingView 放进去排版、画成位图（和原型 main.swift 一样）
@MainActor
enum Offscreen {
    static let window: NSWindow = {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let w = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        return w
    }()

    static func host<V: View>(_ view: V, dark: Bool) -> NSHostingView<V> {
        let h = NSHostingView(rootView: view)
        h.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.appearance = h.appearance
        window.contentView = h
        return h
    }

    /// 量好尺寸、铺满再画
    @discardableResult
    static func fit<V: View>(_ h: NSHostingView<V>) -> NSSize {
        h.layoutSubtreeIfNeeded()
        let size = h.fittingSize
        h.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        h.layoutSubtreeIfNeeded()
        return size
    }

    static func bitmap<V: View>(_ h: NSHostingView<V>) -> NSBitmapImageRep {
        fit(h)
        h.display()
        let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!
        h.cacheDisplay(in: h.bounds, to: rep)
        return rep
    }

    static func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}

/// 面板里的样子：卡片宽 400、左右各 16、上 14 下 6，底色 bg
struct PanelCard: View {
    let markdown: String
    var streaming = false
    var width: CGFloat = 368
    var style: AnswerStyle = TestTheme.panel

    var body: some View {
        AnswerBody(markdown: markdown, streaming: streaming, style: style)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .background(style.selectable ? TestTheme.bg : TestTheme.bg)
    }
}

enum Fixtures {
    static let directory = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")

    struct Chunk: Decodable { let t_ms: Int; let text: String }
    struct Chunks: Decodable { let question: String; let chunks: [Chunk] }

    static func chunks(_ name: String) -> [Chunk] {
        let url = name.hasSuffix("long-mixed") ? directory.appendingPathComponent("long-mixed.chunks.json")
            : directory.appendingPathComponent("samples/\(name).chunks.json")
        return try! JSONDecoder().decode(Chunks.self, from: Data(contentsOf: url)).chunks
    }

    static func answer(_ name: String) -> String { chunks(name).map(\.text).joined() }

    static var sampleNames: [String] {
        let files = try! FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("samples").path)
        return files.filter { $0.hasSuffix(".chunks.json") }.map { String($0.dropLast(".chunks.json".count)) }.sorted()
    }

    struct Formula: Decodable { let file: String; let delim: String; let display: Bool; let tex: String }
    static func formulas(_ file: String) -> [Formula] {
        try! JSONDecoder().decode([Formula].self, from: Data(contentsOf: directory.appendingPathComponent(file)))
    }

    static func text(_ file: String) -> String {
        try! String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
    }
}

func ms(since start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 }

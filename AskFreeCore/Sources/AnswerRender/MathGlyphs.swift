import AppKit
import CoreText
import SwiftMath

/// 一条公式排好的样子：模板图（用的时候跟字一个颜色）和基线在图底边往上多高
public struct MathGlyph {
    public let image: NSImage
    /// 图的底边到公式基线的距离：放进一行字里时往下挪这么多，公式的基线就落在字的基线上
    public let descent: CGFloat
    public var size: CGSize { image.size }
}

/// SwiftMath 排公式（Latin Modern Math），画成 2 倍的模板图。只在主线程用。
/// 同一条公式（同样的模式和字号）每次拿到的是同一张图：流式出字时整段反复重画，图不变就不闪
@MainActor
public enum MathGlyphs {
    /// 超过这么长的公式不排，显示源码
    static let maxLength = 2000
    /// 括号套得太深的不排（SwiftMath 的解析是递归的）
    static let maxBraceDepth = 40
    static let cacheLimit = 300
    /// 图四周留的空：斜体字母、积分号会伸出排版框一点点
    static let pad: CGFloat = 1

    private static var cache: [String: MathGlyph?] = [:]
    private static var order: [String] = []
    private static var fonts: [CGFloat: MTFont] = [:]
    private static let label: MTMathUILabel = {
        let label = MTMathUILabel()
        label.textAlignment = .left
        label.displayErrorInline = false
        return label
    }()

    /// 排一条公式。排不出来（SwiftMath 不认、太长、套得太深）返回 nil，调用方显示源码
    public static func glyph(_ tex: String, display: Bool, size: CGFloat) -> MathGlyph? {
        let key = "\(display ? "D" : "T")\(size)|\(tex)"
        if let hit = cache[key] {
            touch(key)
            return hit
        }
        let made = make(tex, display: display, size: size)
        cache[key] = .some(made)
        order.append(key)
        if order.count > cacheLimit {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        return made
    }

    /// 进程里第一条公式要读字体和数学表（几十毫秒）：启动后找个空闲时刻先排一条，第一次回答时就不卡。返回用了多少毫秒
    @discardableResult
    public static func warmUp() -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        _ = make("x^2+\\frac{1}{2}", display: false, size: 15.5)
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    /// 自测用：字体资源在不在、排不排得出来
    public static func selfCheck() -> Bool {
        make("x^2", display: false, size: 15.5) != nil
    }

    static func cachedCount() -> Int { cache.count }
    static func resetCache() { cache.removeAll(); order.removeAll() }

    private static func touch(_ key: String) {
        guard order.last != key, let i = order.lastIndex(of: key) else { return }
        order.remove(at: i)
        order.append(key)
    }

    private static func font(_ size: CGFloat) -> MTFont? {
        if let f = fonts[size] { return f }
        guard let base = MTFontManager().latinModernFont(withSize: size) else { return nil }
        // MTFontManager 按名字缓存的那份是共用的：拷一份自己的再加中文兜底，\text{速度} 也能显示
        let f = base.copy(withSize: size)
        f.fallbackFont = CTFontCreateWithName("PingFangSC-Regular" as CFString, size, nil)
        fonts[size] = f
        return f
    }

    private static func make(_ tex: String, display: Bool, size: CGFloat) -> MathGlyph? {
        let source = display ? normalize(tex) : sideLimits(normalize(tex))
        guard !source.isEmpty, source.count <= maxLength, braceDepth(source) <= maxBraceDepth, let font = font(size) else { return nil }
        let label = Self.label
        label.font = font
        label.labelMode = display ? .display : .text
        label.latex = source
        guard label.error == nil else { return nil }
        // 宽度不设上限（frame 为零 = 不折行），排一次
        label.frame = .zero
        label.layout()
        guard let list = label.displayList, list.width > 0, list.ascent + list.descent > 0 else { return nil }
        let w = ceil(list.width + pad * 2)
        let h = ceil(list.ascent + list.descent + pad * 2)
        guard w < 8000, h < 2000 else { return nil }
        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(w * scale), height: Int(h * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        // label 把公式摆在 y = (0 − max(高, label.fontSize / 2)) / 2 + descent（它的 frame 是零）。挪到基线离图底边 pad + descent 的地方
        let labelBaseline = -max(list.ascent + list.descent, label.fontSize / 2) / 2 + list.descent
        ctx.translateBy(x: pad, y: pad + list.descent - labelBaseline)
        // 分数线、根号上那条横线是 NSBezierPath 画的，画进「当前」的 NSGraphicsContext：得把它指到这张图上
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        list.draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        image.isTemplate = true
        return MathGlyph(image: image, descent: pad + list.descent)
    }

    // MARK: - 排版前的替换

    /// 模型常写、SwiftMath 不认的几个写法换成它认的；颜色、编号去掉（公式只用字色）
    public static func normalize(_ tex: String) -> String {
        var t = tex
        t = t.replacingOccurrences(of: #"\\dots(?![A-Za-z])"#, with: "\\\\ldots", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\\tfrac(?![A-Za-z])"#, with: "\\\\frac", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\\begin\{align\*?\}"#, with: "\\\\begin{aligned}", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\\end\{align\*?\}"#, with: "\\\\end{aligned}", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\\(begin|end)\{equation\*?\}"#, with: "", options: .regularExpression)
        t = unwrap(t, command: "\\boxed", keepArgument: 0, arguments: 1)
        t = unwrap(t, command: "\\tag*", keepArgument: nil, arguments: 1)
        t = unwrap(t, command: "\\tag", keepArgument: nil, arguments: 1)
        t = unwrap(t, command: "\\textcolor", keepArgument: 1, arguments: 2)
        t = unwrap(t, command: "\\color", keepArgument: nil, arguments: 1)
        t = joinSoftLineBreaks(t)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 行内公式里 ∑、∏、lim 的上下限照 TeX 的行内样子写在右下、右上（SwiftMath 默认摞在上下，一行字被撑得很高）
    static func sideLimits(_ tex: String) -> String {
        tex.replacingOccurrences(of: #"\\(sum|prod|coprod|bigcup|bigcap|bigoplus|bigotimes|lim|limsup|liminf|max|min|sup|inf)(?![A-Za-z])(?!\s*\\(no)?limits)"#,
                                 with: "\\\\$1\\\\nolimits", options: .regularExpression)
    }

    /// \cmd{a}{b}…：整个换成第 keepArgument 个参数（nil = 整个删掉）。按括号层数配对；后面不是命令名的延续才算
    static func unwrap(_ tex: String, command: String, keepArgument: Int?, arguments: Int) -> String {
        var s = Array(tex)
        let cmd = Array(command)
        var i = 0
        while i + cmd.count <= s.count {
            guard Array(s[i..<(i + cmd.count)]) == cmd, i + cmd.count == s.count || !s[i + cmd.count].isLetter else {
                i += 1
                continue
            }
            var j = i + cmd.count
            var args: [[Character]] = []
            var ok = true
            for _ in 0..<arguments {
                while j < s.count, s[j] == " " { j += 1 }
                guard j < s.count, s[j] == "{" else { ok = false; break }
                var depth = 0
                var k = j
                while k < s.count {
                    if s[k] == "\\" { k += 2; continue }
                    if s[k] == "{" { depth += 1 } else if s[k] == "}" { depth -= 1; if depth == 0 { break } }
                    k += 1
                }
                guard k < s.count else { ok = false; break }
                args.append(Array(s[(j + 1)..<k]))
                j = k + 1
            }
            guard ok else { i += 1; continue }
            let replacement = keepArgument.map { args[$0] } ?? []
            s.replaceSubrange(i..<j, with: replacement)
            i += replacement.count
        }
        return String(s)
    }

    /// 不属于 `\\` 的单个反斜杠后面跟换行：换成空格
    static func joinSoftLineBreaks(_ tex: String) -> String {
        guard tex.contains("\\\n") else { return tex }
        var out: [Character] = []
        var run = 0
        for c in tex {
            if c == "\n", run % 2 == 1 {
                out.removeLast()
                out.append(" ")
                run = 0
                continue
            }
            run = c == "\\" ? run + 1 : 0
            out.append(c)
        }
        return String(out)
    }

    static func braceDepth(_ tex: String) -> Int {
        var depth = 0, deepest = 0
        var escaped = false
        for c in tex {
            if escaped { escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "{" { depth += 1; deepest = max(deepest, depth) } else if c == "}" { depth -= 1 }
        }
        return deepest
    }
}

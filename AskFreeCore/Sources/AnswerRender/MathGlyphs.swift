import AppKit
import AskFreeCore
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
/// 同一条公式（同样的模式和字号）每次拿到的是同一张图：流式出字时整段反复重画，图不变就不闪。
/// 排之前改几处 SwiftMath 和 TeX 不一样的地方（TeXTweaks，task-lue8s 设计评审 2–4）：
/// sin、det、∑ 这类算子后面紧跟字母时补一个细空；矩阵、cases 格子开头的负号是一元的，不留空；
/// 行内的 ∑、∫ 用基本字形（不换大一号的）；行内顶层的分数照 TeX 的文本样式，分子分母缩到 0.7 倍（分开排再拼起来）
@MainActor
public enum MathGlyphs {
    static let cacheLimit = 300
    /// 图左右留的空：斜体字母、积分号会伸出排版框一点点（上下按墨迹裁，独立公式上下也留这么多）
    static let pad: CGFloat = 1
    /// 行内分数的分子分母：TeX 文本样式里是上下标字号，Latin Modern Math 是正文的 70%
    static let inlineFractionScale: CGFloat = 0.7
    /// Latin Modern Math 的数学轴（分数线、加减号的高度），单位 em
    static let axisHeight: CGFloat = 0.25
    /// 根号、分数这类能一层套一层的命令超过这么多个不排（几百层根号要排好几百毫秒），显示源码
    static let maxNestingCommands = 60
    /// 公式图的画布面积上限（点²，2 倍图再乘 4）：再大的显示源码
    static let maxCanvasArea: CGFloat = 2_000_000

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
        let normalized = normalize(tex)
        guard !normalized.isEmpty, normalized.count <= TeXFlatten.maxLength, TeXFlatten.braceDepth(normalized) <= TeXFlatten.maxBraceDepth,
              nestingCommands(normalized) <= maxNestingCommands else { return nil }
        let source = display ? TeXTweaks.common(normalized) : sideLimits(TeXTweaks.inline(normalized))
        // 分开排的哪一段排不出来，就整条照常排
        if !display, let parts = TeXTweaks.splitAtFractions(source), let glyph = compose(parts, size: size) { return glyph }
        guard let canvas = render(source, display: display, size: size) else { return nil }
        return crop(canvas, display: display)
    }

    /// \sqrt、\frac 这类命令一共几个
    static func nestingCommands(_ tex: String) -> Int {
        var n = 0
        var rest = Substring(tex)
        while let r = rest.range(of: "\\") {
            rest = rest[r.upperBound...]
            for name in ["sqrt", "frac", "dfrac", "tfrac", "cfrac", "binom"] where rest.hasPrefix(name) { n += 1; break }
        }
        return n
    }

    // MARK: - 画

    /// 一条排好、画在大画布上的公式：box 是 SwiftMath 给的排版框，baseline 是基线高，单位点，原点在画布左下
    struct Canvas {
        let context: CGContext
        let pixelWidth: Int
        let pixelHeight: Int
        let width: CGFloat
        let height: CGFloat
        var box: CGRect
        let baseline: CGFloat
        static let scale: CGFloat = 2
    }

    /// 排好画在画布上：先画在比排版框四周各大 margin 的画布上，裁的时候再按墨迹裁。
    /// SwiftMath 给的高低有时不准（\scriptstyle 那一组的框比字高出一截），只信框会切掉字或留一大块空
    private static func render(_ source: String, display: Bool, size: CGFloat) -> Canvas? {
        guard let font = font(size) else { return nil }
        let label = Self.label
        label.font = font
        label.labelMode = display ? .display : .text
        label.latex = source
        guard label.error == nil else { return nil }
        // 宽度不设上限（frame 为零 = 不折行），排一次
        label.frame = .zero
        label.layout()
        guard let display = label.displayList, display.width > 0, display.ascent + display.descent > 0 else { return nil }
        let margin = ceil(size * 0.6)
        let boxW = ceil(display.width), boxH = ceil(display.ascent + display.descent)
        let width = boxW + margin * 2, height = boxH + margin * 2
        guard width < 8000, height < 2000, width * height < maxCanvasArea else { return nil }
        let pw = Int(width * Canvas.scale), ph = Int(height * Canvas.scale)
        guard let ctx = bitmap(pw, ph) else { return nil }
        ctx.scaleBy(x: Canvas.scale, y: Canvas.scale)
        // label 把公式摆在 y = (0 − max(高, label.fontSize / 2)) / 2 + descent（它的 frame 是零）。挪到基线离画布底边 margin + descent 的地方
        let labelBaseline = -max(display.ascent + display.descent, label.fontSize / 2) / 2 + display.descent
        let baseline = margin + display.descent
        ctx.translateBy(x: margin, y: baseline - labelBaseline)
        // 分数线、根号上那条横线是 NSBezierPath 画的，画进「当前」的 NSGraphicsContext：得把它指到这张图上
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        display.draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return Canvas(context: ctx, pixelWidth: pw, pixelHeight: ph, width: width, height: height,
                      box: CGRect(x: margin, y: margin, width: display.width, height: boxH), baseline: baseline)
    }

    private static func bitmap(_ pw: Int, _ ph: Int) -> CGContext? {
        CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// 裁成最后的图。横向是排版框和墨迹的并集（斜体伸出去的不切，框里的空照留），左右各留 pad；
    /// 竖向独立公式也取并集再留 pad（上下留白和原来一样），行内公式只按墨迹（框比字高时一行字不被撑高）
    private static func crop(_ canvas: Canvas, display: Bool) -> MathGlyph? {
        var keep = canvas.box
        if let ink = inkBounds(canvas) {
            keep = keep.union(ink)
            if !display { keep = CGRect(x: keep.minX, y: ink.minY, width: keep.width, height: ink.height) }
        }
        keep = keep.insetBy(dx: -pad, dy: display ? -pad : 0).intersection(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        guard let full = canvas.context.makeImage() else { return nil }
        let s = Canvas.scale
        // 裁到整像素：CGImage 的 cropping 原点在左上
        let crop = CGRect(x: floor(keep.minX * s), y: floor((canvas.height - keep.maxY) * s),
                          width: ceil(keep.width * s), height: ceil(keep.height * s))
        guard let cg = full.cropping(to: crop) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: crop.width / s, height: crop.height / s))
        image.isTemplate = true
        let bottom = canvas.height - crop.maxY / s
        return MathGlyph(image: image, descent: canvas.baseline - bottom)
    }

    /// 画布上有墨迹的范围，单位点、原点在左下；一点墨迹都没有返回 nil。
    /// 竖向是真的墨迹；横向只看排版框外面那两条边（框里有没有字不要紧：裁的时候框横向整个留着），省得一个个像素看
    private static func inkBounds(_ canvas: Canvas) -> CGRect? {
        guard let data = canvas.context.data else { return nil }
        let rowBytes = canvas.context.bytesPerRow, width = canvas.pixelWidth, height = canvas.pixelHeight
        let used = width * 4
        let zero = [UInt8](repeating: 0, count: used)
        // 预乘的 RGBA：没墨迹的像素四个字节都是 0，整行和全 0 比一下就知道
        func rowHasInk(_ y: Int) -> Bool { memcmp(data + y * rowBytes, zero, used) != 0 }
        var top = 0
        while top < height, !rowHasInk(top) { top += 1 }
        guard top < height else { return nil }
        var bottom = height - 1
        while bottom > top, !rowHasInk(bottom) { bottom -= 1 }
        let s = Canvas.scale
        let boxLeft = max(0, min(width, Int(floor(canvas.box.minX * s)))), boxRight = max(0, min(width, Int(ceil(canvas.box.maxX * s))))
        var minX = boxLeft, maxX = boxRight - 1
        let pixels = data.assumingMemoryBound(to: UInt32.self)
        let stride = rowBytes / 4
        for y in top...bottom {
            let row = pixels + y * stride
            var x = 0
            while x < minX { if row[x] != 0 { minX = x; break }; x += 1 }
            x = width - 1
            while x > maxX { if row[x] != 0 { maxX = x; break }; x -= 1 }
        }
        // 内存第 0 行是图的最上面一行
        return CGRect(x: CGFloat(minX) / s, y: CGFloat(height - 1 - bottom) / s,
                      width: CGFloat(maxX - minX + 1) / s, height: CGFloat(bottom - top + 1) / s)
    }

    // MARK: - 行内分数分开排

    /// 行内公式在顶层的分数处切开：分数用 0.7 倍字号排、分数线抬到正文字号的数学轴上，前后几段照常排，
    /// 再按基线拼成一张图。段和分数之间的空照 TeX 的 Inner 规则补（细空、中空、粗空）；
    /// 段末尾、开头是二元运算符时，它自己排会被当成一元的、两边的空没了：先在旁边垫一个「0」排，再把「0」那一截裁掉
    private static func compose(_ parts: [TeXTweaks.Part], size: CGFloat) -> MathGlyph? {
        let mu = size / 18
        struct Placed { let canvas: Canvas; let clip: ClosedRange<CGFloat>?; let raise: CGFloat; let gapBefore: CGFloat }
        var placed: [Placed] = []
        for part in parts {
            switch part.kind {
            case .fraction:
                let small = size * inlineFractionScale
                guard let c = render(part.tex, display: false, size: small) else { return nil }
                placed.append(Placed(canvas: c, clip: nil, raise: axisHeight * (size - small), gapBefore: part.gapBefore * mu))
            case .text(let padLeft, let padRight):
                guard var c = render((padLeft ? "0" : "") + part.tex + (padRight ? "0" : ""), display: false, size: size) else { return nil }
                var clip: ClosedRange<CGFloat>?
                if padLeft || padRight, let zero = zeroWidth(size) {
                    // 「0」那一截不算这一段：框缩回去，画的时候裁掉
                    let lo = c.box.minX + (padLeft ? zero : 0), hi = c.box.maxX - (padRight ? zero : 0)
                    c.box = CGRect(x: lo, y: c.box.minY, width: max(0, hi - lo), height: c.box.height)
                    clip = (padLeft ? lo : -.infinity)...(padRight ? hi : .infinity)
                }
                placed.append(Placed(canvas: c, clip: clip, raise: 0, gapBefore: part.gapBefore * mu))
            }
        }
        // 拼：每一段的排版框首尾相接（中间隔着补的空），基线对齐（分数抬高 raise）
        let margin = ceil(size * 0.6)
        let baseline = placed.map { $0.canvas.baseline - $0.raise }.max()! + margin
        var x = margin
        var origins: [CGPoint] = []
        var top: CGFloat = 0
        for p in placed {
            x += p.gapBefore
            let origin = CGPoint(x: x - p.canvas.box.minX, y: baseline + p.raise - p.canvas.baseline)
            origins.append(origin)
            top = max(top, origin.y + p.canvas.height)
            x += p.canvas.box.width
        }
        let width = ceil(x + margin), height = ceil(top)
        guard width < 8000, height < 2000, width * height < maxCanvasArea else { return nil }
        let pw = Int(width * Canvas.scale), ph = Int(height * Canvas.scale)
        guard let ctx = bitmap(pw, ph) else { return nil }
        ctx.scaleBy(x: Canvas.scale, y: Canvas.scale)
        var box = CGRect.null
        for (p, origin) in zip(placed, origins) {
            guard let image = p.canvas.context.makeImage() else { return nil }
            ctx.saveGState()
            if let clip = p.clip {
                let lo = clip.lowerBound.isFinite ? origin.x + clip.lowerBound : 0
                let hi = clip.upperBound.isFinite ? origin.x + clip.upperBound : width
                ctx.clip(to: CGRect(x: lo, y: 0, width: max(0, hi - lo), height: height))
            }
            ctx.draw(image, in: CGRect(x: origin.x, y: origin.y, width: p.canvas.width, height: p.canvas.height))
            ctx.restoreGState()
            box = box.union(p.canvas.box.offsetBy(dx: origin.x, dy: origin.y))
        }
        let canvas = Canvas(context: ctx, pixelWidth: pw, pixelHeight: ph, width: width, height: height,
                            box: CGRect(x: margin, y: box.minY, width: x - margin, height: box.height), baseline: baseline)
        return crop(canvas, display: false)
    }

    private static var zeroWidths: [CGFloat: CGFloat] = [:]

    /// 垫的那个「0」在这个字号下有多宽
    private static func zeroWidth(_ size: CGFloat) -> CGFloat? {
        if let w = zeroWidths[size] { return w }
        guard let c = render("0", display: false, size: size) else { return nil }
        zeroWidths[size] = c.box.width
        return c.box.width
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
}

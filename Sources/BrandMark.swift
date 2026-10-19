import CoreGraphics

/// Ask Free 的标志：鼠标指针 + 问号气泡。应用图标、菜单栏图标和主窗口里的 logo 都从这里画，形状只有这一份。
/// 坐标沿用 1024 的 macOS 图标网格（y 向下），圆角底板占 100...924。
/// scripts/make_icons.swift 用它生成 Resources/AskFree.icns 和 Sources/statusbar-icon*.png。
enum BrandMark {
    /// 图标底板在 1024 网格里的位置和圆角
    static let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let plateRadius: CGFloat = 185
    /// 只有图形（指针 + 气泡）时取的正方形范围，菜单栏图标用
    static let glyphBounds = CGRect(x: 247, y: 190, width: 580, height: 580)

    private static let pointer: [CGPoint] = [
        CGPoint(x: 300, y: 268), CGPoint(x: 300, y: 690), CGPoint(x: 404, y: 590), CGPoint(x: 470, y: 744),
        CGPoint(x: 540, y: 714), CGPoint(x: 474, y: 562), CGPoint(x: 616, y: 562),
    ]
    private static let pointerStroke: CGFloat = 28
    private static let bubbleCenter = CGPoint(x: 660, y: 330)
    private static let bubbleRadius: CGFloat = 128
    private static let bubbleTail: [CGPoint] = [CGPoint(x: 584, y: 428), CGPoint(x: 560, y: 482), CGPoint(x: 628, y: 452)]
    private static let questionStroke: CGFloat = 30
    private static let questionDot = CGPoint(x: 660, y: 420)
    private static let questionDotRadius: CGFloat = 17

    /// 问号上半截：圆心 (660,300)、半径 42 的弧从左边绕过顶部到右下，再一段曲线落到中线
    private static let questionLine: [CGPoint] = {
        var points: [CGPoint] = []
        let start = CGFloat.pi, end = CGFloat.pi * 2 + atan2(37, 20)
        for i in 0...48 {
            let a = start + (end - start) * CGFloat(i) / 48
            points.append(CGPoint(x: 660 + 42 * cos(a), y: 300 + 42 * sin(a)))
        }
        func cubic(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ t: CGFloat) -> CGFloat {
            let u: CGFloat = 1 - t
            let head: CGFloat = u * u * u * a + 3 * u * u * t * b
            return head + 3 * u * t * t * c + t * t * t * d
        }
        for i in 1...16 {
            let t = CGFloat(i) / 16
            points.append(CGPoint(x: cubic(680, 666, 660, 660, t), y: cubic(337, 345, 355, 371, t)))
        }
        points.append(CGPoint(x: 660, y: 379))
        return points
    }()

    /// 在 rect（y 向上的 CoreGraphics 坐标）里画图形。source 是 1024 网格里要放进 rect 的那一块。
    /// question 为 nil 时把问号抠成透明（菜单栏模板图），否则用这个颜色画问号。
    static func drawGlyph(in ctx: CGContext, rect: CGRect, source: CGRect, ink: CGColor, question: CGColor?) {
        let s = rect.width / source.width
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + (p.x - source.minX) * s, y: rect.maxY - (p.y - source.minY) * s)
        }
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(ink)
        ctx.setStrokeColor(ink)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        let arrow = CGMutablePath()
        arrow.addLines(between: pointer.map(map))
        arrow.closeSubpath()
        ctx.addPath(arrow)
        ctx.setLineWidth(pointerStroke * s)
        ctx.drawPath(using: .fillStroke)

        let c = map(bubbleCenter)
        ctx.fillEllipse(in: CGRect(x: c.x - bubbleRadius * s, y: c.y - bubbleRadius * s,
                                   width: bubbleRadius * 2 * s, height: bubbleRadius * 2 * s))
        let tail = CGMutablePath()
        tail.addLines(between: bubbleTail.map(map))
        tail.closeSubpath()
        ctx.addPath(tail)
        ctx.fillPath()

        if let question {
            ctx.setStrokeColor(question)
            ctx.setFillColor(question)
        } else {
            ctx.setBlendMode(.clear)
        }
        let line = CGMutablePath()
        line.addLines(between: questionLine.map(map))
        ctx.addPath(line)
        ctx.setLineWidth(questionStroke * s)
        ctx.strokePath()
        let d = map(questionDot)
        ctx.fillEllipse(in: CGRect(x: d.x - questionDotRadius * s, y: d.y - questionDotRadius * s,
                                   width: questionDotRadius * 2 * s, height: questionDotRadius * 2 * s))
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}

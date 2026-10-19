// 由 Sources/BrandMark.swift 生成应用图标和菜单栏图标。改了标志后在仓库根目录运行：
//   swiftc -parse-as-library -o /tmp/make_icons scripts/make_icons.swift Sources/BrandMark.swift && /tmp/make_icons
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct MakeIcons {
    static let ink = CGColor(red: 0.078, green: 0.078, blue: 0.086, alpha: 1)
    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    static func bitmap(_ size: Int, draw: (CGContext, CGFloat) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx, CGFloat(size))
        return ctx.makeImage()!
    }

    static func writePNG(_ image: CGImage, to path: String) {
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        precondition(CGImageDestinationFinalize(dest), "write failed: \(path)")
    }

    /// 应用图标：1024 网格里白色圆角底板 + 一圈极淡的描边 + 黑色图形、白色问号
    static func appIcon(_ size: Int) -> CGImage {
        bitmap(size) { ctx, n in
            let k = n / 1024
            let plate = CGRect(x: BrandMark.plate.minX * k, y: (1024 - BrandMark.plate.maxY) * k,
                               width: BrandMark.plate.width * k, height: BrandMark.plate.height * k)
            let path = CGPath(roundedRect: plate, cornerWidth: BrandMark.plateRadius * k,
                              cornerHeight: BrandMark.plateRadius * k, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(white)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.08))
            ctx.setLineWidth(max(1, 2 * k))
            ctx.strokePath()
            BrandMark.drawGlyph(in: ctx, rect: CGRect(x: 0, y: 0, width: n, height: n),
                                source: CGRect(x: 0, y: 0, width: 1024, height: 1024), ink: ink, question: white)
        }
    }

    /// 菜单栏模板图：只有图形，黑色，问号抠空；系统按深浅色自动着色
    static func menuBarIcon(_ size: Int) -> CGImage {
        bitmap(size) { ctx, n in
            BrandMark.drawGlyph(in: ctx, rect: CGRect(x: 0, y: 0, width: n, height: n),
                                source: BrandMark.glyphBounds, ink: CGColor(gray: 0, alpha: 1), question: nil)
        }
    }

    static func main() throws {
        let fm = FileManager.default
        let iconset = NSTemporaryDirectory() + "AskFree.iconset"
        try? fm.removeItem(atPath: iconset)
        try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            writePNG(appIcon(base), to: "\(iconset)/icon_\(base)x\(base).png")
            writePNG(appIcon(base * 2), to: "\(iconset)/icon_\(base)x\(base)@2x.png")
        }
        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconset, "-o", "Resources/AskFree.icns"]
        try iconutil.run()
        iconutil.waitUntilExit()
        precondition(iconutil.terminationStatus == 0, "iconutil failed")
        try fm.removeItem(atPath: iconset)

        writePNG(menuBarIcon(18), to: "Sources/statusbar-icon.png")
        writePNG(menuBarIcon(36), to: "Sources/statusbar-icon@2x.png")
        print("Wrote Resources/AskFree.icns and Sources/statusbar-icon*.png")
    }
}

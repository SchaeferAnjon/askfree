import AppKit
import ApplicationServices
import Vision
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 截屏那一刻读出指针底下的字（PointerText）：本机文字识别认指针周围一小块，辅助功能读选中的文字。
/// 都不联网；读不到就是 nil，照旧只靠截图上的框。
enum PointerReader {
    /// 认字的范围（点）：指针左右各 450、上下各 150，够一行代码和上下几行
    static let regionPointSize = CGSize(width: 900, height: 300)
    /// 选中的文字太长（整页全选）就不当「指的那段」
    static let selectionLimit = 4000

    /// 指针周围那块的文字识别。image 是整屏截图，cursorPixel、返回的框都是这张图的像素坐标（原点左上）
    static func recognize(image: CGImage, around cursorPixel: CGPoint, scale: CGFloat) -> [OCRLine] {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let region = CGRect(x: cursorPixel.x - regionPointSize.width / 2 * scale,
                            y: cursorPixel.y - regionPointSize.height / 2 * scale,
                            width: regionPointSize.width * scale, height: regionPointSize.height * scale)
            .intersection(full).integral
        guard !region.isNull, region.width > 20, region.height > 10, let crop = image.cropping(to: region) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        // 代码、术语、人名不该被「纠正」成常见词
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: crop).perform([request])
        } catch {
            return []
        }
        let w = CGFloat(crop.width), h = CGFloat(crop.height)
        // Vision 的框是 0 到 1、原点左下，换成整屏图的像素、原点左上
        func toPixel(_ r: CGRect) -> CGRect {
            CGRect(x: region.minX + r.minX * w, y: region.minY + (1 - r.maxY) * h, width: r.width * w, height: r.height * h)
        }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            let tokens = OCRLine.wordRanges(in: text).compactMap { range -> OCRLine.Token? in
                guard let box = (try? candidate.boundingBox(for: range))?.boundingBox else { return nil }
                return OCRLine.Token(text: String(text[range]), box: toPixel(box))
            }
            return OCRLine(text: text, box: toPixel(observation.boundingBox), tokens: tokens)
        }
    }

    /// 用户在指针所在的那个控件里选中的文字（辅助功能接口）。别处早先选中的不算：控件得包住指针。
    /// point 是 Quartz 全局坐标（原点左上），和辅助功能的坐标系一样。对方 App 卡住时最多等 0.25 秒
    static func selectedText(at point: CGPoint) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        guard let focused = value(system, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard let raw = value(element, kAXSelectedTextAttribute) as? String else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= selectionLimit else { return nil }
        if let frame = frame(of: element), !frame.insetBy(dx: -8, dy: -8).contains(point) { return nil }
        return text
    }

    /// 指针所在窗口是哪个 App：名字给模型，bundle id 用来认编辑器、终端
    static func app(pid: pid_t?) -> (name: String?, bundleID: String?) {
        guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return (nil, nil) }
        return (app.localizedName, app.bundleIdentifier)
    }

    /// 拼起来：选中的文字、认出的词和几行、像不像代码
    static func read(lines: [OCRLine], selection: String?, cursorPixel: CGPoint, scale: CGFloat, ownerPID: pid_t?) -> PointerText? {
        var text = PointerTextPicker.pick(lines: lines, pointer: cursorPixel, scale: scale)
        text.selection = selection
        let app = app(pid: ownerPID)
        text.appName = app.name
        if CodeLook.isCodeApp(bundleID: app.bundleID) { text.looksLikeCode = true }
        if let selection, !text.looksLikeCode { text.looksLikeCode = CodeLook.looksLikeCode(lines: selection.components(separatedBy: .newlines)) }
        return text.isEmpty ? nil : text
    }

    // MARK: 辅助功能

    private static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func axValue(_ element: AXUIElement, _ name: String) -> AXValue? {
        guard let v = value(element, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        return (v as! AXValue)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = axValue(element, kAXPositionAttribute), let size = axValue(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}

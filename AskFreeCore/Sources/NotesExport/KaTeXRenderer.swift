import Foundation
import JavaScriptCore

/// 公式用 KaTeX 排：随 App 带的 katex.min.js 在 JavaScriptCore 里跑，不联网、不开网页。
/// 排好的是一段 HTML（文字加样式），导出页不靠脚本就能显示公式。
/// JSContext 不能多线程同时用，所以一把锁串起来；第一次用时才载入（几十毫秒）
public final class KaTeXRenderer: @unchecked Sendable {
    public static let shared = KaTeXRenderer()

    private let lock = NSLock()
    private var context: JSContext?
    private var failedToLoad = false

    public init() {}

    /// tex → HTML；排不出来（TeX 写错、KaTeX 不认的命令）返回 nil，调用方显示源码
    public func render(_ tex: String, display: Bool) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let context = loaded() else { return nil }
        let options = JSValue(newObjectIn: context)!
        options.setValue(display, forProperty: "displayMode")
        options.setValue(true, forProperty: "throwOnError")
        options.setValue("ignore", forProperty: "strict")
        options.setValue("html", forProperty: "output")
        options.setValue(false, forProperty: "trust")
        options.setValue(200, forProperty: "maxExpand")
        context.exception = nil
        guard let katex = context.objectForKeyedSubscript("katex"),
              let result = katex.invokeMethod("renderToString", withArguments: [tex, options]),
              context.exception == nil, result.isString else {
            context.exception = nil
            return nil
        }
        return result.toString()
    }

    /// 正文里用到的 KaTeX 样式：字体只带 woff2，内嵌成 data URL（离线、拷到别的电脑都能看）
    public static func inlineCSS() -> String? {
        guard let dir = Bundle.module.url(forResource: "katex", withExtension: nil, subdirectory: "Resources"),
              var css = try? String(contentsOf: dir.appendingPathComponent("katex.min.css"), encoding: .utf8) else { return nil }
        let pattern = #"src:url\(fonts/([^)]+\.woff2)\) format\("woff2"\)[^;}]*"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = css as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: css, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let name = ns.substring(with: m.range(at: 1))
            if let data = try? Data(contentsOf: dir.appendingPathComponent("fonts/\(name)")) {
                out += "src:url(data:font/woff2;base64,\(data.base64EncodedString())) format(\"woff2\")"
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        css = out
        return css
    }

    private func loaded() -> JSContext? {
        if let context { return context }
        guard !failedToLoad else { return nil }
        guard let url = Bundle.module.url(forResource: "katex.min", withExtension: "js", subdirectory: "Resources/katex"),
              let source = try? String(contentsOf: url, encoding: .utf8), let context = JSContext() else {
            failedToLoad = true
            return nil
        }
        // KaTeX 是 UMD 包：它找 self 当全局对象
        context.evaluateScript("var self = this;")
        context.evaluateScript(source)
        guard context.exception == nil, context.objectForKeyedSubscript("katex")?.isObject == true else {
            failedToLoad = true
            return nil
        }
        self.context = context
        return context
    }
}

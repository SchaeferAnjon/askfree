// NotesExporting.swift
// Ask Free
//
// 笔记页的「用浏览器打开」「导出 PDF」落到文件上的那一段（design/daily-notes/redesign/export.md）：
// 写 HTML 文件、系统存储面板、用默认浏览器 / 默认程序打开；PDF 用不显示的 WKWebView 按 A4 打印分页，
// 再用 Core Graphics 把页码「n / m」画在每页底部（WebKit 不认 @page 的页边页码）。

import AppKit
import WebKit
import PDFKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

enum NotesExportError: LocalizedError {
    case emptyDocument
    case printFailed
    case loadFailed(String)
    /// 选的文件夹写不进去（没有权限）
    case notWritable(folder: String)

    var errorDescription: String? {
        switch self {
        case .emptyDocument: return "排出来的 PDF 是空的"
        case .printFailed: return "系统没能把笔记排成 PDF"
        case .loadFailed(let reason): return "笔记页没能载入：\(reason)"
        case .notWritable(let folder): return "\(folder) 文件夹不能写入：没有权限。换个位置再试。"
        }
    }
}

@MainActor
enum NotesFiles {
    private static let lastFolderKey = "askfree-notes-pdf-folder"

    /// HTML 写进配置目录下的 notes/（开发版自动是 askfree-dev）；每次点都重写，笔记重新整理过也是最新的
    static func writeHTML(_ html: String, name: String, in directory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent(name)
            try Data(html.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        }.value
    }

    /// 交给默认浏览器（不是 .html 关联的编辑器）：开发版带 ASKFREE_NOTES_NO_OPEN 时不真的打开，只写文件（无人值守实测用）
    static func openInBrowser(_ url: URL) async throws {
        if AppIdentity.isDevBuild, ProcessInfo.processInfo.environment["ASKFREE_NOTES_NO_OPEN"] != nil { return }
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        if let probe = URL(string: "https://example.com"), let browser = workspace.urlForApplication(toOpen: probe) {
            try await workspace.open([url], withApplicationAt: browser, configuration: configuration)
        } else {
            try await workspace.open(url, configuration: configuration)
        }
    }

    /// 存好的 PDF 用默认程序（一般是「预览」）打开；返回没打开的原因
    static func openInDefaultApp(_ url: URL) async -> String? {
        if AppIdentity.isDevBuild, ProcessInfo.processInfo.environment["ASKFREE_NOTES_NO_OPEN"] != nil { return nil }
        do {
            try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 系统存储面板：第一次放在「下载」，以后放上次选的文件夹；取消就回 nil
    static func chooseDestination(name: String, window: NSWindow?, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.title = "导出笔记 PDF"
        panel.prompt = "存储"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = name
        panel.directoryURL = lastFolder() ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let done: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.url : nil)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }

    static func rememberDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: lastFolderKey)
    }

    private static func lastFolder() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: lastFolderKey) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 家目录写成 ~；放不下由界面从开头省略，文件名留全
    static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// 笔记页排成 A4 的 PDF：不显示的 WKWebView 加载同一份 HTML，等图片和字体好了，先把页面设成浅色，
/// 再在隐藏页面里量一遍分页（paginationScript：只给会被页边切开的那一块加 .pbk，整块挪到下一页），
/// 再用 NSPrintOperation 按页边分页存成文件（不能用 createPDF：它出来的是一整张长页），最后给每页画页码。
@MainActor
final class NotesPDFPrinter: NSObject, WKNavigationDelegate {
    /// A4（点）；页边上、左、右 10 毫米，下 14 毫米（和会议字幕的 0.4 / 0.55 英寸一样）
    nonisolated static let paper = NSSize(width: 595.28, height: 841.89)
    nonisolated static let margin = (top: CGFloat(28.35), left: CGFloat(28.35), right: CGFloat(28.35), bottom: CGFloat(39.69))

    /// WebKit 打印时把页面排在「页宽的 1.25 倍」宽，再缩到页宽（实测：10 毫米页边的 A4，1 个 CSS 像素印出 0.8 点）
    nonisolated static let printScale: CGFloat = 1.25

    /// 分页脚本给多少个块加了「另起一页」（日志里看）
    private(set) var forcedBreaks = 0

    private var webView: WKWebView?
    private var window: NSWindow?
    private var loaded: CheckedContinuation<Void, Error>?
    private var printed: CheckedContinuation<Bool, Never>?

    /// 返回页数
    func render(html: String, title: String, to url: URL) async throws -> Int {
        let folder = url.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw NotesExportError.notWritable(folder: FileManager.default.displayName(atPath: folder.path))
        }
        let width = Self.paper.width - Self.margin.left - Self.margin.right
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 1000), configuration: WKWebViewConfiguration())
        web.navigationDelegate = self
        // 要在窗口里才会排版和打印；放在屏幕外面，不出现
        let host = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: width, height: 1000), styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = web
        host.orderBack(nil)
        webView = web
        window = host
        defer { host.orderOut(nil); host.contentView = nil; webView = nil; window = nil }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loaded = continuation
            web.loadHTMLString(html, baseURL: nil)
        }
        // 图片解码完、字体就位再排；打印一律浅色白底（深色的选择器比 @media print 的权重高，只写打印样式盖不住）
        _ = try await web.callAsyncJavaScript("""
            document.documentElement.setAttribute('data-theme', 'light');
            await document.fonts.ready;
            await Promise.all(Array.from(document.images).map(i => i.decode().catch(() => {})));
            return true
            """, arguments: [:], in: nil, contentWorld: .page)

        forcedBreaks = try await paginate(web, host: host, width: width)

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("askfree-notes-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let info = NSPrintInfo()
        info.paperSize = Self.paper
        info.topMargin = Self.margin.top
        info.leftMargin = Self.margin.left
        info.rightMargin = Self.margin.right
        info.bottomMargin = Self.margin.bottom
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = temporary
        let operation = web.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = NSRect(x: 0, y: 0, width: width, height: Self.paper.height - Self.margin.top - Self.margin.bottom)
        let ok: Bool = await withCheckedContinuation { continuation in
            printed = continuation
            operation.runModal(for: host, delegate: self, didRun: #selector(printDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
        guard ok else { throw NotesExportError.printFailed }
        return try await Self.numberPages(of: temporary, title: title, to: url)
    }

    /// 在隐藏页面里按打印的宽度和样式量一遍：每个「不能切开的块」（题目加截图、每条要点、代码块、独立公式……）
    /// 放不下当前这页时给它加 .pbk；比一页还高的块不动，由 WebKit 在行和行之间断。返回加了几个
    private func paginate(_ web: WKWebView, host: NSWindow, width: CGFloat) async throws -> Int {
        let layoutWidth = width * Self.printScale
        let pageHeight = (Self.paper.height - Self.margin.top - Self.margin.bottom) * Self.printScale
        let original = web.frame.size
        host.setContentSize(NSSize(width: layoutWidth, height: 1000))
        web.setFrameSize(NSSize(width: layoutWidth, height: 1000))
        defer {
            host.setContentSize(original)
            web.setFrameSize(original)
        }
        let count = try await web.callAsyncJavaScript(Self.paginationScript, arguments: ["pageHeight": pageHeight, "margin": 14],
                                                       in: nil, contentWorld: .page)
        return (count as? Int) ?? 0
    }

    private nonisolated static let paginationScript = """
        // 1 把 @media print 里的规则拿出来当普通规则用，页面就按打印的样子排（宽度是上面把窗口设成的打印排版宽度）
        const emu = document.createElement('style');
        let css = '';
        for (const sheet of document.styleSheets) {
          for (const rule of sheet.cssRules) {
            if (rule instanceof CSSMediaRule && rule.media.mediaText.includes('print')) {
              for (const inner of rule.cssRules) css += inner.cssText + '\\n';
            }
          }
        }
        emu.textContent = css;
        document.head.appendChild(emu);
        document.documentElement.style.overflow = 'hidden';
        document.querySelectorAll('.pbk').forEach(e => e.classList.remove('pbk'));
        // 2 不能切开的单位：标题和截图一起，「回答的要点」标签、小标题跟着后面第一块，每条要点、代码块、公式、段落各一块
        const units = [];
        const add = (...els) => { const list = els.filter(Boolean); if (list.length) units.push(list); };
        add(document.querySelector('.hd'));
        add(document.querySelector('.sum'));
        for (const sec of document.querySelectorAll('.sec')) {
          const head = sec.querySelector('.sech');
          const fig = sec.querySelector('figure.shot');
          const blocks = [];
          for (const child of sec.querySelectorAll('.ptsw > *')) {
            if (child.matches('ul.pts')) blocks.push(...child.children); else blocks.push(child);
          }
          let pending = [];
          if (fig) add(head, fig); else pending.push(head);
          for (const block of blocks) {
            if (block.matches('.lab, .hd3')) { pending.push(block); continue; }
            add(...pending, block);
            pending = [];
          }
          add(...pending);
        }
        add(document.querySelector('.foot'));
        // 3 从上往下排：放不下当前页的整块挪到下一页（用一个撑高的空块代替，量后面的才对），记下来
        const top = el => el.getBoundingClientRect().top + window.scrollY;
        const bottom = el => el.getBoundingClientRect().bottom + window.scrollY;
        const usable = pageHeight - margin;
        let pageTop = 0;
        const breaks = [];
        const spacers = [];
        for (const els of units) {
          const first = els[0];
          const t = top(first);
          const b = bottom(els[els.length - 1]);
          if (b - pageTop <= usable) continue;
          if (b - t > usable) {
            // 比一页还高：不动，它之后新的一页从 WebKit 自己切的地方起算
            pageTop += Math.floor((b - pageTop) / pageHeight) * pageHeight;
            continue;
          }
          const shift = pageTop + pageHeight - t;
          if (shift <= 0) { pageTop += Math.floor((t - pageTop) / pageHeight) * pageHeight; continue; }
          const spacer = document.createElement('div');
          spacer.style.cssText = 'height:' + shift + 'px;margin:0;padding:0;border:0';
          first.before(spacer);
          spacers.push(spacer);
          breaks.push(first);
          pageTop += pageHeight;
        }
        // 4 撤掉撑高的空块和模拟用的样式；只留 .pbk（往上挪到「它是父级第一个孩子」的最外层，分页符才算在这一块的开头）
        spacers.forEach(s => s.remove());
        emu.remove();
        document.documentElement.style.overflow = '';
        for (let el of breaks) {
          while (el.parentElement && el.parentElement.firstElementChild === el && !el.parentElement.matches('.page, main, body')) el = el.parentElement;
          el.classList.add('pbk');
        }
        return breaks.length;
        """

    @objc private func printDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printed?.resume(returning: success)
        printed = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: NotesExportError.loadFailed(error.localizedDescription))
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: NotesExportError.loadFailed(error.localizedDescription))
        loaded = nil
    }

    /// 每页底部正中画「n / m」（8 点，次要灰）：逐页把原来的页画进新 PDF，再叠上页码，文字照样能选能搜
    nonisolated static func numberPages(of source: URL, title: String, to destination: URL) async throws -> Int {
        try await Task.detached(priority: .userInitiated) {
            guard let document = CGPDFDocument(source as CFURL), document.numberOfPages > 0 else { throw NotesExportError.emptyDocument }
            let total = document.numberOfPages
            var box = CGRect(origin: .zero, size: paper)
            let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Ask Free"]
            guard let context = CGContext(destination as CFURL, mediaBox: &box, info as CFDictionary) else { throw NotesExportError.printFailed }
            let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 8, nil)
            for number in 1...total {
                guard let page = document.page(at: number) else { continue }
                var pageBox = page.getBoxRect(.mediaBox)
                let pageInfo = [kCGPDFContextMediaBox: Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size)] as CFDictionary
                context.beginPDFPage(pageInfo)
                context.drawPDFPage(page)
                let label = NSAttributedString(string: "\(number) / \(total)", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.59, alpha: 1),
                ])
                let line = CTLineCreateWithAttributedString(label)
                let bounds = CTLineGetBoundsWithOptions(line, [])
                context.textPosition = CGPoint(x: pageBox.midX - bounds.width / 2, y: pageBox.minY + 18)
                CTLineDraw(line, context)
                context.endPDFPage()
            }
            context.closePDF()
            return total
        }.value
    }
}

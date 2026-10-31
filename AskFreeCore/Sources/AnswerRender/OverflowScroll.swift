import AppKit
import SwiftUI

/// 比可见宽度宽的一行内容（代码块、独立公式、单独成行的宽行内公式）：横向滚，
/// 右端 24 点渐隐，告诉人后面还有、能往右滚；滚到最右端渐隐去掉。内容末尾留 trailing，滚到头时右边不贴边。
/// 渐隐是遮罩（可见区最右 24 点从实到透明），底下是什么颜色都对。
/// 可见宽、内容宽、滚到哪儿从 ScrollView 底下那个 NSScrollView 直接读（SwiftUI 的几何偏好在 ForEach 里第一遍拿不到值）
struct OverflowScroll<Content: View>: View {
    var trailing: CGFloat = 0
    @ViewBuilder let content: Content

    static var fade: CGFloat { 24 }

    @State private var geometry = ScrollGeometry()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            content
                .padding(.trailing, trailing)
                .background(ScrollProbe { geometry = $0 })
        }
        .mask(alignment: .leading) {
            if geometry.showsFade {
                HStack(spacing: 0) {
                    Rectangle().frame(width: max(0, geometry.viewport - Self.fade))
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: Self.fade)
                    Spacer(minLength: 0)
                }
            } else {
                Rectangle()
            }
        }
    }
}

/// 横向滚动的可见宽、内容宽、往右滚了多少
struct ScrollGeometry: Equatable {
    var viewport: CGFloat = 0
    var content: CGFloat = 0
    var offset: CGFloat = 0

    /// 内容比可见区宽，而且还没滚到最右
    var showsFade: Bool { content > viewport + 0.5 && offset + viewport < content - 0.5 }
}

/// 放在横向 ScrollView 的内容后面：找到它外面那个 NSScrollView，排版、滚动时报几何
private struct ScrollProbe: NSViewRepresentable {
    let onChange: (ScrollGeometry) -> Void

    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class ProbeView: NSView {
        var onChange: ((ScrollGeometry) -> Void)?
        private var last: ScrollGeometry?
        private weak var observed: NSClipView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        override func layout() {
            super.layout()
            attach()
            report()
        }

        private func attach() {
            // 系统设了「始终显示滚动条」（接着鼠标时的默认）会在块底下多出 15 点的滚动条，测出的高度就和实际对不上；
            // 一律用悬浮滚动条：滚动时才出现，不占高度
            enclosingScrollView?.scrollerStyle = .overlay
            guard let clip = enclosingScrollView?.contentView, clip !== observed else { return }
            if let old = observed { NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: old) }
            observed = clip
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipChanged), name: NSView.boundsDidChangeNotification, object: clip)
        }

        @objc private func clipChanged() { report() }

        func report() {
            guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            let geometry = ScrollGeometry(viewport: scroll.contentView.bounds.width, content: document.frame.width,
                                          offset: scroll.contentView.bounds.minX)
            guard geometry != last else { return }
            last = geometry
            // 排版当中不改 SwiftUI 的状态：下一轮再报
            DispatchQueue.main.async { [weak self] in self?.onChange?(geometry) }
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

import Foundation
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 开发版带 -stallLog 启动：量主线程每一轮连续忙了多久（RunLoop 从醒来到再次睡下），超过 16 毫秒在调试日志里记一行
/// `stall <ms> ms`。实测出字时卡不卡用（task-lue8s §11 的 P4）；启动后前 3 秒不记（启动本来就忙）。正式版不生效
enum MainThreadStallMonitor {
    static let isRequested: Bool = AppIdentity.isDevBuild && ProcessInfo.processInfo.arguments.contains("-stallLog")
    private static var observer: CFRunLoopObserver?

    static func start(log: @escaping (String) -> Void) {
        guard isRequested, observer == nil else { return }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var awakeSince: UInt64?
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let o = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { _, activity in
            let now = DispatchTime.now().uptimeNanoseconds
            if activity == .afterWaiting {
                awakeSince = now
                return
            }
            guard let since = awakeSince else { return }
            awakeSince = nil
            guard now - startedAt > 3_000_000_000 else { return }
            let ms = Double(now - since) / 1e6
            if ms > 16 { log(String(format: "stall %.1f ms", ms)) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
        observer = o
        log("Stall log on: main thread busy spans over 16 ms are logged")
    }
}

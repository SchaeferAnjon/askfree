import Cocoa
import Combine
import AudioToolbox
import AVFoundation
import ApplicationServices
#if canImport(AskFreeCore)
import AskFreeCore
#endif

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

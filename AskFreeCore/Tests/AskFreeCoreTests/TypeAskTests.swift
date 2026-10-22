import XCTest
@testable import AskFreeCore

final class TypeAskTests: XCTestCase {
    private var dir: URL!
    private var config: AskFreeConfig!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vpta-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        config = AskFreeConfig(configDir: dir, secrets: InMemorySecretStore())
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: - 双击检测

    private let ctrl = UInt64(HotkeyModifierFlags.control.rawValue)
    private let shift = UInt64(HotkeyModifierFlags.shift.rawValue)
    private let capsLock = UInt64(HotkeyModifierFlags.capsLock.rawValue)

    /// 依次喂 (flags, 时刻)，返回在第几步触发
    private func fired(_ steps: [(UInt64, TimeInterval)], detector: inout DoubleTapDetector) -> [Int] {
        steps.enumerated().compactMap { i, step in
            detector.handle(.flagsChanged(rawFlags: step.0, at: step.1)) ? i : nil
        }
    }

    func testQuickDoubleTapFires() {
        var d = DoubleTapDetector(target: .control)
        XCTAssertEqual(fired([(ctrl, 0), (0, 0.08), (ctrl, 0.25), (0, 0.33)], detector: &d), [3])
    }

    func testSingleTapDoesNotFire() {
        var d = DoubleTapDetector(target: .control)
        XCTAssertEqual(fired([(ctrl, 0), (0, 0.08)], detector: &d), [])
    }

    func testSlowSecondTapDoesNotFire() {
        var d = DoubleTapDetector(target: .control)
        XCTAssertEqual(fired([(ctrl, 0), (0, 0.08), (ctrl, 0.6), (0, 0.68)], detector: &d), [])
    }

    /// 第二下太慢不算，但它自己可以当下一次双击的第一下
    func testSlowTapStartsNewSequence() {
        var d = DoubleTapDetector(target: .control)
        XCTAssertEqual(fired([(ctrl, 0), (0, 0.08), (ctrl, 0.6), (0, 0.68), (ctrl, 0.8), (0, 0.88)], detector: &d), [5])
    }

    func testHoldIsNotATap() {
        var d = DoubleTapDetector(target: .control)
        XCTAssertEqual(fired([(ctrl, 0), (0, 0.6), (ctrl, 0.7), (0, 0.78)], detector: &d), [])
    }

    func testOtherModifierInBetweenResets() {
        var d = DoubleTapDetector(target: .control)
        XCTAssertEqual(fired([(ctrl, 0), (ctrl | shift, 0.05), (ctrl, 0.07), (0, 0.1), (ctrl, 0.2), (0, 0.25)], detector: &d), [])
    }

    func testKeyPressInBetweenResets() {
        var d = DoubleTapDetector(target: .control)
        XCTAssertFalse(d.handle(.flagsChanged(rawFlags: ctrl, at: 0)))
        XCTAssertFalse(d.handle(.flagsChanged(rawFlags: 0, at: 0.08)))
        XCTAssertFalse(d.handle(.interrupt))   // ⌃C 之类
        XCTAssertFalse(d.handle(.flagsChanged(rawFlags: ctrl, at: 0.2)))
        XCTAssertFalse(d.handle(.flagsChanged(rawFlags: 0, at: 0.25)))
    }

    func testCapsLockOnStillWorks() {
        var d = DoubleTapDetector(target: .control)
        let on = capsLock
        XCTAssertEqual(fired([(on | ctrl, 0), (on, 0.08), (on | ctrl, 0.25), (on, 0.33)], detector: &d), [3])
    }

    func testOtherTargetIgnoresControl() {
        var d = DoubleTapDetector(target: .shift)
        XCTAssertEqual(fired([(ctrl, 0), (0, 0.08), (ctrl, 0.25), (0, 0.33)], detector: &d), [])
        XCTAssertEqual(fired([(shift, 1), (0, 1.08), (shift, 1.25), (0, 1.33)], detector: &d), [3])
    }

    /// 三连击只算一次，第四下再起一轮
    func testTripleTapFiresOnce() {
        var d = DoubleTapDetector(target: .control)
        XCTAssertEqual(fired([(ctrl, 0), (0, 0.05), (ctrl, 0.15), (0, 0.2), (ctrl, 0.3), (0, 0.35)], detector: &d), [3])
    }

    // MARK: - 配置

    func testDefaultIsUnset() {
        XCTAssertNil(TypeAskHotkey.current(in: config))
        XCTAssertEqual(TypeAskHotkey.displayName(in: config), "未设置")
        XCTAssertFalse(TypeAskHotkey.isActive(in: config))
        TypeAskHotkey.set(.control, in: config)
        XCTAssertEqual(TypeAskHotkey.displayName(in: config), "双击 ⌃ Control")
        XCTAssertTrue(TypeAskHotkey.isActive(in: config))
    }

    func testSetAndClear() {
        TypeAskHotkey.set(.shift, in: config)
        XCTAssertEqual(TypeAskHotkey.current(in: config), .shift)
        TypeAskHotkey.set(nil, in: config)
        XCTAssertNil(TypeAskHotkey.current(in: config))
        XCTAssertFalse(TypeAskHotkey.isActive(in: config))
        XCTAssertEqual(TypeAskHotkey.displayName(in: config), "未设置")
    }

    /// 「看屏幕问」用右 Option：双击 Option 会撞，双击 Control 不撞
    func testConflictWithVoiceHotkeyOnSameKey() {
        AskHotkey.screen.useModifier(.rightOption, in: config)
        TypeAskHotkey.set(.option, in: config)
        XCTAssertNotNil(TypeAskHotkey.conflict(in: config))
        XCTAssertFalse(TypeAskHotkey.isActive(in: config))
        TypeAskHotkey.set(.control, in: config)
        XCTAssertNil(TypeAskHotkey.conflict(in: config))
        AskHotkey.plain.useModifier(.control, in: config)
        XCTAssertEqual(TypeAskHotkey.conflict(in: config), "和「只提问，不看屏幕」的快捷键（Control）是同一颗键")
    }

    /// 自定义组合（⌃Space）要按别的键，双击 Control 认得出来，不算撞
    func testCustomComboIsNotAConflict() {
        AskHotkey.plain.useCustom(RecordingHotkeyCustomShortcut(keyCode: 49, modifiers: .control, keyDisplay: "Space"), in: config)
        XCTAssertNil(TypeAskHotkey.conflict(in: config))
    }
}

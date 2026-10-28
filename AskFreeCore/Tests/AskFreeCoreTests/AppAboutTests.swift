import XCTest
@testable import AskFreeCore

final class ExternalLinkTests: XCTestCase {
    func testAllowsHTTPS() {
        XCTAssertNotNil(ExternalLink.allowedURL("https://askfree.us-cloud.uk"))
        XCTAssertNotNil(ExternalLink.allowedURL("https://example.com/a/b?x=1#top"))
        XCTAssertNotNil(ExternalLink.allowedURL("HTTPS://Example.com/img.jpg"))
        XCTAssertNotNil(ExternalLink.allowedURL("  https://example.com  "), "两头的空白去掉再看")
    }

    func testAllowsPlainMailto() {
        XCTAssertNotNil(ExternalLink.allowedURL("mailto:infoschaeferanjon@gmail.com"))
    }

    func testRejectsMailtoWithParameters() {
        XCTAssertNil(ExternalLink.allowedURL("mailto:a@b.com?subject=hi"))
        XCTAssertNil(ExternalLink.allowedURL("mailto:a@b.com?attach=/etc/passwd"))
        XCTAssertNil(ExternalLink.allowedURL("mailto:a@b.com,c@d.com"))
        XCTAssertNil(ExternalLink.allowedURL("mailto:"))
        XCTAssertNil(ExternalLink.allowedURL("mailto:nobody"))
    }

    func testRejectsOtherSchemes() {
        for bad in ["http://example.com", "file:///Applications/Calculator.app", "javascript:alert(1)",
                    "x-apple.systempreferences:com.apple.preference.security", "ssh://host", "vnc://10.0.0.1",
                    "smb://server/share", "tel:123", "askfree://open", "ftp://example.com/file",
                    "//example.com", "example.com", ""] {
            XCTAssertNil(ExternalLink.allowedURL(bad), bad)
        }
    }

    func testRejectsHTTPSWithoutHost() {
        XCTAssertNil(ExternalLink.allowedURL("https://"))
        XCTAssertNil(ExternalLink.allowedURL("https:example.com"))
        XCTAssertNil(ExternalLink.allowedURL("https:///path"))
    }

    func testIsAllowedOnURL() {
        XCTAssertTrue(ExternalLink.isAllowed(URL(string: "https://duckduckgo.com/i.js")!))
        XCTAssertFalse(ExternalLink.isAllowed(URL(fileURLWithPath: "/tmp/x.jpg")))
        XCTAssertFalse(ExternalLink.isAllowed(URL(string: "http://duckduckgo.com")!))
    }
}

final class AppVersionInfoTests: XCTestCase {
    func testDisplayLine() {
        let info = AppVersionInfo(version: "1.1.0", build: "3", chip: .appleSilicon, macOSVersion: "15.6.1")
        XCTAssertEqual(info.displayLine, "版本 1.1.0（3）· Apple 芯片")
        XCTAssertEqual(AppVersionInfo(version: "1.1.0", build: "3", chip: .intel, macOSVersion: "14.7").displayLine,
                       "版本 1.1.0（3）· Intel 芯片")
    }

    func testDisplayLineWithoutSeparateBuild() {
        XCTAssertEqual(AppVersionInfo(version: "1.1.0", build: "", chip: .appleSilicon, macOSVersion: "15.6").displayLine,
                       "版本 1.1.0 · Apple 芯片")
        XCTAssertEqual(AppVersionInfo(version: "1.1.0", build: "1.1.0", chip: .appleSilicon, macOSVersion: "15.6").displayLine,
                       "版本 1.1.0 · Apple 芯片")
    }

    func testCopyTextHasVersionBuildChipAndMacOS() {
        let info = AppVersionInfo(version: "1.1.0", build: "3", chip: .appleSilicon, macOSVersion: "15.6.1")
        XCTAssertEqual(info.copyText, "Ask Free 1.1.0\n构建号：3\n芯片：Apple 芯片\nmacOS：15.6.1")
        XCTAssertTrue(AppVersionInfo(version: "1.1.0", build: "", chip: .intel, macOSVersion: "14.0").copyText.contains("构建号：未知"))
    }

    func testMacOSString() {
        XCTAssertEqual(AppVersionInfo.macOSString(OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 1)), "15.6.1")
        XCTAssertEqual(AppVersionInfo.macOSString(OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)), "14.0")
    }

    func testCurrentChipMatchesBuildArchitecture() {
        #if arch(arm64)
        XCTAssertEqual(AppVersionInfo.currentChip, .appleSilicon)
        #else
        XCTAssertEqual(AppVersionInfo.currentChip, .intel)
        #endif
    }
}

final class ScreenShareSettingTests: XCTestCase {
    func testHideFromScreenShareIsOnByDefault() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("afss-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = AskFreeConfig(configDir: dir, secrets: InMemorySecretStore())
        XCTAssertTrue(config.bool(forKey: AskSettings.hideFromScreenShareKey, defaultValue: AskSettings.hideFromScreenShareDefault))
        config.save(bool: false, forKey: AskSettings.hideFromScreenShareKey)
        XCTAssertFalse(config.bool(forKey: AskSettings.hideFromScreenShareKey, defaultValue: AskSettings.hideFromScreenShareDefault))
    }
}

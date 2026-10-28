import XCTest
@testable import AskFreeCore

/// 每天匿名报到一次：同意了才报（没问过、不同意都不报）；同一个本地日期只报一次，换一天再报；
/// body 只有约定的 7 个字段、不带 Authorization；失败不抛错、这一天不记下
final class UsagePingTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("af-ping-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 测试用的可变环境：同意没有、现在几点、服务器回什么、收到了哪些请求
    private final class Env: @unchecked Sendable {
        let lock = NSLock()
        var consent: UsageConsent = .yes
        var now = Date(timeIntervalSince1970: 1_793_066_400)   // 2026-10-27 10:00 北京时间
        var status = 204
        var error: Error?
        var requests: [URLRequest] = []
        var logs: [String] = []
        var delayNanos: UInt64 = 0
    }

    private func makePing(_ env: Env, plan: String = "own") -> UsagePing {
        UsagePing(
            file: dir.appendingPathComponent("usage-ping.json"),
            api: URL(string: "http://ping.test")!,
            enabled: { env.lock.withLock { env.consent.allowsPing } },
            info: { .init(version: "1.2.0", plan: plan, lang: "zh") },
            send: { request in
                let (delay, error, status) = env.lock.withLock { () -> (UInt64, Error?, Int) in
                    env.requests.append(request)
                    return (env.delayNanos, env.error, env.status)
                }
                if delay > 0 { try await Task.sleep(nanoseconds: delay) }
                if let error { throw error }
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            },
            now: { env.lock.withLock { env.now } },
            timeZone: TimeZone(identifier: "Asia/Shanghai")!,
            arch: "arm64",
            log: { line in env.lock.withLock { env.logs.append(line) } })
    }

    private func body(_ request: URLRequest) throws -> [String: String] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
    }

    func testConsentIsThreeStateAndOnlyYesAllowsPing() {
        let config = AskFreeConfig(configDir: dir, secrets: FileSecretStore(fileURL: dir.appendingPathComponent("s.json")))
        XCTAssertEqual(UsageConsent.load(from: config), .unasked, "老配置里没有这个键 = 没问过")
        XCTAssertTrue(UsageConsent.load(from: config).needsAsking)
        XCTAssertFalse(UsageConsent.unasked.allowsPing)
        UsageConsent.save(agree: false, in: config)
        XCTAssertEqual(UsageConsent.load(from: config), .no)
        XCTAssertFalse(UsageConsent.no.allowsPing)
        XCTAssertFalse(UsageConsent.no.needsAsking)
        UsageConsent.save(agree: true, in: config)
        XCTAssertEqual(UsageConsent.load(from: config), .yes)
        XCTAssertTrue(UsageConsent.yes.allowsPing)
        XCTAssertEqual(config.loadConfig()["usage_consent"] as? String, "yes")
        config.save(value: "maybe", forKey: "usage_consent")
        XCTAssertEqual(UsageConsent.load(from: config), .unasked, "认不出的值当没问过：不发，再问一次")
    }

    func testNotConsentedSendsNothing() async {
        let env = Env()
        for consent in [UsageConsent.unasked, .no] {
            env.consent = consent
            let outcome = await makePing(env).tick()
            XCTAssertEqual(outcome, .off)
        }
        XCTAssertTrue(env.requests.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("usage-ping.json").path),
                       "没同意时连随机编号都不生成")
    }

    func testSendsExactlyTheAgreedFieldsWithoutAuthorization() async throws {
        let env = Env()
        let outcome = await makePing(env).tick()
        XCTAssertEqual(outcome, .sent)
        let request = try XCTUnwrap(env.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://ping.test/v1/ping")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.timeoutInterval, 10)
        let sent = try body(request)
        XCTAssertEqual(Set(sent.keys), ["id", "version", "platform", "arch", "plan", "lang", "product"])
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(sent["id"])), "id 是随机 UUID")
        XCTAssertEqual(sent["version"], "1.2.0")
        XCTAssertEqual(sent["platform"], "darwin")
        XCTAssertEqual(sent["arch"], "arm64")
        XCTAssertEqual(sent["plan"], "own")
        XCTAssertEqual(sent["lang"], "zh")
        XCTAssertEqual(sent["product"], "askfree")
    }

    func testOncePerLocalDayAndSameIdNextDay() async throws {
        let env = Env()
        let ping = makePing(env)
        let first = await ping.tick()
        let again = await ping.tick()
        XCTAssertEqual(first, .sent)
        XCTAssertEqual(again, .done)
        XCTAssertEqual(env.requests.count, 1)
        env.now = env.now.addingTimeInterval(86_400)
        let nextDay = await ping.tick()
        XCTAssertEqual(nextDay, .sent)
        XCTAssertEqual(env.requests.count, 2)
        XCTAssertEqual(try body(env.requests[0])["id"], try body(env.requests[1])["id"], "编号装一次生成一次，之后不变")
        // 重开 App（新对象读同一个文件）：今天报过了就不再报
        let reopened = await makePing(env).tick()
        XCTAssertEqual(reopened, .done)
    }

    func testFailureIsLoggedAndRetriedLater() async {
        let env = Env()
        env.status = 500
        let ping = makePing(env)
        let failed = await ping.tick()
        XCTAssertEqual(failed, .failed)
        env.status = 204
        env.error = URLError(.timedOut)
        let timedOut = await ping.tick()
        XCTAssertEqual(timedOut, .failed)
        env.error = nil
        let retried = await ping.tick()
        XCTAssertEqual(retried, .sent, "失败的那天没记下，下一次再试")
        XCTAssertEqual(env.logs.count, 2)
        XCTAssertTrue(env.logs[0].contains("HTTP 500"))
        XCTAssertTrue(env.logs[1].contains("URLError"))
    }

    func testConcurrentTicksSendOnce() async {
        let env = Env()
        env.delayNanos = 50_000_000
        let ping = makePing(env)
        async let a = ping.tick()
        async let b = ping.tick()
        let (x, y) = await (a, b)
        XCTAssertEqual(env.requests.count, 1)
        XCTAssertEqual([x, y].filter { $0 == .sent }.count, 2, "同时来的两次合成一次，结果一样")
    }

    func testPlanIsOwnUnlessMember() async throws {
        let env = Env()
        _ = await makePing(env, plan: "member").tick()
        XCTAssertEqual(try body(XCTUnwrap(env.requests.first))["plan"], "member")
    }

    func testLocalDayUsesLocalTimeZone() {
        // 2026-10-27 23:30 UTC 在东八区已经是 28 号
        let date = Date(timeIntervalSince1970: 1_793_143_800)
        XCTAssertEqual(UsagePing.localDay(date, timeZone: TimeZone(identifier: "UTC")!), "2026-10-27")
        XCTAssertEqual(UsagePing.localDay(date, timeZone: TimeZone(identifier: "Asia/Shanghai")!), "2026-10-28")
    }

    func testAPIBaseAndWhenToRun() {
        XCTAssertEqual(UsagePing.apiBase(environment: [:])?.absoluteString, "https://api.us-cloud.uk")
        XCTAssertEqual(UsagePing.apiBase(environment: ["ASKFREE_API": "http://127.0.0.1:8787/"])?.absoluteString, "http://127.0.0.1:8787")
        XCTAssertNil(UsagePing.apiBase(environment: ["ASKFREE_API": "file:///etc"]))
        XCTAssertTrue(UsagePing.shouldRun(isDevBuild: false, isSelfTest: false, environment: [:]), "正式版报")
        XCTAssertFalse(UsagePing.shouldRun(isDevBuild: true, isSelfTest: false, environment: [:]), "开发版不报")
        XCTAssertTrue(UsagePing.shouldRun(isDevBuild: true, isSelfTest: false, environment: ["ASKFREE_API": "http://127.0.0.1:1"]),
                      "开发版设了覆盖地址才报（测试用）")
        XCTAssertFalse(UsagePing.shouldRun(isDevBuild: false, isSelfTest: true, environment: ["ASKFREE_API": "http://127.0.0.1:1"]),
                       "自测从来不报")
    }

    func testCopyStatesTheReasonEverywhere() {
        let reason = "我们会给前 100 位用户免费额度，所以需要统计有多少人在用。统计是匿名的。"
        XCTAssertEqual(UsageConsentCopy.reason, reason)
        XCTAssertTrue(UsageConsentCopy.settingDetail.hasPrefix(reason))
        XCTAssertEqual(UsageConsentCopy.agree, "同意")
        XCTAssertEqual(UsageConsentCopy.decline, "不用了")
    }
}

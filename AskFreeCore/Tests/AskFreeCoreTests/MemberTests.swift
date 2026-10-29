import XCTest
@testable import AskFreeCore

/// 会员客户端：注册领试用、查状态（节流）、令牌失效重新注册、结账轮询、门户、授权码；
/// 计量请求（识别、联网）的请求头；错误码翻成白话（不让用户去填 Key）；剩几次、到期、价格怎么写
@MainActor
final class MemberClientTests: XCTestCase {
    /// 假后台：按「方法 路径」回一段 JSON，记下收到的请求
    final class FakeServer: @unchecked Sendable {
        let lock = NSLock()
        var routes: [String: [(Int, String)]] = [:]
        var requests: [URLRequest] = []
        var headers: [String: String] = [:]
        var fail: Error?

        /// 同一个路径给几次就按顺序回，最后一个一直回
        func on(_ key: String, _ status: Int, _ json: String) {
            lock.withLock { routes[key, default: []].append((status, json)) }
        }

        func count(_ key: String) -> Int {
            lock.withLock { requests.filter { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" == key }.count }
        }

        var send: MemberClient.Send {
            { request in
                let (reply, error, headers) = self.lock.withLock { () -> ((Int, String)?, Error?, [String: String]) in
                    self.requests.append(request)
                    let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
                    var list = self.routes[key] ?? []
                    let reply = list.first
                    if list.count > 1 { list.removeFirst(); self.routes[key] = list }
                    return (reply, self.fail, self.headers)
                }
                if let error { throw error }
                let (status, json) = reply ?? (404, #"{"error":{"code":"not-found","message":"没有这个接口"}}"#)
                return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
            }
        }
    }

    nonisolated static func status(plan: String = "trial", left: Int = 30, used: Int = 0, code: String? = nil, today: String = "null",
                       canUse: Bool = true, reason: String? = nil, subscription: String = "null", expiring: Bool = false,
                       memberUntil: String = "null", extra: String = "") -> String {
        """
        {"product":"askfree","plan":"\(plan)","code":\(code.map { "\"\($0)\"" } ?? "null"),"devices":1,"maxDevices":2,"trialOnly":\(code == nil),
         "trial":{"granted":true,"total":30,"used":\(used),"left":\(left)},"subscription":\(subscription),"pass":null,
         "memberUntil":\(memberUntil),"autoRenew":false,"expiring":\(expiring),"today":\(today),"canUse":\(canUse),
         "reason":\(reason.map { "\"\($0)\"" } ?? "null"),
         "prices":{"month":{"cny":990,"usd":199},"year":{"cny":9900,"usd":1990}},"passPrices":{"month":{"cny":990},"year":{"cny":9900}},
         "sync":null,"now":1793232000000\(extra)}
        """
    }

    nonisolated static let registered = """
    {"token":"afd_first","trial":"granted","trialUses":{"granted":true,"total":30,"used":0,"left":30},
     "product":"askfree","plan":"trial","code":null,"devices":1,"maxDevices":2,"trialOnly":true,
     "subscription":null,"pass":null,"memberUntil":null,"autoRenew":false,"expiring":false,"today":null,"canUse":true,"reason":null,
     "prices":null,"passPrices":null,"sync":null,"now":1793232000000}
    """

    private var server: FakeServer!
    private var secrets: InMemorySecretStore!
    private var clock = Date(timeIntervalSince1970: 1_793_232_000)

    override func setUp() async throws {
        server = FakeServer()
        secrets = InMemorySecretStore()
        clock = Date(timeIntervalSince1970: 1_793_232_000)
    }

    private func makeClient(base: URL? = URL(string: "http://member.test")) -> MemberClient {
        MemberClient(base: base, secrets: secrets, fingerprint: { String(repeating: "ab", count: 32) }, version: "1.3.0",
                     send: server.send, now: { [unowned self] in self.clock }, pollInterval: 0.01, pollTimeout: 5)
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testRegistersOnceAndKeepsTokenInSecretStore() async throws {
        server.on("POST /v1/askfree/device", 200, Self.registered)
        let client = makeClient()
        XCTAssertFalse(client.hasDevice)
        let creds = try await client.credentials()
        XCTAssertEqual(creds.token, "afd_first")
        XCTAssertEqual(creds.base.absoluteString, "http://member.test")
        XCTAssertEqual(secrets.get(MemberClient.tokenAccount), "afd_first", "令牌存进钥匙串（这里是内存）")
        XCTAssertEqual(client.registration, "granted")
        XCTAssertEqual(client.status?.trial.left, 30, "注册的返回里次数明细在 trialUses")
        XCTAssertEqual(client.status?.plan, "trial")

        let req = try XCTUnwrap(server.requests.first)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"), "注册不带令牌")
        let body = try json(req)
        XCTAssertEqual(body["device"] as? String, String(repeating: "ab", count: 32))
        XCTAssertEqual(body["platform"] as? String, "darwin")
        XCTAssertEqual(body["version"] as? String, "1.3.0")

        _ = try await client.credentials()
        XCTAssertEqual(server.count("POST /v1/askfree/device"), 1, "存着令牌就不再注册")
    }

    func testRefreshSendsTokenAndIsThrottledByMaxAge() async throws {
        secrets.set(MemberClient.tokenAccount, "afd_saved")
        server.on("GET /v1/askfree/status", 200, Self.status(left: 27, used: 3))
        let client = makeClient()
        await client.refresh(maxAge: 60)
        XCTAssertEqual(client.status?.trial.left, 27)
        XCTAssertEqual(server.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer afd_saved")
        XCTAssertEqual(server.requests.first?.timeoutInterval, 20, "所有请求 20 秒超时")
        clock += 30
        await client.refresh(maxAge: 60)
        XCTAssertEqual(server.count("GET /v1/askfree/status"), 1, "60 秒内问过就不再问")
        clock += 31
        await client.refresh(maxAge: 60)
        XCTAssertEqual(server.count("GET /v1/askfree/status"), 2)
        await client.refresh()
        XCTAssertEqual(server.count("GET /v1/askfree/status"), 3, "maxAge 0（收到 402 / 429 后）照问")
    }

    func testBadDeviceReRegistersAndRetriesOnce() async throws {
        secrets.set(MemberClient.tokenAccount, "afd_stale")
        server.on("GET /v1/askfree/status", 401, #"{"error":{"code":"bad-device","message":"这台电脑的会员凭据无效"}}"#)
        server.on("GET /v1/askfree/status", 200, Self.status(left: 12, used: 18))
        server.on("POST /v1/askfree/device", 200, Self.registered.replacingOccurrences(of: "afd_first", with: "afd_new"))
        let client = makeClient()
        await client.refresh()
        XCTAssertNil(client.error)
        XCTAssertEqual(client.status?.trial.left, 12, "同一台电脑重新注册拿回原来的账")
        XCTAssertEqual(secrets.get(MemberClient.tokenAccount), "afd_new")
        let statusCalls = server.requests.filter { $0.url?.path == "/v1/askfree/status" }
        XCTAssertEqual(statusCalls.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer afd_stale", "Bearer afd_new"])
    }

    func testNetworkErrorKeepsLastStatus() async throws {
        secrets.set(MemberClient.tokenAccount, "afd_saved")
        server.on("GET /v1/askfree/status", 200, Self.status(left: 20, used: 10))
        let client = makeClient()
        await client.refresh()
        server.fail = URLError(.notConnectedToInternet)
        await client.refresh()
        XCTAssertEqual(client.status?.trial.left, 20, "连不上时留着上次的数，不清空")
        XCTAssertEqual(client.error?.code, "network")
        XCTAssertEqual(MemberSummary.line(client.status, error: client.error).detail, "还剩 20 个问题")
    }

    func testNoServerInDevBuildNeverSends() async throws {
        let client = makeClient(base: nil)
        do {
            _ = try await client.credentials()
            XCTFail("开发版没设 ASKFREE_API 不该拿到凭据")
        } catch let e as MemberAPIError {
            XCTAssertEqual(e.code, "no-server")
        }
        await client.refresh()
        XCTAssertEqual(client.error?.code, "no-server")
        XCTAssertTrue(server.requests.isEmpty, "一个请求都不发")
    }

    func testCheckoutPollsUntilPaid() async throws {
        secrets.set(MemberClient.tokenAccount, "afd_saved")
        server.on("POST /v1/askfree/checkout", 200, #"{"url":"https://checkout.stripe.test/cs_1","claim":"afc_abc"}"#)
        server.on("GET /v1/askfree/checkout/afc_abc", 200, #"{"status":"pending"}"#)
        server.on("GET /v1/askfree/checkout/afc_abc", 200, #"{"status":"pending"}"#)
        let member = Self.status(plan: "member", left: 27, used: 3, code: "AF-ABCD-EFGH-JKMN",
                                 today: #"{"limit":200,"used":0,"left":200,"resetAt":1793318400000}"#,
                                 subscription: #"{"status":"active","plan":"month","currency":"cny","amount":990,"periodEnd":1795824000000,"cancelAtPeriodEnd":false,"accessUntil":1795910400000}"#,
                                 memberUntil: "1795910400000")
        server.on("GET /v1/askfree/checkout/afc_abc", 200, String(member.dropLast()) + #","status":"paid"}"#)
        let client = makeClient()
        let paid = expectation(description: "paid")
        client.onPaid = { s in
            XCTAssertTrue(s.isMember)
            paid.fulfill()
        }
        let url = try await client.checkout(plan: "month", currency: "cny", mode: "sub")
        XCTAssertEqual(url.absoluteString, "https://checkout.stripe.test/cs_1")
        XCTAssertEqual(client.pendingCheckout?.claim, "afc_abc")
        let body = try json(XCTUnwrap(server.requests.first { $0.url?.path == "/v1/askfree/checkout" }))
        XCTAssertEqual(body["plan"] as? String, "month")
        XCTAssertEqual(body["currency"] as? String, "cny")
        XCTAssertEqual(body["mode"] as? String, "sub")
        await fulfillment(of: [paid], timeout: 3)
        XCTAssertNil(client.pendingCheckout, "付完就不再等")
        XCTAssertEqual(client.status?.code, "AF-ABCD-EFGH-JKMN")
        XCTAssertEqual(client.status?.today?.left, 200)
        XCTAssertEqual(server.count("GET /v1/askfree/checkout/afc_abc"), 3)
    }

    func testExpiredCheckoutStopsPolling() async throws {
        secrets.set(MemberClient.tokenAccount, "afd_saved")
        server.on("POST /v1/askfree/checkout", 200, #"{"url":"https://checkout.stripe.test/cs_2","claim":"afc_x"}"#)
        server.on("GET /v1/askfree/checkout/afc_x", 200, #"{"status":"expired"}"#)
        let client = makeClient()
        let ended = expectation(description: "ended")
        client.onCheckoutEnded = { ended.fulfill() }
        _ = try await client.checkout(plan: "year", currency: "cny", mode: "pass")
        await fulfillment(of: [ended], timeout: 3)
        XCTAssertNil(client.pendingCheckout)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(server.count("GET /v1/askfree/checkout/afc_x"), 1, "过期就不再问")
    }

    func testCheckoutConflictIsThrownWithServerMessage() async throws {
        secrets.set(MemberClient.tokenAccount, "afd_saved")
        server.on("POST /v1/askfree/checkout", 409, #"{"error":{"code":"already-subscribed","message":"已经开了自动续费，不用再买。"}}"#)
        let client = makeClient()
        do {
            _ = try await client.checkout(plan: "month", currency: "cny", mode: "pass")
            XCTFail("409 要抛出来")
        } catch let e as MemberAPIError {
            XCTAssertEqual(e.status, 409)
            XCTAssertEqual(e.code, "already-subscribed")
            XCTAssertEqual(e.message, "已经开了自动续费，不用再买。")
        }
        XCTAssertNil(client.pendingCheckout)
    }

    func testPortalActivateAndUnbind() async throws {
        secrets.set(MemberClient.tokenAccount, "afd_saved")
        server.on("POST /v1/askfree/portal", 200, #"{"url":"https://billing.stripe.test/p/1"}"#)
        server.on("POST /v1/askfree/license/activate", 200, Self.status(plan: "member", code: "AF-ABCD-EFGH-JKMN"))
        server.on("POST /v1/askfree/license/unbind", 200, Self.status(left: 5, used: 25))
        let client = makeClient()
        let portal = try await client.portal()
        XCTAssertEqual(portal.absoluteString, "https://billing.stripe.test/p/1")
        try await client.activate(code: "af-abcd-efgh-jkmn")
        XCTAssertEqual(client.status?.code, "AF-ABCD-EFGH-JKMN")
        let body = try json(XCTUnwrap(server.requests.first { $0.url?.path == "/v1/askfree/license/activate" }))
        XCTAssertEqual(body["code"] as? String, "af-abcd-efgh-jkmn", "大小写、前缀由后台认")
        try await client.unbind()
        XCTAssertNil(client.status?.code)
        XCTAssertEqual(client.status?.trial.left, 5)

        server.lock.withLock { server.routes["POST /v1/askfree/license/activate"] = nil }
        server.on("POST /v1/askfree/license/activate", 404, #"{"error":{"code":"bad-code","message":"不是 Ask Free 的授权码，核对一下再试"}}"#)
        let fresh = makeClient()
        do {
            try await fresh.activate(code: "MC-XXXX")
            XCTFail("错码要抛")
        } catch let e as MemberAPIError {
            XCTAssertEqual(e.code, "bad-code")
        }
    }

    func testUseHeadersUpdateCountsLocally() async throws {
        secrets.set(MemberClient.tokenAccount, "afd_saved")
        server.on("GET /v1/askfree/status", 200, Self.status(left: 2, used: 28))
        let client = makeClient()
        await client.refresh()
        client.apply(MemberUseHeaders(charged: true, kind: "trial", left: 1, reset: nil))
        XCTAssertEqual(client.status?.trial.left, 1)
        XCTAssertEqual(client.status?.trial.used, 29)
        XCTAssertTrue(client.status?.canUse == true)
        client.apply(MemberUseHeaders(charged: true, kind: "trial", left: 0, reset: nil))
        XCTAssertEqual(client.status?.canUse, false)
        XCTAssertEqual(client.status?.reason, "trial-used-up")
    }
}

final class MemberModelTests: XCTestCase {
    func testStatusDecodesSpecExample() throws {
        let s = try JSONDecoder().decode(MemberStatus.self, from: Data(MemberClientTests.status(left: 27, used: 3).utf8))
        XCTAssertEqual(s.plan, "trial")
        XCTAssertEqual(s.trial, MemberStatus.Trial(granted: true, total: 30, used: 3, left: 27))
        XCTAssertEqual(s.prices?.amount(plan: "month", currency: "cny"), 990)
        XCTAssertEqual(s.prices?.amount(plan: "year", currency: "usd"), 1990)
        XCTAssertEqual(s.passPrices?.amount(plan: "year", currency: "cny"), 9900)
        XCTAssertNil(s.passPrices?.amount(plan: "month", currency: "usd"), "一次买只有人民币")
        XCTAssertTrue(s.canUse)
    }

    func testRegistrationReadsTrialResultAndCounts() throws {
        let r = try MemberRegistration.decode(Data(MemberClientTests.registered.utf8))
        XCTAssertEqual(r.token, "afd_first")
        XCTAssertEqual(r.trial, "granted")
        XCTAssertEqual(r.status.trial.total, 30)
        XCTAssertThrowsError(try MemberRegistration.decode(Data(#"{"trial":"granted"}"#.utf8)), "没有令牌")
    }

    func testMemberApplyDailyHeaders() throws {
        var s = try JSONDecoder().decode(MemberStatus.self, from: Data(MemberClientTests.status(
            plan: "member", today: #"{"limit":200,"used":10,"left":190,"resetAt":1793318400000}"#).utf8))
        s.apply(MemberUseHeaders(charged: true, kind: "sub", left: 189, reset: 1793318400000))
        XCTAssertEqual(s.today?.left, 189)
        XCTAssertEqual(s.today?.used, 11)
        XCTAssertEqual(s.trial.left, 30, "会员期间不扣试用")
        s.apply(MemberUseHeaders(charged: true, kind: "sub", left: 0, reset: nil))
        XCTAssertEqual(s.reason, "daily-limit")
    }

    func testUseHeadersParse() {
        let url = URL(string: "http://x")!
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                headerFields: ["X-Use-Charged": "1", "X-Uses-Kind": "sub", "X-Uses-Left": "188", "X-Uses-Reset": "1793318400000"])!
        XCTAssertEqual(MemberUseHeaders(r), MemberUseHeaders(charged: true, kind: "sub", left: 188, reset: 1793318400000))
        XCTAssertNil(MemberUseHeaders(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!))
    }

    func testErrorParsing() {
        let data = Data(#"{"error":{"code":"daily-limit","message":"今天的 200 次用完了，北京时间早上 8 点重置","resetAt":1793318400000}}"#.utf8)
        let r = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "3600"])!
        let e = MemberAPIError.from(status: 429, data: data, response: r)
        XCTAssertEqual(e.code, "daily-limit")
        XCTAssertEqual(e.resetAt, 1793318400000)
        XCTAssertEqual(e.retryAfter, 3600)
        let bare = MemberAPIError.from(status: 502, data: Data("<html>".utf8))
        XCTAssertEqual(bare.code, "http-502")
        XCTAssertTrue(bare.message.contains("502"))
        XCTAssertTrue(MemberAPIError(status: 401, code: "bad-device", message: "").isBadDevice)
        XCTAssertEqual(MemberAPIError.network(URLError(.timedOut)).code, "timeout")
        XCTAssertEqual(MemberAPIError.network(URLError(.cannotConnectToHost)).code, "network")
    }

    func testMoneyAndDates() {
        XCTAssertEqual(MemberFormat.money(990, currency: "cny"), "¥9.9")
        XCTAssertEqual(MemberFormat.money(9900, currency: "cny"), "¥99")
        XCTAssertEqual(MemberFormat.money(199, currency: "usd"), "$1.99")
        XCTAssertEqual(MemberFormat.money(1990, currency: "usd"), "$19.9")
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        // 2026-10-31 00:00 UTC：北京时间早上 8 点，柏林（冬令时）凌晨 1 点
        let reset: Double = 1_793_404_800_000
        XCTAssertEqual(MemberFormat.resetLine(reset, timeZone: shanghai), "北京时间早上 8 点")
        XCTAssertEqual(MemberFormat.resetLine(reset, timeZone: berlin), "北京时间早上 8 点（你这里是 01:00）")
        XCTAssertEqual(MemberFormat.day(1_795_910_400_000, timeZone: shanghai), "11 月 29 日")
    }

    func testFingerprintIsSha256OfProductAndHardwareID() {
        XCTAssertEqual(MemberFingerprint.hash(hardwareID: "00000000-1111-2222-3333-444444444444"),
                       "10700d57e19493771f514aa62defd89a2cdfc53d8f9060fa9759ef4dfcc69652")
        let current = MemberFingerprint.hardwareUUID().map { MemberFingerprint.hash(hardwareID: $0) }
        if let current { XCTAssertEqual(current.count, 64) }
    }

    func testEndpointNeverPointsDevBuildAtLiveServer() {
        XCTAssertNil(MemberEndpoint.base(environment: [:], isDevBuild: true, isSelfTest: false), "开发版没设 ASKFREE_API 不连后台")
        XCTAssertEqual(MemberEndpoint.base(environment: ["ASKFREE_API": "http://127.0.0.1:8821/"], isDevBuild: true, isSelfTest: false)?.absoluteString,
                       "http://127.0.0.1:8821")
        XCTAssertEqual(MemberEndpoint.base(environment: [:], isDevBuild: false, isSelfTest: false)?.absoluteString, "https://api.us-cloud.uk")
        XCTAssertNil(MemberEndpoint.base(environment: [:], isDevBuild: false, isSelfTest: true), "CI 的启动自测不占线上名额")
        let base = URL(string: "http://127.0.0.1:8821")!
        XCTAssertEqual(MemberEndpoint.url(base, "/chat/completions").absoluteString, "http://127.0.0.1:8821/v1/askfree/chat/completions")
    }

    func testUsageModeDefaultsToMemberAndMigratesOldUsers() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("af-mode-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fresh = AskFreeConfig(configDir: dir.appendingPathComponent("a"), secrets: InMemorySecretStore())
        XCTAssertEqual(UsageMode.current(config: fresh), .member, "新用户默认会员")
        XCTAssertFalse(UsageMode.isChosen(config: fresh))
        UsageMode.migrate(config: fresh)
        XCTAssertFalse(UsageMode.isChosen(config: fresh), "没填过 Key 不替他选")

        let old = AskFreeConfig(configDir: dir.appendingPathComponent("b"), secrets: InMemorySecretStore())
        old.save(value: "sk-old", forKey: "deepseek_api_key")
        UsageMode.migrate(config: old)
        XCTAssertEqual(UsageMode.current(config: old), .own, "更新上来、填过 Key 的老用户照旧自带 Key")
        UsageMode.save(.member, config: old)
        UsageMode.migrate(config: old)
        XCTAssertEqual(UsageMode.current(config: old), .member, "选过了就不再改")
    }
}

final class MemberRequestTests: XCTestCase {
    private let creds = MemberCredentials(base: URL(string: "http://127.0.0.1:8821")!, token: "afd_t")
    private let useId = "0b5f6c1e-2a3b-4c5d-8e9f-001122334455"

    func testASRUploadsRawAudioWithUseId() throws {
        let audio = Data([1, 2, 3, 4])
        let r = CloudASRTranscriber.memberRequest(audio: audio, format: "m4a", seconds: 3.24, credentials: creds, useId: useId)
        XCTAssertEqual(r.url?.absoluteString, "http://127.0.0.1:8821/v1/askfree/asr")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer afd_t")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Use-Id"), useId)
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Audio-Seconds"), "3.2")
        XCTAssertEqual(r.httpBody, audio, "请求体就是音频字节，不是 base64 的 JSON")
        XCTAssertEqual(r.timeoutInterval, 150)
        let wav = CloudASRTranscriber.memberRequest(audio: audio, format: "wav", seconds: 1, credentials: creds, useId: useId)
        XCTAssertEqual(wav.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
    }

    func testASRResponses() {
        if case .success(let text) = CloudASRTranscriber.parseMemberResponse(status: 200, data: Data(#"{"text":"明天柏林天气怎么样","durationMs":3200,"noSpeech":false}"#.utf8)) {
            XCTAssertEqual(text, "明天柏林天气怎么样")
        } else { XCTFail("200 有字") }
        guard case .failure(CloudASRTranscriber.TranscriptionError.noSpeech) = CloudASRTranscriber.parseMemberResponse(
            status: 200, data: Data(#"{"text":"","noSpeech":true}"#.utf8)) else { return XCTFail("没听到话") }
        guard case .failure(let e as MemberAPIError) = CloudASRTranscriber.parseMemberResponse(
            status: 402, data: Data(#"{"error":{"code":"asr-limit","message":"试用的语音识别一共 60 分钟，已经用完了"}}"#.utf8)) else {
            return XCTFail("402 按后台的错误码")
        }
        XCTAssertEqual(e.code, "asr-limit")
    }

    func testSearchGoesThroughMemberServer() throws {
        let member = AskMember(credentials: creds, useId: useId)
        let r = try XCTUnwrap(DeepSeekSearch.request(query: "柏林天气", apiKey: creds.token, member: member))
        XCTAssertEqual(r.url?.absoluteString, "http://127.0.0.1:8821/v1/askfree/search")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer afd_t")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Use-Id"), useId)
        let own = try XCTUnwrap(DeepSeekSearch.request(query: "x", apiKey: "sk-own", member: nil))
        XCTAssertNil(own.value(forHTTPHeaderField: "X-Use-Id"), "自带 Key 照旧直连 DeepSeek")
    }

    func testMemberProviderLooksLikeDeepSeekOnTheServer() {
        let p = AskProvider.member(AskMember(credentials: creds, useId: useId))
        XCTAssertEqual(p.name, "deepseek", "联网、看屏幕的工具照 DeepSeek 走")
        XCTAssertEqual(p.url.absoluteString, "http://127.0.0.1:8821/v1/askfree/chat/completions")
        XCTAssertEqual(p.visionURL, p.url, "带图也发到后台")
        XCTAssertEqual(p.model, "deepseek-flash")
        XCTAssertEqual(p.apiKey, "afd_t")
        XCTAssertTrue(AskSearch.shouldOfferTool(provider: p.name, hasQwenKey: false), "会员也能联网（走后台的搜索转发）")
    }
}

final class MemberCopyTests: XCTestCase {
    private func problem(_ status: Int, _ code: String, _ message: String = "后台的话", resetAt: Double? = nil) -> MemberProblem {
        MemberProblem(MemberAPIError(status: status, code: code, message: message, resetAt: resetAt), timeZone: TimeZone(identifier: "Europe/Berlin")!)
    }

    func testEveryCodeSaysWhatToDoWithoutAskingForAKey() {
        let codes: [(Int, String)] = [(402, "trial-used-up"), (402, "trial-closed"), (402, "sub-ended"), (402, "payment-failed"),
                                      (429, "daily-limit"), (402, "asr-limit"), (429, "asr-limit"), (429, "use-limit"), (409, "use-expired"),
                                      (429, "rate"), (503, "busy"), (503, "upstream"), (502, "asr-failed"), (413, "audio-too-long"),
                                      (503, "not-ready"), (0, "network"), (0, "timeout"), (401, "bad-device"), (500, "server")]
        for (status, code) in codes {
            let p = problem(status, code)
            XCTAssertFalse(p.title.isEmpty, code)
            XCTAssertFalse(p.detail.isEmpty, code)
            XCTAssertFalse((p.title + p.detail + p.actions.map(\.title).joined()).contains("Key"), "\(code) 不让用户去填 Key")
            XCTAssertFalse(p.actions.contains { $0.action == .openModels }, "\(code) 不跳去填 Key")
        }
    }

    func testActionsPerCode() {
        XCTAssertEqual(problem(402, "trial-used-up").actions.map(\.action), [.openMembership])
        XCTAssertEqual(problem(402, "trial-closed").title, "免费试用的名额发完了")
        XCTAssertEqual(problem(402, "payment-failed").actions.map(\.action), [.openPortal], "欠费：打开门户换卡")
        XCTAssertEqual(problem(402, "asr-limit").actions.map(\.action), [.typeInstead, .openMembership], "试用的识别分钟用完：改打字或订阅")
        XCTAssertEqual(problem(429, "asr-limit").actions.map(\.action), [.typeInstead])
        XCTAssertTrue(problem(429, "use-limit").actions.isEmpty, "这一问到上限了，不再重试")
        XCTAssertEqual(problem(503, "upstream").actions.map(\.action), [.retry])
        XCTAssertEqual(problem(503, "upstream").withoutRetry.actions, [])
    }

    func testDailyLimitAddsLocalResetTime() {
        let p = problem(429, "daily-limit", "今天的 200 次用完了，北京时间早上 8 点重置", resetAt: 1_793_404_800_000)
        XCTAssertEqual(p.detail, "今天的 200 次用完了，北京时间早上 8 点重置（你这里是 01:00）")
        let inChina = MemberProblem(MemberAPIError(status: 429, code: "daily-limit", message: "今天的 200 次用完了，北京时间早上 8 点重置", resetAt: 1_793_404_800_000),
                                    timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        XCTAssertEqual(inChina.detail, "今天的 200 次用完了，北京时间早上 8 点重置")
    }

    func testAskFailureMapsMemberErrors() {
        let f = AskFailure(error: MemberAPIError(status: 402, code: "trial-used-up", message: "x"))
        XCTAssertEqual(f.memberCode, "trial-used-up")
        XCTAssertEqual(f.title(provider: "会员"), "免费试用用完了")
        XCTAssertEqual(f.actions.first?.action, .openMembership)
        XCTAssertNil(AskFailure(error: URLError(.timedOut)).memberCode)
    }

    func testSummaryLines() throws {
        func s(_ json: String) throws -> MemberStatus { try JSONDecoder().decode(MemberStatus.self, from: Data(json.utf8)) }
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertEqual(MemberSummary.line(nil).detail, "正在连接会员服务器…")
        XCTAssertEqual(MemberSummary.line(try s(MemberClientTests.status(left: 27, used: 3))),
                       .init(title: "免费试用", detail: "还剩 27 个问题", warn: false))
        XCTAssertEqual(MemberSummary.line(try s(MemberClientTests.status(plan: "none", left: 0, used: 30, canUse: false, reason: "trial-used-up"))),
                       .init(title: "免费试用", detail: "30 个问题用完了", warn: true))
        XCTAssertEqual(MemberSummary.line(try s(MemberClientTests.status(plan: "none", left: 0, used: 0, canUse: false, reason: "trial-closed"))).detail,
                       "免费名额已经发完了")
        let today = #"{"limit":200,"used":12,"left":188,"resetAt":1793318400000}"#
        XCTAssertEqual(MemberSummary.line(try s(MemberClientTests.status(plan: "member", today: today))).detail, "今天还能问 188 个")
        XCTAssertEqual(MemberSummary.line(try s(MemberClientTests.status(plan: "member", today: today, expiring: true, memberUntil: "1793404800000")), timeZone: tz),
                       .init(title: "会员", detail: "10 月 31 日 到期，记得续买", warn: true))
        let used = #"{"limit":200,"used":200,"left":0,"resetAt":1793318400000}"#
        XCTAssertEqual(MemberSummary.line(try s(MemberClientTests.status(plan: "member", today: used, canUse: false, reason: "daily-limit"))).detail,
                       "今天的 200 个问题用完了")
        XCTAssertEqual(MemberSummary.registration("closed", status: nil), "前 100 位新用户的免费名额已经发完了。可以订阅会员，或者改用自带 Key（永久免费）。")
    }
}

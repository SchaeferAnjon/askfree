import Foundation

public final class CloudASRTranscriber {

    // MARK: - 服务商 & 识别版本
    public enum ASRProvider {
        case volcano   // 火山引擎
        case bailian   // 阿里百炼（DashScope）
    }

    /// 可切换的识别版本，各有独立免费额度：火山三档 + 百炼一档。
    /// 火山闲时版不纳入（进 24h 队列，无法用于实时）。
    public enum ASRVersion: String, CaseIterable {
        case turbo      // 火山极速版 1.0：同步 flash
        case standard   // 火山标准版 1.0：异步 submit + 轮询 query
        case v2         // 火山 2.0(seedasr)：异步 submit + 轮询 query
        case bailian    // 百炼 qwen3-asr-flash：同步 OpenAI 兼容接口

        public var provider: ASRProvider {
            switch self {
            case .turbo, .standard, .v2: return .volcano
            case .bailian: return .bailian
            }
        }

        /// 火山调用时填入 X-Api-Resource-Id 的值（百炼不用）
        public var resourceID: String {
            switch self {
            case .turbo: return "volc.bigasr.auc_turbo"
            case .standard: return "volc.bigasr.auc"
            case .v2: return "volc.seedasr.auc"
            case .bailian: return ""
            }
        }

        public var modelIdentifier: String {
            switch self {
            case .turbo, .standard, .v2: return resourceID
            case .bailian: return "qwen3-asr-flash"
            }
        }

        /// true = 同步一步出结果（极速版、百炼）；false = 异步 submit/query（火山标准版/2.0）
        public var isSync: Bool {
            switch self {
            case .turbo, .bailian: return true
            case .standard, .v2: return false
            }
        }

        /// 给用户看的名字
        public var displayName: String {
            switch self {
            case .turbo: return "极速版"
            case .standard: return "标准版"
            case .v2: return "2.0"
            case .bailian: return "百炼"
            }
        }

    }

    private struct Credentials {
        enum AuthStyle {
            case apiKey(String)
            case appAccess(appID: String, accessToken: String)
        }
        let authStyle: AuthStyle
    }

    // MARK: - 错误分类
    public enum TranscriptionError: LocalizedError {
        case missingCredentials
        case invalidAudio
        case noData
        case parseError
        case network(underlying: Error)      // 网络层错误（断网/超时）→ 不切版本
        case serverBusy(message: String)     // 服务器临时繁忙（如 55000031）→ 原地可重试
        case serverFailed(message: String)   // 服务端业务失败 / 疑似额度耗尽 → 建议切版本
        case timeout                          // 异步轮询超过总时限
        case noSpeech                         // 服务端判定音频无有效语音（火山状态码 20000003）→ 当作"无内容"，不报错

        public var errorDescription: String? {
            switch self {
            case .missingCredentials: return "未配置云端语音识别凭证"
            case .invalidAudio: return "音频编码失败"
            case .noData: return "云端识别未返回数据"
            case .parseError: return "云端识别返回无法解析"
            case .network(let e): return "网络错误：\(e.localizedDescription)"
            case .serverBusy(let m): return m
            case .serverFailed(let m): return m
            case .timeout: return "识别超时"
            case .noSpeech: return "无内容"
            }
        }

    }

    // MARK: - 端点
    private static let flashURL  = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash"
    private static let submitURL = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/submit"
    private static let queryURL  = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/query"
    // 百炼(DashScope) OpenAI 兼容 ASR：qwen3-asr-flash 同步一步出结果
    private static let bailianURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    private static let bailianModel = ASRVersion.bailian.modelIdentifier

    private let config = AskFreeConfig.shared
    public var debugLog: ((String) -> Void)?

    public init() {}

    /// 会员模式下不用 Key（识别走后台转给火山极速版），连得到后台就算配好了
    public func isConfigured() -> Bool {
        if UsageMode.current() == .member { return MemberEndpoint.current != nil }
        return isConfigured(version: currentVersion())
    }

    /// 当前版本对应服务商的凭证是否已配置。
    public func isConfigured(version: ASRVersion) -> Bool {
        switch version.provider {
        case .volcano: return volcanoCredentials() != nil
        case .bailian: return dashscopeAPIKey() != nil
        }
    }

    // MARK: - 当前识别版本

    /// 用户在设置里选择的识别版本，默认极速版。
    public func currentVersion() -> ASRVersion {
        if let raw = config.string(forKey: "bigasr_version", envKey: "BIGASR_VERSION"),
           let v = ASRVersion(rawValue: raw) {
            return v
        }
        return .turbo
    }

    /// 火山控制台里建的热词表 / 替换词表（隐藏配置）：三个版本都放在 request.corpus 下。
    private func hotWordRequestOptions() -> [String: Any] {
        var corpus: [String: Any] = [:]

        if let boostingTableName = config.string(forKey: "bigasr_boosting_table_name", envKey: "BIGASR_BOOSTING_TABLE_NAME"),
           !boostingTableName.isEmpty {
            corpus["boosting_table_name"] = boostingTableName
        } else if let boostingTableID = config.string(forKey: "bigasr_boosting_table_id", envKey: "BIGASR_BOOSTING_TABLE_ID"),
                  !boostingTableID.isEmpty {
            corpus["boosting_table_id"] = boostingTableID
        }

        if let correctTableName = config.string(forKey: "bigasr_correct_table_name", envKey: "BIGASR_CORRECT_TABLE_NAME"),
           !correctTableName.isEmpty {
            corpus["correct_table_name"] = correctTableName
        } else if let correctTableID = config.string(forKey: "bigasr_correct_table_id", envKey: "BIGASR_CORRECT_TABLE_ID"),
                  !correctTableID.isEmpty {
            corpus["correct_table_id"] = correctTableID
        }

        return corpus.isEmpty ? [:] : ["corpus": corpus]
    }

    // MARK: - 识别入口

    /// 用当前选择的版本识别。
    public func transcribe(samples: [Float], sampleRate: Int = 16000, completion: @escaping (Result<String, Error>) -> Void) {
        transcribe(samples: samples, sampleRate: sampleRate, version: currentVersion(), completion: completion)
    }

    /// 用指定版本识别。
    public func transcribe(samples: [Float], sampleRate: Int = 16000, version: ASRVersion, completion: @escaping (Result<String, Error>) -> Void) {
        // 优先压缩为 AAC/M4A 上传（体积约为 WAV 的 1/10，弱网更快、更不易超时），编码失败回退 WAV
        let audioData: Data
        let audioFormat: String
        if let m4aData = M4AEncoder.makeM4AData(from: samples, sampleRate: sampleRate), !m4aData.isEmpty {
            audioData = m4aData
            audioFormat = "m4a"
        } else if let wavData = WAVEncoder.makeWAVData(from: samples, sampleRate: sampleRate), !wavData.isEmpty {
            audioData = wavData
            audioFormat = "wav"
        } else {
            completion(.failure(TranscriptionError.invalidAudio))
            return
        }

        // 识别预算：基础 60s，按音频时长线性放宽，封顶 10 分钟。短录音仍 ~60s 不受影响；
        // 长录音（如 20-30 分钟）给服务器足够的处理/轮询时间，避免客户端提前超时（曾导致长录音无结果、还白录）。
        let audioSeconds = Double(samples.count) / Double(max(sampleRate, 1))
        let budget = Self.recognitionBudget(audioSeconds: audioSeconds)

        switch version.provider {
        case .volcano:
            guard let credentials = volcanoCredentials() else {
                completion(.failure(TranscriptionError.missingCredentials))
                return
            }
            let body = makeRequestBody(audioData: audioData, format: audioFormat)
            debugLog?("Cloud ASR: version=\(version.rawValue) provider=volcano resource=\(version.resourceID) sync=\(version.isSync) audio=\(audioFormat)/\(audioData.count / 1024)KB budget=\(Int(budget))s")
            if version.isSync {
                transcribeSync(body: body, credentials: credentials, resourceID: version.resourceID, budgetSeconds: budget, completion: completion)
            } else {
                transcribeAsync(body: body, credentials: credentials, resourceID: version.resourceID, budgetSeconds: budget, completion: completion)
            }
        case .bailian:
            guard let apiKey = dashscopeAPIKey() else {
                completion(.failure(TranscriptionError.missingCredentials))
                return
            }
            // 百炼 qwen3-asr-flash 官方硬上限：音频 ≤5 分钟。超了服务端只会用天书报错（"audio format illegal"）拒掉，
            // 这里提前拦下、给人话提示，省一次注定失败的请求。长音频请改用火山 2.0（异步长音频接口）。
            if audioSeconds > 300 {
                let mins = Int((audioSeconds / 60).rounded())
                completion(.failure(TranscriptionError.serverFailed(message: "百炼识别最长支持 5 分钟，这段约 \(mins) 分钟太长了。请在「模型」里改用火山 2.0，或把问题说短一些。")))
                return
            }
            debugLog?("Cloud ASR: version=\(version.rawValue) provider=bailian model=\(Self.bailianModel) audio=\(audioFormat)/\(audioData.count / 1024)KB budget=\(Int(budget))s")
            transcribeBailian(audioData: audioData, format: audioFormat, apiKey: apiKey, budgetSeconds: budget, completion: completion)
        }
    }

    // MARK: - 会员（后台转给火山极速版）

    /// 会员模式：录音压成 m4a（编不出来用 wav）原样传给后台 POST /v1/askfree/asr，后台用我们的火山 Key 调极速版（§4.8）。
    /// 带这一问的用量号：识别成功那一刻就算了这一次，后面问答失败、点重试（同一个号）不再算。
    /// 后台说「识别服务忙」（火山 55000031 → 503 upstream）原地再试一次，同一个号。
    public func transcribeMember(samples: [Float], sampleRate: Int = 16000, credentials: MemberCredentials, useId: String,
                                 onUse: ((MemberUseHeaders) -> Void)? = nil,
                                 completion: @escaping (Result<String, Error>) -> Void) {
        let audio: Data
        let format: String
        if let m4a = M4AEncoder.makeM4AData(from: samples, sampleRate: sampleRate), !m4a.isEmpty {
            (audio, format) = (m4a, "m4a")
        } else if let wav = WAVEncoder.makeWAVData(from: samples, sampleRate: sampleRate), !wav.isEmpty {
            (audio, format) = (wav, "wav")
        } else {
            completion(.failure(TranscriptionError.invalidAudio))
            return
        }
        let seconds = Double(samples.count) / Double(max(sampleRate, 1))
        let request = Self.memberRequest(audio: audio, format: format, seconds: seconds, credentials: credentials, useId: useId)
        debugLog?("Cloud ASR: member audio=\(format)/\(audio.count / 1024)KB seconds=\(Int(seconds))")
        func attempt(_ n: Int) {
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(MemberAPIError.network(error)))
                    return
                }
                let http = response as? HTTPURLResponse
                let result = Self.parseMemberResponse(status: http?.statusCode ?? 0, data: data, response: http)
                // 剩几次只在识别出字时改：没听到话、出错的这一问后台不算（返回头里的数是还没作废时的）
                if case .success = result, let http, let headers = MemberUseHeaders(http) { onUse?(headers) }
                if case .failure(let e as MemberAPIError) = result, e.status == 503, e.code == "upstream", n == 0 {
                    self.debugLog?("Cloud ASR: member upstream busy → retry once")
                    attempt(1)
                    return
                }
                completion(result)
            }.resume()
        }
        attempt(0)
    }

    /// 发给后台的识别请求：请求体就是音频字节，Content-Type 说是 m4a 还是 wav，X-Audio-Seconds 让后台先拦超长的。
    /// 极速版一次请求直接出字，后台给火山 120 秒，这边等 150 秒
    static func memberRequest(audio: Data, format: String, seconds: Double, credentials: MemberCredentials, useId: String) -> URLRequest {
        var request = URLRequest(url: MemberEndpoint.url(credentials.base, MemberEndpoint.asrPath), timeoutInterval: 150)
        request.httpMethod = "POST"
        request.setValue(format == "m4a" ? "audio/mp4" : "audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue(String(format: "%.1f", seconds), forHTTPHeaderField: "X-Audio-Seconds")
        for (name, value) in credentials.headers(useId: useId) { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = audio
        return request
    }

    /// 后台的识别返回：200 {text, noSpeech}；没听到话是 noSpeech（不算次数）；其余按后台的错误码
    static func parseMemberResponse(status: Int, data: Data?, response: HTTPURLResponse? = nil) -> Result<String, Error> {
        guard status == 200 else { return .failure(MemberAPIError.from(status: status, data: data, response: response)) }
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(TranscriptionError.parseError)
        }
        let text = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if (json["noSpeech"] as? Bool) == true || text.isEmpty { return .failure(TranscriptionError.noSpeech) }
        return .success(text)
    }

    /// 按音频时长给出识别等待预算：基础 60s + 时长×0.5，封顶 600s（10 分钟）。
    /// 短录音 ≈ 60s 不变；30 分钟（1800s）→ 封顶 600s，足够异步接口处理完。
    static func recognitionBudget(audioSeconds: Double) -> TimeInterval {
        return min(600, max(60, audioSeconds * 0.5 + 60))
    }

    // MARK: - 同步（极速版 flash）

    private func transcribeSync(body: [String: Any], credentials: Credentials, resourceID: String, budgetSeconds: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) {
        guard var request = makeRequest(urlString: Self.flashURL, credentials: credentials, resourceID: resourceID, requestID: UUID().uuidString.lowercased()) else {
            completion(.failure(TranscriptionError.invalidAudio))
            return
        }
        request.timeoutInterval = budgetSeconds
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        // 注意：不要用 [weak self]。测试连接等场景用临时实例，请求发出后实例即释放，
        // weak self 会变 nil 导致 completion 永不回调（界面卡在"测试中…"）。强持有 self 直到回调。
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(TranscriptionError.network(underlying: error)))
                return
            }
            guard let data = data else {
                completion(.failure(TranscriptionError.noData))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(TranscriptionError.parseError))
                return
            }
            if let text = Self.extractText(from: json) {
                completion(.success(text))
                return
            }
            // 没拿到文本 → 按状态码分类失败
            completion(.failure(self.classifyServerError(status: Self.apiStatusCode(from: response), data: data)))
        }.resume()
    }

    // MARK: - 异步（标准版 / 2.0：submit + 轮询 query）

    private func transcribeAsync(body: [String: Any], credentials: Credentials, resourceID: String, budgetSeconds: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) {
        let requestID = UUID().uuidString.lowercased()
        guard var submitReq = makeRequest(urlString: Self.submitURL, credentials: credentials, resourceID: resourceID, requestID: requestID) else {
            completion(.failure(TranscriptionError.invalidAudio))
            return
        }
        submitReq.timeoutInterval = budgetSeconds
        do {
            submitReq.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: submitReq) { _, response, error in
            if let error = error {
                completion(.failure(TranscriptionError.network(underlying: error)))
                return
            }
            let status = Self.apiStatusCode(from: response)
            // 提交成功(20000000)或已在排队/处理(2000000x) → 进入轮询；否则直接判失败
            if let status = status, status != 20000000, status != 20000001, status != 20000002 {
                completion(.failure(self.classifyServerError(status: status, data: nil)))
                return
            }
            self.pollQuery(requestID: requestID, credentials: credentials, resourceID: resourceID,
                           deadline: Date().addingTimeInterval(budgetSeconds), completion: completion)
        }.resume()
    }

    private func pollQuery(requestID: String, credentials: Credentials, resourceID: String,
                           deadline: Date, completion: @escaping (Result<String, Error>) -> Void) {
        if Date() > deadline {
            completion(.failure(TranscriptionError.timeout))
            return
        }
        guard var queryReq = makeRequest(urlString: Self.queryURL, credentials: credentials, resourceID: resourceID, requestID: requestID) else {
            completion(.failure(TranscriptionError.parseError))
            return
        }
        queryReq.httpBody = try? JSONSerialization.data(withJSONObject: [String: Any]())

        URLSession.shared.dataTask(with: queryReq) { data, response, error in
            if let error = error {
                completion(.failure(TranscriptionError.network(underlying: error)))
                return
            }
            let status = Self.apiStatusCode(from: response)
            switch status {
            case 20000000?:
                // 完成
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = Self.extractText(from: json) {
                    completion(.success(text))
                } else {
                    completion(.failure(TranscriptionError.serverFailed(message: "识别完成但未返回文本")))
                }
            case 20000001?, 20000002?:
                // 处理中 / 排队中 → 0.3s 后再查
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
                    self.pollQuery(requestID: requestID, credentials: credentials, resourceID: resourceID,
                                   deadline: deadline, completion: completion)
                }
            default:
                completion(.failure(self.classifyServerError(status: status, data: data)))
            }
        }.resume()
    }

    // MARK: - 百炼（DashScope qwen3-asr-flash，同步一步）

    private func transcribeBailian(audioData: Data, format: String, apiKey: String, budgetSeconds: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: Self.bailianURL) else {
            completion(.failure(TranscriptionError.invalidAudio))
            return
        }
        let mimeType = format == "m4a" ? "audio/mp4" : "audio/wav"
        let dataURI = "data:\(mimeType);base64," + audioData.base64EncodedString()
        let body: [String: Any] = [
            "model": Self.bailianModel,
            "messages": [
                ["role": "user", "content": [["type": "input_audio", "input_audio": ["data": dataURI]]]]
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = budgetSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        // 同样不用 [weak self]，保证临时实例存活到回调。
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(TranscriptionError.network(underlying: error)))
                return
            }
            guard let data = data else {
                completion(.failure(TranscriptionError.noData))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(TranscriptionError.parseError))
                return
            }
            if let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any] {
                let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !content.isEmpty {
                    completion(.success(content))
                } else {
                    // 正常返回但没文字 = 音频里没听出话（静音/太短），与火山 20000003 同等对待
                    completion(.failure(TranscriptionError.noSpeech))
                }
                return
            }
            // 失败：百炼把错误放在 error.message（额度/鉴权/限流等）→ 归为业务失败（可触发切下一个）。
            // 常见的 Key 错 / 欠费 / 限流由 AskAI.extractAPIErrorMessage 统一翻成中文，其余保留原话。
            let msg = AskAI.extractAPIErrorMessage(from: json) ?? "百炼识别失败"
            completion(.failure(TranscriptionError.serverFailed(message: msg)))
        }.resume()
    }

    // MARK: - 共享构造 / 解析

    private func makeRequest(urlString: String, credentials: Credentials, resourceID: String, requestID: String) -> URLRequest? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch credentials.authStyle {
        case .apiKey(let apiKey):
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        case .appAccess(let appID, let accessToken):
            request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
            request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        }
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        return request
    }

    private func makeRequestBody(audioData: Data, format: String) -> [String: Any] {
        var requestDict: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": true,
            "enable_ddc": true,
            "enable_speaker_info": false,
            "enable_channel_split": false,
            "show_utterances": true,
            "vad_segment": false,
            "sensitive_words_filter": ""
        ]
        for (key, value) in hotWordRequestOptions() {
            requestDict[key] = value
        }
        return [
            "user": ["uid": "豆包语音"],
            "audio": [
                "data": audioData.base64EncodedString(),
                "format": format,
                "language": ""
            ],
            "request": requestDict
        ]
    }

    /// 从识别返回里取文本：优先逐句拼接，回退整段 text。
    private static func extractText(from json: [String: Any]) -> String? {
        guard let result = json["result"] as? [String: Any] else { return nil }
        if let utterances = result["utterances"] as? [[String: Any]], !utterances.isEmpty {
            let sentences = utterances.compactMap { u in
                (u["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            if !sentences.isEmpty {
                return sentences.joined(separator: "")
            }
        }
        if let text = (result["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return nil
    }

    /// 火山的处理状态在响应头 X-Api-Status-Code，而非响应体。
    private static func apiStatusCode(from response: URLResponse?) -> Int? {
        guard let http = response as? HTTPURLResponse,
              let raw = http.value(forHTTPHeaderField: "X-Api-Status-Code"),
              let code = Int(raw) else {
            return nil
        }
        return code
    }

    private static func message(from data: Data?) -> String? {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (json["message"] as? String) ?? (json["msg"] as? String) ?? (json["error"] as? String)
    }

    /// 把服务端失败分成「临时繁忙（原地重试）」和「业务失败（建议切版本）」。
    private func classifyServerError(status: Int?, data: Data?) -> TranscriptionError {
        let message = Self.message(from: data) ?? "云端识别失败"
        guard let status = status else {
            return .serverFailed(message: message)
        }
        if status == 55000031 {   // 服务器繁忙：服务过载，临时性
            return .serverBusy(message: "\(message)（服务器繁忙）")
        }
        if status == 20000003 {   // 音频无有效语音（静音 / 太短）→ 当作"无内容"，不报红框
            return .noSpeech
        }
        // 新用户最常撞的两个错，原文是英文（"requested resource not granted" / "Invalid X-Api-Key"），
        // 换成能照着办的中文；其余状态码保留服务端原话。
        if status == 45000030 {   // HTTP 403：账号没开通该识别版本（极速版/标准版/2.0 需分别开通并领免费额度）
            return .serverFailed(message: "火山账号未开通此识别版本，请到控制台开通并领免费额度（45000030）")
        }
        if status == 45000010 {   // HTTP 401：API Key 不对
            return .serverFailed(message: "火山 API Key 无效，请检查是否复制完整（45000010）")
        }
        return .serverFailed(message: "\(message)（状态码 \(status)）")
    }

    /// 百炼凭证：DashScope API Key（与语音优化的通义千问共用同一个 key）。
    private func dashscopeAPIKey() -> String? {
        if let key = config.string(forKey: "dashscope_api_key", envKey: "DASHSCOPE_API_KEY"),
           !key.isEmpty {
            return key
        }
        return nil
    }

    /// 火山凭证：新版单 API Key 优先，兼容旧版 App ID + Access Token。
    private func volcanoCredentials() -> Credentials? {
        // 新版控制台：单个 API Key 鉴权（优先）
        if let apiKey = config.string(forKey: "bigasr_api_key", envKey: "BIGASR_API_KEY"),
           !apiKey.isEmpty {
            return Credentials(authStyle: .apiKey(apiKey))
        }
        // 旧版控制台：App ID + Access Token（向后兼容，老用户配置不中断）
        if let appID = config.string(forKey: "bigasr_app_id", envKey: "BIGASR_APP_ID"),
           let accessToken = config.string(forKey: "bigasr_access_token", envKey: "BIGASR_ACCESS_TOKEN"),
           !appID.isEmpty,
           !accessToken.isEmpty {
            return Credentials(authStyle: .appAccess(appID: appID, accessToken: accessToken))
        }
        return nil
    }
}

import Foundation

/// DeepSeek 自家的联网搜索（POST {base}/v1/tools/search，和对话同一个 Key）。
/// 问 AI 走 DeepSeek 时，模型调用 web_search 就用它查，再把结果连同原问题（和截图）交回 deepseek-flash 作答，
/// 不再转给千问。文档：https://api-docs.deepseek.com/guides/search （2026-10-19 查，每千次 0.75 美元）。
public enum DeepSeekSearch {
    public struct Result: Equatable, Sendable {
        public let title: String
        public let url: String
        public let date: String?
        /// 文档说这段 600 到 800 字、写给模型读的
        public let summary: String
    }

    /// 取几条：够交叉核对，又不至于把提示词撑得太长拖慢首字
    public static let count = 6
    static let timeout: TimeInterval = 10

    public static var endpoint: URL? { URL(string: DeepSeekEndpoint.base + "/v1/tools/search") }

    /// 文档限定 query 1 到 128 个字符
    public static func requestBody(query: String) -> [String: Any] {
        ["query": String(query.prefix(128)), "count": count]
    }

    public static func parseResults(_ data: Data) -> [Result]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }
        return results.compactMap { r in
            guard let url = r["url"] as? String else { return nil }
            let summary = (r["summary"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (r["snippet"] as? String ?? "")
            return Result(title: r["title"] as? String ?? "", url: url, date: r["date"] as? String, summary: summary)
        }
    }

    /// 接到 system prompt 后面的搜索结果段。模型凭记忆补全是「瞎编」的主要来源，所以明说以结果为准、查不到就说查不到。
    public static func promptSection(query: String, results: [Result]) -> String {
        var lines = ["", "", "刚刚联网搜索了「\(query)」。回答涉及事实、数字、日期时以下面的结果为准；结果里没有的，直说没查到，不要凭记忆补。"]
        if results.isEmpty {
            lines.append("（这次搜索没有找到结果。）")
        }
        for (i, r) in results.enumerated() {
            let date = r.date.map { "（\($0.prefix(10))）" } ?? ""
            lines.append("[\(i + 1)] \(r.title)\(date) \(r.url)\n\(r.summary)")
        }
        return lines.joined(separator: "\n")
    }

    /// 会员模式下发到后台的搜索转发（POST /v1/askfree/search，请求、返回和 DeepSeek 的一样），带设备令牌和用量号
    static func request(query: String, apiKey: String, member: AskMember?) -> URLRequest? {
        guard let url = member.map({ MemberEndpoint.url($0.credentials.base, MemberEndpoint.searchPath) }) ?? endpoint,
              let body = try? JSONSerialization.data(withJSONObject: requestBody(query: query)) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: member == nil ? timeout : 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (name, value) in member?.headers ?? [:] { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body
        return request
    }

    public static func search(query: String, apiKey: String, member: AskMember? = nil,
                              completion: @escaping (Swift.Result<[Result], Error>) -> Void) {
        guard let request = request(query: query, apiKey: apiKey, member: member) else {
            completion(.failure(AskAI.AskError.apiError("DeepSeek 搜索地址无效")))
            return
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(member != nil ? MemberAPIError.network(error) : error)); return }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if let member, let http, status == 200, let headers = MemberUseHeaders(http) { member.onUse(headers) }
            if member != nil, status != 200 {
                completion(.failure(MemberAPIError.from(status: status, data: data, response: http)))
                return
            }
            guard status == 200, let data, let results = parseResults(data) else {
                completion(.failure(AskAI.AskError.apiError("DeepSeek 搜索失败（\(status)）")))
                return
            }
            completion(.success(results))
        }.resume()
    }
}

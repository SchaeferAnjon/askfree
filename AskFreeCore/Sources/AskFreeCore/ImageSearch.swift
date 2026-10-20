import Foundation

/// 联网回答附的图。thumb 给回答下方的小图，full 点开看大图，pageURL 是图所在的网页（来源）。
public struct AskImage: Equatable, Sendable, Identifiable {
    public var id: String { full }
    public let thumb: String
    public let full: String
    public let pageURL: String
    public let title: String
    public let width: Int
    public let height: Int

    public init(thumb: String, full: String, pageURL: String, title: String, width: Int, height: Int) {
        self.thumb = thumb; self.full = full; self.pageURL = pageURL; self.title = title; self.width = width; self.height = height
    }
}

/// 找图：DuckDuckGo 图片接口，不要 Key。做法照 Relecture（~/Projects/relecture/app/server/imgSearchDdg.ts）：
/// ① GET duckduckgo.com/?q=…&iax=images 从页面里抠一次性 vqd；② GET duckduckgo.com/i.js?q=…&vqd=… 拿 JSON。
/// 2026-09-22 实测：请求头要像 Safari（UA + Accept + Accept-Language），Chrome UA 且不带 Accept 会 403；
/// 「Verkehrszeichen 205」0.7 秒回 98 张，头一张就是那个标志。接口没有官方文档，哪天不通了就是返回空，不影响回答。
/// 千问的联网搜索只回文字、DeepSeek 不能联网，所以图只能这么找。
public enum ImageSearch {
    public static let settingKey = "ask_images_enabled"
    public static var isEnabled: Bool { AskFreeConfig.shared.bool(forKey: settingKey, defaultValue: true) }
    /// 回答下方放几张
    public static let resultLimit = 3
    static let timeout: TimeInterval = 8
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept-Language": "en-US,en;q=0.9"]
        return URLSession(configuration: config)
    }()

    /// 模型点名要配图时在回答里单独写一行 `[[图片: 搜索词]]`（提示词见 promptSuffix）。
    /// 返回去掉这行后给用户看的文字，和搜索词。流式中途 `[[` 还没合上时先把这截藏起来，免得闪一下标记；
    /// 完整回答（isFinal）里没合上的 `[[` 是正文，原样显示。
    public static func extractMarker(_ text: String, isFinal: Bool = false) -> (display: String, query: String?) {
        let ns = text as NSString
        if let m = markerRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let query = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let display = ns.replacingCharacters(in: m.range, with: "")
                .trimmingCharacters(in: .newlines)
            return (display, query.isEmpty ? nil : query)
        }
        if !isFinal, let open = text.range(of: "[[", options: .backwards), text[open.upperBound...].range(of: "]]") == nil {
            return (String(text[..<open.lowerBound]).trimmingCharacters(in: .newlines), nil)
        }
        return (text, nil)
    }

    private static let markerRegex = try! NSRegularExpression(pattern: #"\[\[\s*图片\s*[:：]\s*([^\]\n]+?)\s*\]\][ \t]*\n?"#)

    /// 拼进系统提示词：告诉模型面板能放图、什么时候要图、怎么点名
    public static let promptSuffix = """

    面板能在回答下方放几张网上的图片。用户想看照片、长相、样子（如「找个照片我看一下」「长什么样」「给我看看」），回答的第一行单独写 `[[图片: 搜索词]]`，搜索词写最容易搜到图的说法（人名、物名、地名用原文，如 Selena Gomez），再换行照常回答；面板会把这一行换成图片。这种时候不要说你没法发图。用户没想看图就不要写这一行。
    """

    /// 页面里的一次性 token：vqd="…" 或 vqd='…'
    public static func parseVqd(_ html: String) -> String? {
        guard let range = html.range(of: #"vqd=['"]([^'"]+)['"]"#, options: .regularExpression) else { return nil }
        let match = html[range]
        guard let start = match.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let inner = match[match.index(after: start)...].dropLast()
        return inner.isEmpty ? nil : String(inner)
    }

    /// i.js 的 JSON → 结果。缺 image 的跳过；太小的（图标、表情）跳过。
    public static func parseResults(_ data: Data, limit: Int = resultLimit) -> [AskImage] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        var out: [AskImage] = []
        for r in results {
            guard let full = r["image"] as? String, !full.isEmpty else { continue }
            let w = r["width"] as? Int ?? 0, h = r["height"] as? Int ?? 0
            if w > 0, h > 0, w < 200 || h < 150 { continue }
            out.append(AskImage(thumb: (r["thumbnail"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? full,
                                full: full, pageURL: r["url"] as? String ?? "", title: r["title"] as? String ?? "",
                                width: w, height: h))
            if out.count >= limit { break }
        }
        return out
    }

    /// 搜不到、被拦、超时一律回空数组：图是锦上添花，不能拖累回答
    public static func search(_ query: String, completion: @escaping ([AskImage]) -> Void) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, var home = URLComponents(string: "https://duckduckgo.com/") else { completion([]); return }
        home.queryItems = [.init(name: "q", value: q), .init(name: "iar", value: "images"), .init(name: "iax", value: "images"), .init(name: "ia", value: "images")]
        var homeRequest = URLRequest(url: home.url!)
        homeRequest.setValue("text/html", forHTTPHeaderField: "Accept")
        session.dataTask(with: homeRequest) { data, _, _ in
            guard let data, let html = String(data: data, encoding: .utf8), let vqd = parseVqd(html),
                  var api = URLComponents(string: "https://duckduckgo.com/i.js") else { completion([]); return }
            api.queryItems = [.init(name: "l", value: "us-en"), .init(name: "o", value: "json"), .init(name: "q", value: q),
                              .init(name: "vqd", value: vqd), .init(name: "f", value: ",,,,,"), .init(name: "p", value: "1")]
            var request = URLRequest(url: api.url!)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("https://duckduckgo.com/", forHTTPHeaderField: "Referer")
            session.dataTask(with: request) { data, response, _ in
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { completion([]); return }
                completion(parseResults(data))
            }.resume()
        }.resume()
    }
}

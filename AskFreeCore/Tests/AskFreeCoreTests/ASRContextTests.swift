import XCTest
@testable import AskFreeCore

final class ASRContextTests: XCTestCase {
    func testHotwordsAreScreenTermsWithPointerWordFirst() {
        let c = ASRContext(screenLines: ["I deleted the old GitHub artifacts before testing.", "SyntaxError: EOL while scanning", "bigmodel_nostream 二遍识别"],
                           pointerWord: "artifacts")
        XCTAssertEqual(c.hotwords.first, "artifacts")
        XCTAssertTrue(c.hotwords.contains("GitHub"))
        XCTAssertTrue(c.hotwords.contains("SyntaxError"))
        XCTAssertTrue(c.hotwords.contains("bigmodel_nostream"))
        XCTAssertFalse(c.hotwords.contains("the"), "常用词不当热词")
        XCTAssertEqual(c.hotwords.filter { $0.lowercased() == "artifacts" }.count, 1, "不重复")
        // 中文的词不拿来当热词：一行里切不准，乱塞反而容易误认
        XCTAssertFalse(c.hotwords.contains { $0.contains("识别") })
    }

    func testHotwordLimit() {
        let line = (1...60).map { "word\($0)" }.joined(separator: " ")
        XCTAssertEqual(ASRContext(screenLines: [line]).hotwords.count, ASRContext.hotwordLimit)
    }

    func testCorpusContextPutsNewestDialogFirst() throws {
        let c = ASRContext(screenLines: ["SyntaxError: EOL while scanning"], pointerWord: "EOL",
                           dialog: [ASRDialogTurn(question: "第一问", answer: "第一答"), ASRDialogTurn(question: "第二问", answer: "第二答")])
        let json = try XCTUnwrap(c.corpusContext())
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(obj["context_type"] as? String, "dialog_ctx")
        let data = try XCTUnwrap(obj["context_data"] as? [[String: String]]).map { $0["text"] ?? "" }
        XCTAssertEqual(Array(data.prefix(4)), ["第二答", "第二问", "第一答", "第一问"])
        XCTAssertTrue(data.last?.contains("SyntaxError: EOL") == true)
        XCTAssertEqual((obj["hotwords"] as? [[String: String]])?.first?["word"], "EOL")
        XCTAssertNil(ASRContext().corpusContext())
    }

    func testContextTextStaysShort() throws {
        let long = String(repeating: "很长的一段回答。", count: 200)
        let c = ASRContext(screenLines: [String(repeating: "x", count: 2000)],
                           dialog: (1...5).map { ASRDialogTurn(question: "问\($0)", answer: long) })
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(c.corpusContext()).utf8)) as? [String: Any])
        let total = try XCTUnwrap(obj["context_data"] as? [[String: String]]).map { $0["text"]?.count ?? 0 }.reduce(0, +)
        XCTAssertLessThanOrEqual(total, ASRContext.textLimit)
    }
}

final class ASRRequestBodyTests: XCTestCase {
    /// 发给火山的请求体：上下文放在 request.corpus.context（和文档、2026-11-07 实测通过的写法一样）
    func testContextGoesIntoCorpus() throws {
        let context = ASRContext(screenLines: ["GitHub artifacts"], pointerWord: "artifacts").corpusContext()
        let body = CloudASRTranscriber().makeRequestBody(audioData: Data([1, 2]), format: "m4a", context: context)
        let request = try XCTUnwrap(body["request"] as? [String: Any])
        let corpus = try XCTUnwrap(request["corpus"] as? [String: Any])
        XCTAssertEqual(corpus["context"] as? String, context)
        let none = CloudASRTranscriber().makeRequestBody(audioData: Data([1]), format: "m4a", context: nil)
        XCTAssertNil(((none["request"] as? [String: Any])?["corpus"] as? [String: Any])?["context"])
    }
}

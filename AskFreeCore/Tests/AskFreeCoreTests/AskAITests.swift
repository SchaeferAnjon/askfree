import XCTest
@testable import AskFreeCore

final class AskAITests: XCTestCase {

    // MARK: - 额度/业务错误提取

    func testExtractAPIErrorMessageFromCommonShapes() {
        // OpenAI/qwen 兼容：{"error":{"message":...}}，额度类 → 翻成中文并带 code
        XCTAssertEqual(
            AskAI.extractAPIErrorMessage(from: ["error": ["message": "Free allocated quota exceeded", "code": "insufficient_quota"]]),
            "账号欠费或免费额度已用完，请到服务商控制台检查（insufficient_quota）")
        // DashScope 欠费：顶层 code+message
        XCTAssertEqual(
            AskAI.extractAPIErrorMessage(from: ["code": "Arrearage", "message": "Access denied, please make sure your account has enough balance"]),
            "账号欠费或免费额度已用完，请到服务商控制台检查（Arrearage）")
        // error 为字符串：限流 → 中文
        XCTAssertEqual(AskAI.extractAPIErrorMessage(from: ["error": "rate limit exceeded"]), "请求太频繁或额度超限，稍后再试")
        // 只有 code：Key 错 → 中文
        XCTAssertEqual(AskAI.extractAPIErrorMessage(from: ["error": ["code": "InvalidApiKey"]]), "API Key 无效，请检查是否复制完整（InvalidApiKey）")
        // 认不出的错误：保留原话
        XCTAssertEqual(AskAI.extractAPIErrorMessage(from: ["error": ["message": "model qwen-x is not supported", "code": "invalid_parameter_error"]]),
                       "model qwen-x is not supported")
        // 正常响应（有 choices）→ 无错误可提取
        XCTAssertNil(AskAI.extractAPIErrorMessage(from: ["choices": [["message": ["content": "ok"]]]]))
        XCTAssertNil(AskAI.extractAPIErrorMessage(from: nil))
    }

    /// 2026-08-17 用真实 key 打服务商实测抓回来的原文，确保翻译命中
    func testFriendlyProviderErrorMatchesRealPayloads() {
        // 百炼 DashScope：Key 错（HTTP 401）
        XCTAssertEqual(
            AskAI.extractAPIErrorMessage(from: ["error": [
                "message": "Incorrect API key provided. For details, see: https://help.aliyun.com/zh/model-studio/error-code#apikey-error",
                "type": "invalid_request_error", "code": "invalid_api_key"]]),
            "API Key 无效，请检查是否复制完整（invalid_api_key）")
        // 百炼 DashScope：没带 Key（HTTP 401，code 为 null）
        XCTAssertEqual(
            AskAI.extractAPIErrorMessage(from: ["error": [
                "message": "You didn't provide an API key. You need to provide your API key in an Authorization header using Bearer auth (i.e. Authorization: Bearer YOUR_KEY). ",
                "type": "invalid_request_error", "code": NSNull()]]),
            "API Key 无效，请检查是否复制完整")
        // 火山 Ark：Key 错（HTTP 401）
        XCTAssertEqual(
            AskAI.extractAPIErrorMessage(from: ["error": [
                "code": "AuthenticationError",
                "message": "The API key format is incorrect. Request id: 0217869805600638c140f267f4351837af8462310b5bfee937427",
                "param": "", "type": "Unauthorized"]]),
            "API Key 无效，请检查是否复制完整（AuthenticationError）")
    }

    func testAskErrorAPIErrorCarriesMessage() {
        let err = AskAI.AskError.apiError("余额不足")
        XCTAssertEqual(err.errorDescription, "余额不足")
    }
}

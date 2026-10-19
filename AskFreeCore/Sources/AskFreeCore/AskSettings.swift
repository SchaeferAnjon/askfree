import Foundation

/// 看屏幕问 AI 的配置项。读写都走 AskFreeConfig，和其他功能一致。
public enum AskSettings {
    /// 提问时带屏幕截图
    public static let screenshotEnabledKey = "ask_screenshot_enabled"
    public static let screenshotDefaultEnabled = true
    /// 手填视觉模型名，覆盖内置默认值
    public static let visionModelKey = "ask_vision_model"
    /// 手填视觉模型时所在的服务商。视觉模型名只对这一家有效，换了服务商就不再用它
    public static let visionModelProviderKey = "ask_vision_model_provider"

    public static var isScreenshotEnabled: Bool {
        AskFreeConfig.shared.bool(forKey: screenshotEnabledKey, defaultValue: screenshotDefaultEnabled)
    }

    public static var visionModelOverride: String? {
        let raw = AskFreeConfig.shared.string(forKey: visionModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    /// 当前服务商能用的手填视觉模型。填的时候记下了服务商、和现在的对不上就忽略，
    /// 否则在千问下填的 qwen3-vl-plus 会被发到 DeepSeek 或智谱，每次都报模型不存在。
    /// 没记服务商的旧值照旧生效。
    public static func visionOverride(provider: String) -> String? {
        guard let model = visionModelOverride else { return nil }
        let owner = AskFreeConfig.shared.string(forKey: visionModelProviderKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let owner, !owner.isEmpty, owner != provider { return nil }
        return model
    }
}

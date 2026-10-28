import Foundation

/// 正式版与开发版（scripts/dev_run.sh 编出来的 Ask Free Dev）的身份区分。
///
/// 开发版 bundle id 带 `.dev` 后缀，与正式版完全隔离：
/// - 配置目录 `~/.config/askfree-dev/`（正式版 `~/.config/askfree/`）
/// - 不碰钥匙串：密钥存在开发版配置目录下的 `dev_secrets.json`（0600），也可用环境变量覆盖
/// - 调试日志文件名加 `-dev`
/// 判断只看运行时 bundle id，正式版代码路径不变。
public enum AppIdentity {
    public static let devBundleID = "io.github.schaeferanjon.askfree.dev"

    /// 当前进程是不是开发版。单元测试（xctest）里为 false，行为与正式版一致。
    public static let isDevBuild: Bool = Bundle.main.bundleIdentifier == devBundleID

    /// 带 -selfTest 启动的启动自测（CI 在正式包上跑）
    public static let isSelfTest: Bool = ProcessInfo.processInfo.arguments.contains("-selfTest")

    /// 启动自测和开发版的 -snapshotPages：配置、历史、日志、密钥都换到一个空的临时目录，
    /// 不碰这台 Mac 上的设置和钥匙串，每台机器上画出来的都是同一个「刚装好」的样子
    public static let usesTemporaryData: Bool = isSelfTest
        || (isDevBuild && ProcessInfo.processInfo.arguments.contains("-snapshotPages"))

    /// 上面那个临时目录，退出时由 App 删掉
    public static let temporaryDataDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AskFree-selftest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    /// 开发版带 -demoData <目录> 启动（拍 README 截图用，见 scripts/readme-shots.mjs）：配置和历史换到这个目录，
    /// 截图里只有演示用的问答，不带开发版平时测出来的历史；Key 照旧读开发版的 dev_secrets.json
    public static let demoDataDirectory: URL? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard isDevBuild, let i = arguments.firstIndex(of: "-demoData"), i + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: (arguments[i + 1] as NSString).expandingTildeInPath, isDirectory: true)
    }()

    /// 平时的配置目录：正式版 ~/.config/askfree，开发版 ~/.config/askfree-dev
    private static var homeConfigDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(isDevBuild ? ".config/askfree-dev" : ".config/askfree", isDirectory: true)
    }

    /// 配置目录：正式版 ~/.config/askfree，开发版 ~/.config/askfree-dev（-demoData 时是那个目录）
    public static var configDirectory: URL {
        if usesTemporaryData { return temporaryDataDirectory.appendingPathComponent("config", isDirectory: true) }
        return demoDataDirectory ?? homeConfigDirectory
    }

    /// 调试日志：正式版 ~/Library/Logs/AskFree.log，开发版 AskFree-dev.log
    public static var debugLogFileURL: URL {
        if usesTemporaryData { return temporaryDataDirectory.appendingPathComponent("AskFree-selftest.log") }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(isDevBuild ? "Library/Logs/AskFree-dev.log" : "Library/Logs/AskFree.log")
    }

    /// 默认密钥存储：正式版用系统钥匙串；开发版用配置目录下的文件，避免 ad hoc 签名每次重编都弹钥匙串授权框。
    /// 启动自测也用文件（在临时目录里，是空的）
    public static func defaultSecretStore() -> SecretStoring {
        if usesTemporaryData {
            return FileSecretStore(fileURL: configDirectory.appendingPathComponent("dev_secrets.json"))
        }
        if isDevBuild {
            return FileSecretStore(fileURL: homeConfigDirectory.appendingPathComponent("dev_secrets.json"))
        }
        return KeychainSecretStore.shared
    }
}

/// 开发版专用：把密钥存成本地 JSON 文件（权限 0600）。正式版不使用。
public final class FileSecretStore: SecretStoring {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func get(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return load()[account]
    }

    @discardableResult
    public func set(_ account: String, _ value: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var all = load()
        if let value, !value.isEmpty { all[account] = value } else { all.removeValue(forKey: account) }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return obj
    }
}

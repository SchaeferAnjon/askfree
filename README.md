# Ask Free

按一个键说出问题，AI 看着你的屏幕回答。macOS 菜单栏应用，用你自己的 API Key，开源免费。

## 怎么用

- **看屏幕问 AI**（默认右 Option）：按住说出问题、松开提问；或轻点一下开始、再点一下结束。按下那一刻鼠标指在哪，AI 就重点看哪。
- **只提问，不看屏幕**：在「设置 → 快捷键」里自己设一个键，不截屏，更快。
- 回答显示在屏幕右上角的面板里：
  - 回答还在时再按快捷键 → 追问（带着这个话题的上下文）
  - 开头说「新话题」→ 另起一个话题
  - 开头说「搜一下」→ 直接联网查
  - 说话时按 Esc → 取消
- **历史**：主窗口「历史」页（或菜单栏「历史记录」）按天列出问过的话题，点开看每一轮问答，可搜索、复制、右键删除、清空。

## 需要准备

1. macOS 14 或更新，Apple 芯片。
2. 两个 API Key，填在「模型」页：
   - **语音识别**：火山引擎（豆包）录音文件识别，[控制台](https://console.volcengine.com/speech/app)。
   - **问答模型**：DeepSeek（最快，需要时自己联网，[控制台](https://platform.deepseek.com/api_keys)）或阿里百炼千问（自带联网搜索，[控制台](https://bailian.console.aliyun.com/)）。
3. 三项系统权限：麦克风、辅助功能（全局快捷键）、屏幕录制（看屏幕问）。

Key 存在系统钥匙串里，配置在 `~/.config/askfree/`。语音和问题直连你选的服务商，不经过任何中间服务器；截图只用于当次提问，不保存。问答历史只存文字，在 `~/.config/askfree/history.jsonl`（仅本机、仅你可读）。

## 从源码编译

用 Xcode 26.3 编译通过（更早的版本没试过）。

```bash
bash scripts/install_app.sh   # 编译并安装到 /Applications/Ask Free.app
bash build.sh                 # 只编译，产物在 dist/Ask Free.app
bash scripts/dev_run.sh       # 编译并启动开发版 Ask Free Dev（独立配置，不影响正式版）
```

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成。增删源文件后运行 `xcodegen generate`（`build.sh` 检测到 xcodegen 时会自动运行）。

核心逻辑在 Swift Package `AskFreeCore` 里，单元测试：

```bash
cd AskFreeCore && swift test
```

## 目录

```
Sources/        App 界面：菜单栏、录音胶囊、回答面板、主窗口（首页 / 模型 / 设置 / 关于）
AskFreeCore/    核心逻辑：语音识别、问答与联网、快捷键状态机、配置与钥匙串
Resources/      图标与 entitlements
scripts/        安装与开发脚本
```

## 致谢与许可

Ask Free 基于 [Typefree](https://github.com/kdsz001/typefree)（作者 kdsz001）的「问 AI」功能修改而来，去掉了听写、润色、词库、会员与自动更新等部分，只保留语音提问。

以 [GPL-3.0](LICENSE) 发布，与上游一致。

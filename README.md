<p align="center"><img src="docs/readme/icon.png" width="96" height="96" alt="Ask Free"></p>

<h1 align="center">Ask Free</h1>

<p align="center"><b>Press a key, ask out loud, and AI answers looking at your screen.</b></p>

<p align="center"><a href="https://github.com/SchaeferAnjon/askfree/releases/latest"><b>Download for Mac (Apple silicon)</b></a></p>

<p align="center"><a href="https://askfree.us-cloud.uk/"><img src="docs/readme/en/website.svg" width="274" height="36" alt="Website (in Chinese): askfree.us-cloud.uk"></a></p>

<p align="center">
<a href="https://github.com/SchaeferAnjon/askfree/releases/latest"><img src="https://img.shields.io/github/v/release/SchaeferAnjon/askfree?label=latest&color=111113" alt="Latest release"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-111113" alt="GPL-3.0"></a>
<img src="https://img.shields.io/badge/macOS-14%2B-111113" alt="macOS 14+">
<img src="https://img.shields.io/badge/chip-Apple%20silicon-111113" alt="Apple silicon">
</p>

<p align="center"><sub><b>English</b> · <a href="README.zh-CN.md">简体中文</a></sub></p>

<!-- Hero animation (README item 30) goes here, an 840 px wide WebP, for example:
<p align="center"><img src="docs/readme/en/ask.webp" width="840" alt="Point at something on screen, hold the key and ask; the answer card in the top right corner answers"></p>
-->

> [!NOTE]
> The app's interface is in Chinese only. Speech recognition and the answer models are services based in mainland China: Volcano Engine (ByteDance) turns your voice into text, and DeepSeek or Alibaba Cloud Bailian (Qwen) answers. You need your own API keys from them, and you pay them directly. The website and its setup guide are in Chinese too.

## What it does

You are reading a web page, a paper or some code and hit something you don't get. Point at it, hold the key, ask "what does this mean?" and let go: the answer appears in the top right corner of the screen. No switching windows, no screenshots to take, no typing. A macOS menu bar app that uses your own API keys; free and open source.

- **Answers about your screen**: the moment you press the key, it captures the whole screen and the window under the pointer and sends them to the AI with your question.
- **Knows what you point at**: a red box marks where the pointer is. Ask about "this word" or "this button" and it answers about what is in the box; ask "what is this page about" and it reads the whole page.
- **Follow-up questions**: press the key again while the answer is still showing and you continue the same topic; start with 新话题 ("new topic") to start over.
- **Searches the web by itself**: for news, prices or exchange rates it looks them up; start with 搜一下 ("search") to search right away.
- **Pictures in the answer**: ask to see a photo of something and 3 images from the web appear below the answer; click one to open the original.
- **History with screenshots**: every question and answer is kept on your Mac with the screenshots sent to the AI, listed by day; search, copy or delete them.
- **Type instead**: when you can't talk, double-tap a key (Control, say), it captures the screen and you type the question.

<details>
<summary>Which languages you can ask in</summary>

- **Speaking**: according to Volcano Engine's [speech recognition docs](https://www.volcengine.com/docs/6561/1354868) (in Chinese), when no language is set (Ask Free sets none) it recognizes Mandarin Chinese and English, plus Cantonese, Shanghainese, Hokkien (Minnan), Sichuanese and Shaanxi dialect. Japanese, Korean and other languages need the language set in the request, which Ask Free does not do yet. The docs say nothing specific about mixing Chinese and English in one sentence. This is what the docs say (checked October 27, 2026); not tested.
- **Typing**: skips speech recognition, so any language DeepSeek or Qwen can read works.
- **Answers** come in the language you ask in: ask in English and it answers in English.
- The interface is Chinese only.

</details>

## How to use it

<!-- Feature animation (README item 30) goes here, for example follow-ups and web search:
<p align="center"><img src="docs/readme/en/followup.webp" width="840" alt="Press the key again while the answer is showing to ask a follow-up; follow-ups are numbered"></p>
-->

No shortcut is set until you pick one, since every keyboard is different: the welcome guide asks you to choose one the first time (right Option, right Command, fn, Control, or record your own), and you can change it later on the **快捷键** (Shortcuts) page of the main window.

| Way to ask | How | Sees the screen |
|---|---|---|
| **Ask about the screen** | Hold the key, speak, let go to ask; or tap once to start and tap again to stop | Yes, focused on where the pointer was when you pressed |
| **Just ask** | Set a second key on the **快捷键** (Shortcuts) page; same gestures | No, faster |
| **Type** | Pick a double-tap key on the **快捷键** (Shortcuts) page (double Control, say) and type after the double tap | Yes, captures the current screen |

The answer appears in a panel in the top right corner:

- Press the key again while the answer is showing → follow-up question (keeps the context)
- Start with 新话题 ("new topic") → a new topic
- Start with 搜一下 ("search") → search the web right away
- Press Esc while speaking → cancel

**History**: the **历史** (History) page of the main window, or **历史记录** in the menu bar, lists your topics by day. Open one to see each question, answer and the screenshot sent with it; search, copy, delete with a right click, or clear everything.

<!-- Real screenshots (README item 31) go here, like the "Real screenshots" table in the MeetCaption README:
## Real screenshots

<table>
<tr>
<td colspan="2" align="center"><img src="docs/readme/shots/answer.jpg" width="800" alt="An answer about the screen, with a red box at the pointer"><br><sub>Answering about the screen</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/readme/shots/followup.jpg" width="380" alt="Numbered follow-ups"><br><sub>Follow-ups</sub></td>
<td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/readme/shots/history-dark.jpg"><img src="docs/readme/shots/history-light.jpg" width="420" alt="The History page of the main window"></picture><br><sub>History</sub></td>
</tr>
</table>
-->

## What you need

1. A Mac with Apple silicon, macOS 14 or later.
2. Two API keys, entered in the welcome guide or on the **语音与模型** (Voice and models) page. The [setup guide](https://askfree.us-cloud.uk/#page=setup) on the website (in Chinese) shows where to get them, step by step.
   - **Speech recognition**: Volcano Engine (Doubao) audio file recognition, [console](https://console.volcengine.com/speech/app). Each recognition version comes with 20 free hours, valid for six months.
   - **Answers**: DeepSeek (fastest, searches the web when needed, [console](https://platform.deepseek.com/api_keys)) or Qwen on Alibaba Cloud Bailian (built-in web search, [console](https://bailian.console.aliyun.com/), 1 million free tokens per model, valid for 90 days after you sign up).
3. Three system permissions: Microphone, Accessibility (for the global shortcut) and Screen Recording (for asking about the screen).

The app costs nothing; recognition and answers are billed by each provider to your own account. Once the free quotas run out, one spoken question about the screen costs about CNY 0.01 to 0.025; asking 20 times a day comes to about CNY 6 to 15 a month.

<details>
<summary>How the cost per question is worked out</summary>

Estimated from each provider's official prices as of October 27, 2026, in CNY. Usage comes from 9 spoken questions about the screen in the development build's log: recordings of 2.4 to 25 seconds, half of them 4.5 seconds or shorter; answers of 58 to 316 Chinese characters. The log does not record token counts, so the tokens below are worked out from character counts and screenshot sizes.

| Item | Per question | How |
|---|---|---|
| Speech recognition: Volcano Engine turbo (default) | CNY 0.006 to 0.013 | 5 to 10 seconds per question at [CNY 4.5 per hour, pay as you go](https://www.volcengine.com/docs/6561/1359370); the standard version is CNY 2.3 per hour |
| Answer about the screen: DeepSeek (deepseek-flash) | CNY 0.004 to 0.011 | About 3,000 input tokens (at most 2,048 for the two screenshots, about 800 for the prompt) and 200 to 600 output tokens. [On weekdays 9:00–12:00 and 14:00–18:00 Beijing time](https://api-docs.deepseek.com/quick_start/pricing) input is CNY 2 and output CNY 8 per million tokens; half that at other times |
| Answer about the screen: Qwen (qwen3.8-flash) | About CNY 0.004 | About 3,300 input tokens (about 2,500 for the two screenshots) and at most 600 output tokens, at [CNY 0.8 input and CNY 2.7 output per million tokens](https://help.aliyun.com/zh/model-studio/model-pricing) |
| One web search (when the AI decides to, or you say 搜一下) | CNY 0.005 to 0.01 extra | DeepSeek search is CNY 5 per 1,000 searches, and its 6 results add about 2,500 input tokens; Qwen web search is CNY 3 per 1,000 searches, and the pages it reads count as input tokens |

In total, one question about the screen costs CNY 0.01 to 0.025, more than half of it speech recognition. Follow-ups and "just ask" send no screenshots and cost less; typed questions skip recognition. Prices change; the providers' pages have the current ones.

</details>

## Install

| | Download | Needs |
|---|---|---|
| **Mac with Apple silicon** (M1 or later) | `AskFree-<version>.zip` on the [releases page](https://github.com/SchaeferAnjon/askfree/releases/latest) | macOS 14 or later |

Macs with an Intel chip are not supported. Unzip the download, drag `Ask Free.app` into **Applications** and open it from there; opened straight from **Downloads**, macOS runs it from a temporary read-only location.

Earlier versions are on the [releases page](https://github.com/SchaeferAnjon/askfree/releases) too. Ask Free does not update itself yet; new versions are published on the same page.

<details>
<summary>The first time you open it</summary>

- **macOS says the developer cannot be verified**: this version has a Developer ID signature but is not notarized by Apple yet. Open **System Settings**, go to **Privacy & Security**, scroll to the bottom and click **Open Anyway**.
- **The welcome guide** has six steps: welcome, permissions, speech recognition, answer model, shortcut, and finally one real question to check everything works. It takes about 3 minutes.
- **Permissions**: for the microphone, click **Allow** in the system prompt. For Accessibility and Screen Recording, click **打开系统设置** (Open System Settings): an Ask Free icon floats next to System Settings; drag it to the left into the list and the switch turns on. After Screen Recording, macOS asks you to quit and reopen Ask Free; the guide comes back to the same step.
- **Upgrading from 1.0.1**: macOS may ask for Accessibility and Screen Recording again. On the **权限** (Permissions) page of the main window, click **打开系统设置** and drag the icon into the list.

</details>

## Privacy

- No account, no sign-up, and no server of ours: Ask Free talks only to the providers you choose.
- Your voice goes straight to Volcano Engine to be turned into text. Recordings are not kept.
- Your question and the screenshots go to the answer model you chose, DeepSeek or Alibaba Cloud Bailian.
- The screen is captured only at the moment you press the key (or double-tap the typing key): a scaled-down image of the whole screen and a sharp one of the window under the pointer. The "just ask" key captures nothing, and nothing is captured with **让 AI 看屏幕** (Let AI see the screen) turned off on the **回答方式** (Answers) page.
- Web searches go to the same provider: DeepSeek's search API, or Qwen's built-in web search.
- **联网的回答附上图** (Pictures with web answers) is on by default: when the answer needs pictures, one image search term (or your question, if there is no term) goes to DuckDuckGo, never the screenshots or the recording. Turn it off on the **回答方式** (Answers) page.
- Keys are stored in the macOS Keychain. History and screenshots stay on your Mac in `~/.config/askfree/`, readable only by your user account: text in `history.jsonl`, the screenshots sent to the model and thumbnails of found images in `history-images/`. Delete single entries or everything on the **历史** (History) page.

## Build from source

Builds with Xcode 26.3 (earlier versions not tried).

```bash
bash scripts/install_app.sh   # build and install to /Applications/Ask Free.app
bash build.sh                 # build only, output in dist/Ask Free.app
bash scripts/dev_run.sh       # build and start the development build Ask Free Dev (own settings, leaves the release build alone)
```

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or removing source files, run `xcodegen generate` (`build.sh` runs it when xcodegen is installed).

The core logic lives in the Swift package `AskFreeCore`. Unit tests:

```bash
cd AskFreeCore && swift test
```

## Layout

```
Sources/        The app's interface: menu bar, recording capsule, answer panel, main window (home, history, settings), welcome guide
AskFreeCore/    Core logic: speech recognition, answers and web search, shortcut state machine, settings and Keychain
Resources/      Icon and entitlements
scripts/        Install and development scripts
```

## Credits and license

Ask Free is built from the "Ask AI" feature of [Typefree](https://github.com/kdsz001/typefree) by kdsz001, with dictation, polishing, the word list, membership and auto-update removed, keeping only spoken questions.

Released under [GPL-3.0](LICENSE), the same as upstream.

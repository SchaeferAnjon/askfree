// UpdateSettings.swift
// Ask Free
//
// 「通用 → 更新」：自动检查并下载的开关；现在走到哪一步（AppUpdater.phase）、「检查更新」、下好了「重启更新」。
// 和 MeetCaption 设置里的「更新」一组同一套说法。

import SwiftUI
#if canImport(AskFreeCore)
import AskFreeCore
#endif

struct UpdateSettingsGroup: View {
    @ObservedObject private var updater = AppUpdater.shared
    private let version = Bundle.main.appVersionString

    var body: some View {
        SettingsGroup(title: "更新") {
            SettingsRow(title: "自动检查并下载新版本",
                        detail: "有新版本时在后台下载，下好后提示你重启。不点重启也行，下次退出时自动装上。") {
                // 开发版不更新：开关画成关着的、点不了
                Toggle("自动检查并下载新版本", isOn: Binding(get: { updater.isSupported && updater.automaticallyChecks },
                                                     set: { updater.setAutomaticallyChecks($0) }))
                    .toggleStyle(.square)
                    .disabled(!updater.isSupported)
            }
            Hairline()
            SettingsRow(title: statusLine, detail: updater.isSupported && !updater.isInApplications ? UpdateLocation.notInApplicationsHint : nil,
                        detailColor: Theme.warn) {
                HStack(spacing: 8) {
                    Button("检查更新") { updater.checkNow() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!updater.phase.canCheck)
                    if let ready = updater.phase.readyVersion {
                        Button("重启更新") { updater.installAndRelaunch() }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityLabel("重启并更新到 \(ready)")
                    }
                }
            }
        }
    }

    private var statusLine: String {
        updater.phase.line(currentVersion: version)
    }
}

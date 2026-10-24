// DemoStage.swift
// Ask Free
//
// 「开始」「首页」「快捷键」页和欢迎页顶上的那段示意：指针移到图表最高那根，细红框框住，
// 底部录音胶囊亮起说出问题，然后右上角弹出回答。循环播放，高度固定，不撑开布局。

import SwiftUI
#if canImport(AskFreeCore)
import AskFreeCore
#endif

struct DemoStage: View {
    var height: CGFloat = 208
    /// 右下角「按住 [键]」：nil 时写「提问键」
    var keyTitle: String? = nil
    var showsKeyHint = true

    private let period: Double = 7.5
    private let question = "这根最高的是几月？"
    private let answer = "是 7 月，大约 4.2 万人，比 6 月多了三成多。"

    var body: some View {
        Stage(height: height) {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
                scene(t)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("示意：指着图表按住提问键说出问题，回答出现在右上角")
    }

    private func scene(_ t: Double) -> some View {
        let pointerIn = ease(t, 0.2, 1.1)
        let marker = ease(t, 1.2, 1.4) * (1 - ease(t, 6.8, 7.1))
        let capsule = ease(t, 1.5, 1.8) * (1 - ease(t, 3.9, 4.2))
        let typed = Int(Double(question.count) * ease(t, 1.9, 3.5))
        let card = ease(t, 4.2, 4.6) * (1 - ease(t, 6.9, 7.3))
        let keyDown = t > 1.5 && t < 3.9

        return ZStack(alignment: .topLeading) {
            chart(marker: marker)
                .offset(x: 24, y: 18)
            // 指针：从右下移到第 5 根柱子上
            Image(systemName: "cursorarrow")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.black)
                .shadow(color: .white, radius: 0.5)
                .offset(x: 24 + 180 + (1 - pointerIn) * 140, y: 18 + 62 + (1 - pointerIn) * 70)
            capsuleView(typed: typed)
                .opacity(capsule)
                .scaleEffect(0.92 + 0.08 * capsule)
                .offset(x: 176, y: height - 58)
            answerCard
                .opacity(card)
                .offset(x: 0, y: (1 - card) * -8)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.trailing, 20)
                .padding(.top, 18)
            if showsKeyHint {
                HStack(spacing: 8) {
                    Text("按住").font(.system(size: 12)).foregroundStyle(Theme.text3)
                    Text(keyTitle ?? "提问键")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(keyDown ? Theme.selected : Theme.elevated, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.borderStrong, lineWidth: 0.5))
                        .offset(y: keyDown ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(20)
                .opacity(card > 0.5 ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 一张白卡片上的柱状图；第 5 根是最高那根，被细红框框住
    private func chart(marker: Double) -> some View {
        let values: [CGFloat] = [0.48, 0.62, 0.55, 0.7, 0.96, 0.66]
        let months = ["3 月", "4 月", "5 月", "6 月", "7 月", "8 月"]
        return VStack(alignment: .leading, spacing: 2) {
            Text("每月新用户").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(white: 0.1))
            Text("2026 年 · 千人").font(.system(size: 9.5)).foregroundStyle(Color(white: 0.55))
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(values.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i == 4 ? Color(white: 0.2) : Color(white: 0.84))
                            .frame(width: 30, height: 84 * values[i])
                            .overlay {
                                if i == 4 {
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Theme.marker, lineWidth: 1.2)
                                        .padding(-5)
                                        .opacity(marker)
                                }
                            }
                        Text(months[i]).font(.system(size: 8.5)).foregroundStyle(Color(white: 0.6))
                    }
                }
            }
            .frame(height: 104, alignment: .bottom)
            .padding(.top, 6)
        }
        .padding(12)
        .frame(width: 290, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
    }

    /// 录音胶囊：全圆角、深底、彩色音浪，说的话一个字一个字出来
    private func capsuleView(typed: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                .frame(width: 18, height: 18).background(.white.opacity(0.14), in: Circle())
            TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
                let s = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2) {
                    ForEach(0..<6, id: \.self) { i in
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.75, green: 0.45, blue: 1), Color(red: 0.35, green: 0.55, blue: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 2.5, height: 5 + 9 * abs(sin(s * 6 + Double(i) * 0.9)))
                    }
                }
                .frame(height: 16)
            }
            Text(String(question.prefix(typed)))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 118, alignment: .leading)
            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                .frame(width: 18, height: 18).background(.white.opacity(0.14), in: Circle())
        }
        .padding(.horizontal, 7)
        .frame(height: 32)
        .background(Color(white: 0.11), in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "cursorarrow.rays").font(.system(size: 9))
                Text("Ask Free").font(.system(size: 10))
            }
            .foregroundStyle(Color(white: 0.55))
            Text(question).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.1))
            Text(answer).font(.system(size: 12)).foregroundStyle(Color(white: 0.2))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(width: 236, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    /// 0 → 1 的缓动，t 在 [a, b] 之间
    private func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        guard t > a else { return 0 }
        guard t < b else { return 1 }
        let x = (t - a) / (b - a)
        return x * x * (3 - 2 * x)
    }
}

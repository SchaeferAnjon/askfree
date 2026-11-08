import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 历史页里接着聊：把这一条前面几轮的问答当上下文，打的字发给设置里的那一家模型（不看屏幕），
/// 回答一段段流进历史详情，答完存进同一条历史（同一个 thread），列表里的轮数跟着加一。
/// 用自己的 AskAI，不碰回答面板那一路的状态（面板可能同时在答别的）。
@MainActor
final class HistoryChat: ObservableObject {
    /// 正在问的这一轮：问题、已经出来的字；没答成时带报错
    struct Pending: Equatable {
        let threadID: String
        let question: String
        var at = Date()
        var answer = ""
        var note: String?
        var failure: AskFailure?
        static func == (a: Pending, b: Pending) -> Bool {
            a.threadID == b.threadID && a.question == b.question && a.answer == b.answer && a.note == b.note && (a.failure == nil) == (b.failure == nil)
        }
    }

    static let shared = HistoryChat()

    @Published private(set) var pending: Pending?
    /// 还在等回答（报错卡挂着时不算）
    var isBusy: Bool { pending != nil && pending?.failure == nil }

    private let ai = AskAI()
    /// 每问一次加一；停下、换问题以后，旧请求的回调认出自己过期了就不再动页面
    private var generation = 0
    private var images: [AskImage] = []
    private var searched = false
    /// 日志用：发出的时刻、第一段字到了没有
    private var startedAt = Date()
    private var gotFirstText = false

    private init() {
        ai.debugLog = { message in (NSApp.delegate as? AppDelegate)?.debugLog(message) }
    }

    func isPending(in threadID: String) -> Bool { pending?.threadID == threadID }

    /// 发一句：前面几轮的问答（都已答完）当上下文
    func send(_ text: String, in thread: AskHistoryThread) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return }
        generation += 1
        let generation = generation
        images = []
        searched = false
        startedAt = Date()
        gotFirstText = false
        pending = Pending(threadID: thread.id, question: question)
        let history = thread.turns.map { (question: $0.question, answer: $0.answer) }
        log("ask thread=\(thread.id.prefix(8)) turns=\(history.count) chars=\(question.count) member=\(UsageModeStore.isMember)")
        if UsageModeStore.isMember {
            if let block = MemberClient.shared.knownBlock(voice: false, log: { [weak self] in self?.log($0) }) {
                finish(generation, thread: thread.id, question: question, .failure(block))
                return
            }
            Task { @MainActor [weak self] in
                do {
                    let credentials = try await MemberClient.shared.credentials()
                    self?.run(generation, thread: thread.id, question: question, history: history, credentials: credentials, mayRecover: true)
                } catch {
                    self?.finish(generation, thread: thread.id, question: question, .failure(error))
                }
            }
        } else {
            run(generation, thread: thread.id, question: question, history: history, credentials: nil, mayRecover: false)
        }
    }

    /// 停下：已经出来的字当这一轮的回答存下；请求本身不掐（AskAI.answer 没有中途掐断的口子），回来的结果丢掉
    func stop() {
        guard let pending, pending.failure == nil else { return }
        generation += 1
        log("stopped chars=\(pending.answer.count)")
        if pending.answer.isEmpty {
            self.pending = nil
        } else {
            record(thread: pending.threadID, question: pending.question, answer: pending.answer)
        }
    }

    /// 报错卡上的按钮
    func perform(_ action: AskFailure.Action, in thread: AskHistoryThread) {
        switch action {
        case .openModels: SettingsWindowController.show(page: .models)
        case .openMembership: (NSApp.delegate as? AppDelegate)?.openMembership()
        case .openPortal: (NSApp.delegate as? AppDelegate)?.openMemberPortal()
        case .useOwnKeys: (NSApp.delegate as? AppDelegate)?.switchToOwnKeys()
        case .retry, .typeInstead:
            guard let question = pending?.question else { return }
            pending = nil
            send(question, in: thread)
        }
    }

    /// 关掉报错卡（问题已经还到输入框里时用）
    func dismissFailure() {
        if pending?.failure != nil { pending = nil }
    }

    /// 报错卡和状态里说是哪一家
    var providerName: String {
        UsageMode.current() == .member ? "会员" : AnswerPanel.providerName(AskFreeConfig.shared.string(forKey: "ask_provider") ?? "qwen")
    }

    private func run(_ generation: Int, thread: String, question: String, history: [(question: String, answer: String)],
                     credentials: MemberCredentials?, mayRecover: Bool) {
        guard generation == self.generation else { return }
        let member = credentials.map { credentials in
            AskMember(credentials: credentials, useId: MemberUse.newId(), onUse: { headers in
                DispatchQueue.main.async { MainActor.assumeIsolated { MemberClient.shared.apply(headers) } }
            })
        }
        ai.answer(question: question, history: history, screen: nil, spoken: false, member: member, onPartial: { [weak self] partial in
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                if !self.gotFirstText {
                    self.gotFirstText = true
                    self.log("first text after \(Int(Date().timeIntervalSince(self.startedAt) * 1000))ms")
                }
                self.pending?.answer = partial
            }
        }, onImages: { [weak self] images in
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.images = images
            }
        }, onRouteNote: { [weak self] note in
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.searched = true
                self.pending?.note = note
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if mayRecover, let credentials, case .failure(let e as MemberAPIError) = result, e.isBadDevice {
                    Task { @MainActor in
                        do {
                            let fresh = try await MemberClient.shared.recoverDevice(after: credentials)
                            self.run(generation, thread: thread, question: question, history: history, credentials: fresh, mayRecover: false)
                        } catch {
                            self.finish(generation, thread: thread, question: question, .failure(error))
                        }
                    }
                    return
                }
                self.finish(generation, thread: thread, question: question, result)
            }
        })
    }

    private func finish(_ generation: Int, thread: String, question: String, _ result: Result<String, Error>) {
        guard generation == self.generation else { return }
        switch result {
        case .success(let answer):
            log("answered chars=\(answer.count) images=\(images.count) searched=\(searched) total=\(Int(Date().timeIntervalSince(startedAt) * 1000))ms")
            record(thread: thread, question: question, answer: answer)
        case .failure(let error):
            if let member = error as? MemberAPIError { MemberClient.shared.noteUsageError(member) }
            let trial = MemberClient.shared.status?.trialResult
            pending?.failure = AskFailure(error: error, trialResult: trial)
            log("failed: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
        }
    }

    /// 存进同一条历史；先发「历史变了」让页面读到新的一轮，再撤掉正在问的那块，中间不闪
    private func record(thread: String, question: String, answer: String) {
        let turn = AskHistoryTurn(thread: thread, question: question, answer: answer, images: images,
                                  via: "history", searched: searched ? true : nil)
        do {
            try AskHistoryStore.shared.append(turn)
        } catch {
            log("history write failed: \(error)")
            pending?.failure = AskFailure(error: error, trialResult: nil)
            return
        }
        if !images.isEmpty {
            AskHistoryStore.shared.saveImageThumbs(images, turnID: turn.id) {
                NotificationCenter.default.post(name: .askFreeHistoryDidChange, object: nil)
            }
        }
        NotificationCenter.default.post(name: .askFreeHistoryDidChange, object: nil)
        pending = nil
    }

    private func log(_ message: String) {
        (NSApp.delegate as? AppDelegate)?.debugLog("HistoryChat: " + message)
    }
}

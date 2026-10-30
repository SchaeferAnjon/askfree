// NotesModel.swift
// Ask Free
//
// 「历史」页里看的每日图文笔记（design/daily-notes/redesign，方向 A）：哪一天、整理到哪了、勾了哪些题、Anki 底栏、提示条。
// 整理走和回答同一条通道（自带 Key，或会员后台：一次整理算一次），整理好的笔记存在历史旁边，开着就能看；
// 整理、读文件、拼 HTML 都不在主线程上做。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif
#if canImport(NotesExport)
import NotesExport
#endif

/// 笔记页上一个问题的一节：这一天里的第几个、话题、整理好的内容（还没整理好是 nil）
struct NotesEntry: Identifiable {
    var id: String { thread.id }
    let number: Int
    let thread: AskHistoryThread
    let item: DayNoteItem?
    let time: String
}

/// 一天的整理进度
enum NotesPhase: Equatable {
    /// 没在整理：笔记整份在（或者这天还没有笔记）
    case idle
    case generating
    /// 没整理完：用户停下的，或者模型少写了几个
    case stopped(byUser: Bool)
    case failed(AskFailure)
}

struct NotesDayState {
    var notes: DayNotes?
    var phase: NotesPhase = .idle
}

/// Anki 底栏的状态
enum AnkiBarState: Equatable {
    case idle
    case importing
    case opening
    /// Anki 没开着（或没装 AnkiConnect）；timedOut：点了「打开 Anki」等了一阵还是连不上
    case noAnki(timedOut: Bool)
    case result(added: Int, skipped: Int)
    case failed(String)
}

/// 页头按钮能不能点
enum NotesExportAvailability: Equatable {
    case ready
    /// 正在整理
    case generating
    /// 一个整理好的都没有
    case empty
}

struct NotesToast: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String?
    let isError: Bool
}

@MainActor
final class NotesModel: ObservableObject {
    /// 开着的那一天（yyyy-MM-dd）；nil = 在「历史」列表里
    @Published private(set) var openDay: String?
    @Published private(set) var days: [HistoryDay] = []
    @Published private(set) var states: [String: NotesDayState] = [:]
    @Published private(set) var ledger: [String: Date] = [:]
    @Published var picks: Set<String> = []
    @Published private(set) var bar: AnkiBarState = .idle
    @Published private(set) var toast: NotesToast?
    @Published private(set) var busyExport: NotesExportKind?
    @Published var pickerOpen = false
    @Published var tocCollapsed: Bool {
        didSet { UserDefaults.standard.set(tocCollapsed, forKey: Self.tocKey) }
    }
    private static let tocKey = "askfree-notes-toc-collapsed"

    private let store = DayNotesStore.shared
    private let history = AskHistoryStore.shared
    private let ai = AskAI()
    private var jobs: [String: Job] = [:]
    private var toastTask: Task<Void, Never>?
    private var openAnkiTask: Task<Void, Never>?
    private var historyObserver: NSObjectProtocol?

    private struct Job {
        var generation: Int
        var handle: AskRequestHandle?
        var use: MemberUseRef
        /// 重新整理之前的那份笔记：新的一个问题都没整理出来就失败了，页面上还是它
        var previous: DayNotes?
    }

    init() {
        tocCollapsed = UserDefaults.standard.bool(forKey: Self.tocKey)
        ai.debugLog = { message in (NSApp.delegate as? AppDelegate)?.debugLog(message) }
        ledger = store.ankiLedger()
        historyObserver = NotificationCenter.default.addObserver(forName: .askFreeHistoryDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.historyDidChange() }
        }
    }

    deinit {
        if let historyObserver { NotificationCenter.default.removeObserver(historyObserver) }
    }

    private func log(_ message: String) {
        (NSApp.delegate as? AppDelegate)?.debugLog("Notes: " + message)
    }

    // MARK: 现在这一天

    var isOpen: Bool { openDay != nil }

    var day: HistoryDay? { days.first { $0.key == openDay } }

    var state: NotesDayState { openDay.flatMap { states[$0] } ?? NotesDayState() }

    var notes: DayNotes? { state.notes }

    var phase: NotesPhase { state.phase }

    var status: DayNotesStatus? { day.flatMap { day in notes?.status(against: day) } }

    /// 这一天的每个问题（按那天问的时间），整理好的带着内容
    var entries: [NotesEntry] {
        guard let day else { return [] }
        let notes = self.notes
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return day.threads.enumerated().map { offset, thread in
            NotesEntry(number: offset + 1, thread: thread, item: notes?.item(for: thread.id),
                       time: formatter.string(from: HistoryDay.moment(of: thread, on: day.date)))
        }
    }

    /// 整理好的问题（页上有内容的那几节）
    var finished: [NotesEntry] { entries.filter { $0.item != nil } }

    /// 第几个正在整理（第一个还没有内容的）
    var currentNumber: Int? {
        guard phase == .generating else { return nil }
        return entries.first { $0.item == nil }?.number
    }

    var exportAvailability: NotesExportAvailability {
        if phase == .generating { return .generating }
        return finished.isEmpty ? .empty : .ready
    }

    /// 笔记里没有的新问题（整理之后又问的、又追问的）
    var outdated: (new: Int, followedUp: Int)? {
        guard phase == .idle || phase == .stopped(byUser: false) || phase == .stopped(byUser: true), let status, status.isOutdated else { return nil }
        return (status.newQuestions, status.followedUp)
    }

    func isInAnki(_ entry: NotesEntry) -> Bool { ledger[entry.thread.id] != nil }

    // MARK: 打开、换一天、回到历史

    /// 今天问过问题就是今天那天，没有就是 nil
    func todayKey() -> String? {
        let key = HistoryDay.key(for: Date())
        return refreshedDays().contains { $0.key == key } ? key : nil
    }

    private func refreshedDays() -> [HistoryDay] {
        let fresh = HistoryDay.group(history.threads())
        if fresh != days { days = fresh }
        return fresh
    }

    /// 打开某一天：整理好的直接看；没整理过的马上开始整理；整理了一半的停在「接着整理」
    func open(day key: String) {
        guard refreshedDays().contains(where: { $0.key == key }) else { return }
        openDay = key
        pickerOpen = false
        picks = []
        bar = .idle
        openAnkiTask?.cancel()
        ledger = store.ankiLedger()
        if states[key]?.phase == .generating { return }
        guard let cached = store.load(day: key) else {
            if states[key]?.notes == nil { start(key, resume: nil) }
            return
        }
        var state = NotesDayState(notes: cached)
        if let day = days.first(where: { $0.key == key }) {
            let status = cached.status(against: day)
            if status.done < status.total || !status.hasSummary { state.phase = .stopped(byUser: true) }
        }
        states[key] = state
    }

    func close() {
        openDay = nil
        pickerOpen = false
        picks = []
        bar = .idle
        openAnkiTask?.cancel()
    }

    private func historyDidChange() {
        guard isOpen else { return }
        let fresh = HistoryDay.group(history.threads())
        if fresh != days { days = fresh }
        // 这天的问题全删了：回到列表
        if let key = openDay, !fresh.contains(where: { $0.key == key }) { close() }
        picks = picks.filter { id in day?.threads.contains { $0.id == id } == true }
    }

    // MARK: 整理

    func regenerate() {
        guard let key = openDay else { return }
        start(key, resume: nil)
    }

    func resume() {
        guard let key = openDay, let notes = states[key]?.notes else { return }
        start(key, resume: notes)
    }

    func stop() {
        guard let key = openDay, var job = jobs[key] else { return }
        job.generation += 1   // 之后到的回调都不算数
        job.handle?.cancel()
        jobs[key] = job
        var state = states[key] ?? NotesDayState()
        state.phase = .stopped(byUser: true)
        states[key] = state
        if let notes = state.notes, !notes.items.isEmpty { try? store.save(notes) }
        log("stopped \(key) after \(state.notes?.items.count ?? 0) questions")
    }

    private func start(_ key: String, resume: DayNotes?) {
        guard let day = days.first(where: { $0.key == key }) else { return }
        jobs[key]?.handle?.cancel()
        let generation = (jobs[key]?.generation ?? 0) + 1
        // 同一天停下再接着整理，在后台的重试窗口里用同一个用量号：会员算一次
        let use = MemberUse.forRetry(resume == nil ? nil : jobs[key]?.use)
        jobs[key] = Job(generation: generation, handle: nil, use: use,
                        previous: resume == nil ? (states[key]?.notes ?? store.load(day: key)) : nil)
        var state = NotesDayState(notes: resume ?? DayNotes.begin(day), phase: .generating)
        for thread in day.threads where !(state.notes?.covered.contains { $0.thread == thread.id } ?? false) {
            state.notes?.covered.append(DayNoteCoverage(thread: thread.id, turns: thread.turns.count))
        }
        states[key] = state
        if UsageModeStore.isMember, let block = MemberClient.shared.knownBlock(voice: false, log: { [weak self] in self?.log($0) }) {
            finish(key, generation, .failure(block))
            return
        }
        log("start \(key) questions=\(day.threads.count) resume=\(resume != nil) member=\(UsageModeStore.isMember)")
        if UsageModeStore.isMember {
            Task { @MainActor [weak self] in
                do {
                    let credentials = try await MemberClient.shared.credentials()
                    self?.run(key, generation, day: day, resume: resume, credentials: credentials, mayRecover: true)
                } catch {
                    self?.finish(key, generation, .failure(error))
                }
            }
        } else {
            run(key, generation, day: day, resume: resume, credentials: nil, mayRecover: false)
        }
    }

    private func run(_ key: String, _ generation: Int, day: HistoryDay, resume: DayNotes?, credentials: MemberCredentials?, mayRecover: Bool) {
        guard jobs[key]?.generation == generation else { return }
        let member = credentials.map { credentials in
            AskMember(credentials: credentials, useId: jobs[key]?.use.id ?? MemberUse.newId(), onUse: { headers in
                DispatchQueue.main.async { MainActor.assumeIsolated { MemberClient.shared.apply(headers) } }
            })
        }
        // 接着整理从已经整理好的往下；失败后「再试一次」同样接着来
        let base = resume ?? states[key]?.notes.flatMap { $0.items.isEmpty ? nil : $0 }
        let handle = DayNotesGenerator(ai: ai).run(day: day, resume: base, member: member, onUpdate: { [weak self] notes in
            MainActor.assumeIsolated { self?.apply(key, generation, notes) }
        }, completion: { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                if mayRecover, let credentials, case .failure(let e as MemberAPIError) = result, e.isBadDevice {
                    Task { @MainActor in
                        do {
                            let fresh = try await MemberClient.shared.recoverDevice(after: credentials)
                            self.run(key, generation, day: day, resume: resume, credentials: fresh, mayRecover: false)
                        } catch {
                            self.finish(key, generation, .failure(error))
                        }
                    }
                    return
                }
                self.finish(key, generation, result)
            }
        })
        if jobs[key]?.generation == generation { jobs[key]?.handle = handle }
    }

    private func apply(_ key: String, _ generation: Int, _ notes: DayNotes) {
        guard jobs[key]?.generation == generation else { return }
        states[key]?.notes = notes
        if !notes.items.isEmpty { try? store.save(notes) }
    }

    private func finish(_ key: String, _ generation: Int, _ result: Result<DayNotes, Error>) {
        guard jobs[key]?.generation == generation else { return }
        var state = states[key] ?? NotesDayState()
        switch result {
        case .success(let notes):
            state.notes = notes
            if !notes.items.isEmpty { try? store.save(notes) }
            let complete = days.first { $0.key == key }.map { notes.status(against: $0).isComplete } ?? false
            state.phase = complete ? .idle : .stopped(byUser: false)
            log("finished \(key) items=\(notes.items.count) complete=\(complete)")
        case .failure(let error):
            if let member = error as? MemberAPIError {
                MemberClient.shared.noteUsageError(member)
                // 后台说这个号过了重试窗口：下次换新号
                if member.code == "use-expired" { jobs[key]?.use = MemberUse.forRetry(nil) }
            }
            let trial = MemberClient.shared.status?.trialResult
            state.phase = .failed(AskFailure(error: error, trialResult: trial))
            // 重新整理一个都没整理出来就失败了：页面上留着原来的笔记（文件本来也没动）
            if state.notes?.items.isEmpty ?? true, let previous = jobs[key]?.previous, !previous.items.isEmpty {
                state.notes = previous
            }
            log("failed \(key): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
        }
        states[key] = state
    }

    /// 报错卡上的按钮
    func perform(_ action: AskFailure.Action) {
        switch action {
        case .openModels: SettingsWindowController.show(page: .models)
        case .openMembership: (NSApp.delegate as? AppDelegate)?.openMembership()
        case .openPortal: (NSApp.delegate as? AppDelegate)?.openMemberPortal()
        case .useOwnKeys: (NSApp.delegate as? AppDelegate)?.switchToOwnKeys()
        case .retry: resume()
        case .typeInstead: break   // 笔记不用语音
        }
    }

    /// 提示条和报错卡里说是哪一家
    var providerName: String {
        UsageMode.current() == .member ? "会员" : AnswerPanel.providerName(AskFreeConfig.shared.string(forKey: "ask_provider") ?? "qwen")
    }

    // MARK: 提示条

    func showToast(_ title: String, detail: String? = nil, isError: Bool = false) {
        let toast = NotesToast(title: title, detail: detail, isError: isError)
        self.toast = toast
        toastTask?.cancel()
        // 成功 5 秒，出错 6 秒（会议字幕里同样）；出错的还能点 × 先关
        let seconds: Double = isError ? 6 : 5
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismissToast(toast.id)
        }
    }

    func dismissToast(_ id: UUID? = nil) {
        guard id == nil || toast?.id == id else { return }
        toast = nil
    }

    // MARK: Anki

    var pickedEntries: [NotesEntry] { finished.filter { picks.contains($0.thread.id) } }

    func togglePick(_ entry: NotesEntry) {
        guard entry.item != nil, phase != .generating else { return }
        if picks.contains(entry.thread.id) { picks.remove(entry.thread.id) } else { picks.insert(entry.thread.id) }
        if case .result = bar { bar = .idle }
        if case .failed = bar { bar = .idle }
    }

    var allPicked: Bool { !finished.isEmpty && finished.allSatisfy { picks.contains($0.thread.id) } }

    func toggleAll() {
        picks = allPicked ? [] : Set(finished.map(\.thread.id))
        if case .result = bar { bar = .idle }
    }

    func dismissBar() { bar = .idle }

    func importPicked() {
        guard let day, !pickedEntries.isEmpty, bar != .importing else { return }
        let entries = pickedEntries
        bar = .importing
        let dayKey = day.key
        let history = self.history
        log("anki import start count=\(entries.count)")
        Task { [weak self] in
            // 截图从文件读进来、拼卡片都不在主线程上做
            let cards: [AnkiCard] = await Task.detached(priority: .userInitiated) {
                entries.compactMap { entry in
                    guard let item = entry.item else { return nil }
                    let shot = entry.thread.turns[0].hasScreenshot
                        ? try? Data(contentsOf: history.screenshotURLs(turnID: entry.thread.turns[0].id).closeUp) : nil
                    return AnkiCardBuilder.card(item: item, question: entry.thread.turns[0].question, day: dayKey, time: entry.time, screenshot: shot)
                }
            }.value
            do {
                let result = try await AnkiConnect().add(cards)
                guard let self else { return }
                // 新加的和已经有了的，都是「已在 Anki」
                try? self.store.markInAnki(result.added + result.skipped)
                self.ledger = self.store.ankiLedger()
                self.picks = self.picks.subtracting(result.added + result.skipped)
                self.bar = .result(added: result.added.count, skipped: result.skipped.count)
                self.log("anki import done added=\(result.added.count) skipped=\(result.skipped.count)")
            } catch AnkiConnectError.notRunning {
                self?.bar = .noAnki(timedOut: false)
                self?.log("anki not running")
            } catch {
                self?.bar = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
                self?.log("anki import failed: \(error)")
            }
        }
    }

    /// 「打开 Anki」：把 Anki 打开，连得上了就自动接着导入（选的都还勾着）
    func openAnki() {
        bar = .opening
        openAnkiTask?.cancel()
        if AnkiConnect.configuredURL() == AnkiConnect.defaultURL {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.ankiweb.dtop") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            } else {
                // 没装 Anki：带去官网下载
                if let url = URL(string: "https://apps.ankiweb.net") { NSWorkspace.shared.open(url) }
                showToast("没找到 Anki", detail: "装好 Anki 和 AnkiConnect 插件后再试", isError: true)
                bar = .noAnki(timedOut: false)
                return
            }
        } else {
            log("anki: dev override URL set, not launching the real Anki app")
        }
        openAnkiTask = Task { [weak self] in
            for _ in 0..<60 {
                if Task.isCancelled { return }
                if (try? await AnkiConnect().version()) != nil {
                    self?.importPicked()
                    return
                }
                try? await Task.sleep(for: .seconds(1.5))
            }
            if !Task.isCancelled { self?.bar = .noAnki(timedOut: true) }
        }
    }

    func showInAnki() {
        Task { try? await AnkiConnect().browse() }
    }

    // MARK: 在历史里看

    func showInHistory(_ entry: NotesEntry) {
        HistorySelection.pending = entry.thread.id
        close()
    }

    // MARK: 导出

    private func exportSnapshot() -> (day: HistoryDay, notes: DayNotes)? {
        guard let day, let notes else { return nil }
        return (day, notes)
    }

    /// 导出用的 HTML：读截图、排公式、着色、拼页面都在后台线程
    private func buildHTML(_ snapshot: (day: HistoryDay, notes: DayNotes)) async -> String {
        let history = self.history
        return await Task.detached(priority: .userInitiated) {
            NotesPage.html(notes: snapshot.notes, day: snapshot.day, screenshot: { thread in
                guard thread.turns[0].hasScreenshot else { return nil }
                return try? Data(contentsOf: history.screenshotURLs(turnID: thread.turns[0].id).closeUp)
            })
        }.value
    }

    /// 「用浏览器打开」：写一个自带一切的 HTML，用默认浏览器打开；成功不提示，没打开才说
    func openInBrowser() {
        guard busyExport == nil, exportAvailability == .ready, let snapshot = exportSnapshot() else { return }
        busyExport = .browser
        log("export html start day=\(snapshot.day.key) questions=\(finished.count)")
        Task { [weak self] in
            guard let self else { return }
            defer { self.busyExport = nil }
            do {
                let html = await self.buildHTML(snapshot)
                let url = try await NotesFiles.writeHTML(html, name: NotesPage.fileName(day: snapshot.day.key, ext: "html"),
                                                         in: self.history.exportedNotesDirectory)
                try await NotesFiles.openInBrowser(url)
                self.log("export html opened \(url.lastPathComponent) \(html.utf8.count / 1024) KB")
            } catch {
                self.showToast("没能用浏览器打开", detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription, isError: true)
                self.log("export html failed: \(error)")
            }
        }
    }

    /// 「导出 PDF」：系统存储面板选位置，存好用默认程序打开，提示条写路径
    func exportPDF(window: NSWindow?) {
        guard busyExport == nil, exportAvailability == .ready, let snapshot = exportSnapshot() else { return }
        let name = NotesPage.fileName(day: snapshot.day.key, ext: "pdf")
        NotesFiles.chooseDestination(name: name, window: window) { [weak self] url in
            guard let self, let url else { return }   // 取消了：什么都不发生
            self.busyExport = .pdf
            self.log("export pdf start day=\(snapshot.day.key) questions=\(self.finished.count)")
            Task { [weak self] in
                guard let self else { return }
                defer { self.busyExport = nil }
                do {
                    let html = await self.buildHTML(snapshot)
                    let pages = try await NotesPDFPrinter().render(html: html, title: name.replacingOccurrences(of: ".pdf", with: ""), to: url)
                    NotesFiles.rememberDirectory(url.deletingLastPathComponent())
                    self.log("export pdf done pages=\(pages) \(url.lastPathComponent)")
                    let openError = await NotesFiles.openInDefaultApp(url)
                    let path = NotesFiles.displayPath(url)
                    self.showToast("已导出 PDF", detail: openError.map { "\(path)（没能打开：\($0)）" } ?? path)
                } catch {
                    self.showToast("没能导出 PDF", detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription, isError: true)
                    self.log("export pdf failed: \(error)")
                }
            }
        }
    }
}

enum NotesExportKind: Equatable { case browser, pdf }

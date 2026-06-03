import AppKit
import CoreGraphics
import ServiceManagement

// SleepBar —— 菜单栏常驻的「屏幕关闭时间」临时调度工具
//
// 语义:
//  · 「屏幕关闭时间」单选一个时长 → 这段时间内屏幕保持常亮(caffeinate -dis),
//    到点执行「到时间后」动作。「永不」= 一直常亮不关。再次点已选中项 = 取消(回到系统原设置)。
//  · 「到时间后」是会记住的偏好:锁定并熄屏 / 锁定、熄屏并休眠。
//
// 测试阶段:直接编译成可执行文件运行,不打包 .app / DMG。

enum EndAction: String {
    case lockOnly  = "lockOnly"   // 锁定屏幕
    case lockOff   = "lockOff"    // 锁定并熄屏
    case lockSleep = "lockSleep"  // 锁定、熄屏并休眠
}

enum Lang: String { case zh, en }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var task: Process?            // 当前 caffeinate 进程
    private var endDate: Date?            // 计时结束时间(永不/空闲为 nil)
    private var ticker: Timer?

    // activeMinutes: nil = 空闲(系统原设置);-1 = 永不(常亮);>0 = 计时分钟数
    private var activeMinutes: Int?

    private var endAction: EndAction = .lockOff
    private var customMinutes: Int = 0   // 记住的上次自定义分钟数(0 = 还没设过)
    private var lang: Lang = .zh

    // —— 定时锁屏(Timed Lock)——
    // 窗口期内,每当无键鼠输入累计达「间隔」就锁一次屏。窗口是固定计时器,锁/解锁都不重置它。
    private var tlActive = false
    private var tlInterval: Int = 0       // 锁屏间隔(分钟),也作上次值记忆
    private var tlWindowMin: Int = 0      // 窗口时长(分钟),也作上次值记忆
    private var tlWindowEnd: Date?        // 窗口绝对结束时间
    private var tlTimer: Timer?           // 自适应空闲检查(非每秒轮询)
    private var tlWindowTimer: Timer?     // 窗口到点一次性停止
    private var tlItem: NSMenuItem!
    private var launchItem: NSMenuItem!   // 「开机自启」开关(仅 .app 版本显示)

    // 预设时长(分钟),标题按语言生成
    private let presets: [Int] = [5, 10, 15, 30, 60]

    // 菜单项引用(用于更新对勾)
    private var presetItems: [(min: Int, item: NSMenuItem)] = []
    private var customItem: NSMenuItem!
    private var neverItem: NSMenuItem!
    private var lockOnlyItem: NSMenuItem!
    private var lockOffItem: NSMenuItem!
    private var lockSleepItem: NSMenuItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        if let saved = UserDefaults.standard.string(forKey: "endAction"),
           let a = EndAction(rawValue: saved) { endAction = a }
        customMinutes = UserDefaults.standard.integer(forKey: "customMinutes")
        if let s = UserDefaults.standard.string(forKey: "lang"), let l = Lang(rawValue: s) {
            lang = l
        } else {
            lang = (Locale.preferredLanguages.first?.hasPrefix("zh") ?? true) ? .zh : .en
        }

        tlInterval  = UserDefaults.standard.integer(forKey: "tlInterval")
        tlWindowMin = UserDefaults.standard.integer(forKey: "tlWindowMin")

        // 监听锁屏/解锁(事件驱动,锁屏期间零轮询)
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(screenDidLock),
                       name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dc.addObserver(self, selector: #selector(screenDidUnlock),
                       name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        refreshUI()
    }

    // MARK: - 本地化

    private func t(_ zh: String, _ en: String) -> String { lang == .zh ? zh : en }

    // 分钟 → 本地化标题:5 分钟 / 5 min,1 小时 / 1 hour
    private func durationTitle(_ minutes: Int) -> String {
        if minutes >= 60 && minutes % 60 == 0 {
            let h = minutes / 60
            return lang == .zh ? "\(h) 小时" : (h > 1 ? "\(h) hours" : "1 hour")
        }
        return lang == .zh ? "\(minutes) 分钟" : "\(minutes) min"
    }

    private func customLabel() -> String {
        guard customMinutes > 0 else { return t("自定义时长…", "Custom…") }
        return lang == .zh ? "自定义 (\(durationTitle(customMinutes)))"
                           : "Custom (\(durationTitle(customMinutes)))"
    }

    // MARK: - 菜单构建

    private func icon(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        presetItems = []

        // —— 屏幕关闭时间 ——
        menu.addItem(.sectionHeader(title: t("屏幕关闭时间", "Screen Off Timer")))
        for minutes in presets {
            let item = NSMenuItem(title: durationTitle(minutes), action: #selector(pickPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            item.image = icon("clock")
            menu.addItem(item)
            presetItems.append((minutes, item))
        }
        customItem = NSMenuItem(title: customLabel(), action: #selector(pickCustom), keyEquivalent: "")
        customItem.target = self
        customItem.image = icon("slider.horizontal.3")
        menu.addItem(customItem)

        neverItem = NSMenuItem(title: t("永不", "Never"), action: #selector(pickNever), keyEquivalent: "")
        neverItem.target = self
        neverItem.image = icon("nosign")
        menu.addItem(neverItem)

        // —— 到时间后 ——
        menu.addItem(.sectionHeader(title: t("到时间后", "When Time's Up")))
        lockOnlyItem = NSMenuItem(title: t("锁定屏幕", "Lock Screen"), action: #selector(pickLockOnly), keyEquivalent: "")
        lockOnlyItem.target = self
        lockOnlyItem.image = icon("lock")
        menu.addItem(lockOnlyItem)

        lockOffItem = NSMenuItem(title: t("锁定并熄屏", "Lock & Turn Off Display"), action: #selector(pickLockOff), keyEquivalent: "")
        lockOffItem.target = self
        lockOffItem.image = icon("lock.display")
        menu.addItem(lockOffItem)

        lockSleepItem = NSMenuItem(title: t("锁定、熄屏并休眠", "Lock, Off & Sleep"), action: #selector(pickLockSleep), keyEquivalent: "")
        lockSleepItem.target = self
        lockSleepItem.image = icon("powersleep")
        menu.addItem(lockSleepItem)

        // —— 定时锁屏 ——
        menu.addItem(.sectionHeader(title: t("定时锁屏", "Timed Lock")))
        tlItem = NSMenuItem(title: tlLabel(), action: #selector(toggleTimedLock), keyEquivalent: "")
        tlItem.target = self
        tlItem.image = icon("lock.rotation")
        menu.addItem(tlItem)

        // —— 语言 ——
        menu.addItem(.separator())
        let langItem = NSMenuItem(title: t("语言", "Language"), action: nil, keyEquivalent: "")
        langItem.image = icon("globe")
        let langMenu = NSMenu()
        let zhItem = NSMenuItem(title: "中文", action: #selector(pickLangZh), keyEquivalent: "")
        zhItem.target = self
        zhItem.state = (lang == .zh) ? .on : .off
        langMenu.addItem(zhItem)
        let enItem = NSMenuItem(title: "English", action: #selector(pickLangEn), keyEquivalent: "")
        enItem.target = self
        enItem.state = (lang == .en) ? .on : .off
        langMenu.addItem(enItem)
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // —— 开机自启(仅打包成 .app 运行时才提供;裸二进制/install.sh 版由 LaunchAgent 负责)——
        if isAppBundle {
            launchItem = NSMenuItem(title: t("开机自启", "Launch at Login"),
                                    action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            launchItem.target = self
            launchItem.image = icon("power.circle")
            menu.addItem(launchItem)
        }

        // —— 退出 ——
        let quit = NSMenuItem(title: t("退出", "Quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.image = icon("power")
        menu.addItem(quit)

        statusItem.menu = menu
        updateChecks()
    }

    func menuWillOpen(_ menu: NSMenu) { updateChecks() }

    private func updateChecks() {
        let m = activeMinutes
        for (min, item) in presetItems { item.state = (m == min) ? .on : .off }
        customItem.title = customLabel()
        customItem.state = isCustomActive() ? .on : .off
        neverItem.state = (m == -1) ? .on : .off
        lockOnlyItem.state = (endAction == .lockOnly) ? .on : .off
        lockOffItem.state = (endAction == .lockOff) ? .on : .off
        lockSleepItem.state = (endAction == .lockSleep) ? .on : .off
        if tlItem != nil {                       // 剩余时间只在打开菜单时计算,平时不刷新(省电)
            tlItem.title = tlLabel()
            tlItem.state = tlActive ? .on : .off
        }
        if launchItem != nil {
            launchItem.state = launchAtLoginEnabled() ? .on : .off
        }
    }

    // MARK: - 屏幕关闭时间动作

    @objc private func pickPreset(_ sender: NSMenuItem) {
        if activeMinutes == sender.tag { goIdle() }      // 再次点击 = 取消
        else { startTimed(minutes: sender.tag) }
    }

    @objc private func pickCustom() {
        if isCustomActive() { goIdle(); return }   // 倒计时中再点 = 取消
        promptCustom()                             // 空闲 = 弹输入框(预填上次值,回车确认)
    }

    // 当前是否正以「自定义时长」倒计时(区别于预设和永不)
    private func isCustomActive() -> Bool {
        guard let m = activeMinutes, m != -1 else { return false }
        return !presets.contains(m)
    }

    private func promptCustom() {
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        alert.messageText = t("自定义屏幕关闭时间", "Custom Screen-Off Time")
        alert.informativeText = t("输入分钟数,回车确认:", "Enter minutes, press Return:")
        alert.addButton(withTitle: t("开始", "Start"))
        alert.addButton(withTitle: t("取消", "Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        field.alignment = .center
        field.font = .systemFont(ofSize: 15)
        field.placeholderString = t("分钟,例如 45", "minutes, e.g. 45")
        if customMinutes > 0 { field.stringValue = "\(customMinutes)" }  // 预填上次的值
        let fmt = NumberFormatter()
        fmt.numberStyle = .none
        fmt.minimum = 1
        fmt.maximum = 1440
        fmt.allowsFloats = false
        field.formatter = fmt
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field   // 弹出即可直接输入
        if alert.runModal() == .alertFirstButtonReturn {
            if let mins = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), mins > 0 {
                customMinutes = mins
                UserDefaults.standard.set(mins, forKey: "customMinutes")  // 记住
                startTimed(minutes: mins)
            }
        }
    }

    @objc private func pickNever() {
        if activeMinutes == -1 { goIdle() } else { startForever() }
    }

    // MARK: - 到时间后(偏好)

    @objc private func pickLockOnly()  { setEndAction(.lockOnly) }
    @objc private func pickLockOff()   { setEndAction(.lockOff) }
    @objc private func pickLockSleep() { setEndAction(.lockSleep) }

    private func setEndAction(_ a: EndAction) {
        endAction = a
        UserDefaults.standard.set(a.rawValue, forKey: "endAction")
        updateChecks()
    }

    // MARK: - 语言

    @objc private func pickLangZh() { setLang(.zh) }
    @objc private func pickLangEn() { setLang(.en) }

    private func setLang(_ l: Lang) {
        guard l != lang else { return }
        lang = l
        UserDefaults.standard.set(l.rawValue, forKey: "lang")
        buildMenu()    // 整菜单按新语言重建
        refreshUI()
    }

    @objc private func quit() { killTask(); NSApp.terminate(nil) }

    // MARK: - caffeinate 控制

    private func startTimed(minutes: Int) {
        stopTimedLock()   // 与定时锁屏互斥(一个保持常亮,一个空闲即锁,语义相反)
        killTask()
        let seconds = minutes * 60
        let p = makeCaffeinate(args: ["-dis", "-t", "\(seconds)"]) { [weak self] proc in
            guard let self = self, self.task === proc else { return }
            self.performEndAction()         // 到点执行动作
            self.goIdle()
        }
        if launch(p) {
            task = p
            activeMinutes = minutes
            endDate = Date().addingTimeInterval(TimeInterval(seconds))
            startTicker()
        }
        refreshUI(); updateChecks()
    }

    private func startForever() {
        stopTimedLock()   // 与定时锁屏互斥
        killTask()
        let p = makeCaffeinate(args: ["-dis"]) { _ in }   // 无 -t,常亮直到取消
        if launch(p) {
            task = p
            activeMinutes = -1
            endDate = nil
        }
        stopTicker()
        refreshUI(); updateChecks()
    }

    private func goIdle() {
        killTask()
        activeMinutes = nil
        endDate = nil
        stopTicker()
        refreshUI(); updateChecks()
    }

    private func makeCaffeinate(args: [String], onEnd: @escaping (Process) -> Void) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = args
        p.terminationHandler = { proc in DispatchQueue.main.async { onEnd(proc) } }
        return p
    }

    private func launch(_ p: Process) -> Bool {
        do { try p.run(); return true } catch { return false }
    }

    // 手动结束当前进程:先摘掉 handler,避免触发到点动作
    private func killTask() {
        if let t = task { t.terminationHandler = nil; t.terminate() }
        task = nil
    }

    // MARK: - 到点动作

    private func performEndAction() {
        switch endAction {
        case .lockOnly:
            lockScreen()
        case .lockOff:
            lockScreen()
            runPmset("displaysleepnow")
        case .lockSleep:
            lockScreen()
            runPmset("sleepnow")
        }
    }

    private func lockScreen() {
        typealias LockFn = @convention(c) () -> Int32
        guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
              let sym = dlsym(h, "SACLockScreenImmediate") else { return }
        _ = unsafeBitCast(sym, to: LockFn.self)()
    }

    private func runPmset(_ arg: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = [arg]
        try? p.run()
    }

    // MARK: - 倒计时 / 图标

    // 缓存的菜单栏图标:避免倒计时时每秒重建 NSImage
    private lazy var idleIcon: NSImage?   = makeIcon("moon.zzz")
    private lazy var activeIcon: NSImage? = makeIcon("display")
    private lazy var tlIcon: NSImage?     = makeIcon("lock.rotation")
    private var iconState: Int?           // 0 空闲 / 1 常亮 / 2 定时锁屏;避免重复赋值

    private func makeIcon(_ name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: "SleepBar")?
            .withSymbolConfiguration(cfg)
    }

    private func startTicker() {
        stopTicker()
        // 每秒只刷新文字标题;tolerance 让系统合并唤醒、尽量待在低功耗态
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateTitle() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    // 完整刷新:仅在状态变化时调用(切换图标 + 更新标题)
    private func refreshUI() {
        guard let button = statusItem.button else { return }
        // 图标优先级:常亮 > 定时锁屏 > 空闲
        let state = (activeMinutes != nil) ? 1 : (tlActive ? 2 : 0)
        if iconState != state {                   // 仅在状态切换时才换图标
            switch state {
            case 1:  button.image = activeIcon
            case 2:  button.image = tlIcon
            default: button.image = idleIcon
            }
            button.imagePosition = .imageLeading
            iconState = state
        }
        updateTitle()
    }

    // 轻量刷新:倒计时每秒只更新标题字符串,无任何对象分配
    private func updateTitle() {
        guard let button = statusItem.button else { return }
        if let end = endDate {
            let left = max(0, Int(end.timeIntervalSinceNow))
            button.title = " " + format(left)
        } else if activeMinutes == -1 {
            button.title = " ∞"
        } else {
            button.title = ""
        }
    }

    private func format(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    // MARK: - 定时锁屏

    // 菜单项标题:激活时显示「每 N 分钟 · 剩 H:MM:SS」,否则显示上次设置/默认提示
    private func tlLabel() -> String {
        if tlActive, let end = tlWindowEnd {
            let left = format(max(0, Int(end.timeIntervalSinceNow)))
            return lang == .zh ? "定时锁屏:每 \(tlInterval) 分 · 剩 \(left)"
                               : "Timed Lock: every \(tlInterval)m · \(left) left"
        }
        if tlInterval > 0 && tlWindowMin > 0 {
            return lang == .zh ? "定时锁屏 (\(tlInterval) 分 / \(durationTitle(tlWindowMin)))…"
                               : "Timed Lock (\(tlInterval)m / \(durationTitle(tlWindowMin)))…"
        }
        return t("定时锁屏…", "Timed Lock…")
    }

    @objc private func toggleTimedLock() {
        if tlActive { stopTimedLock() } else { promptTimedLock() }
    }

    private func promptTimedLock() {
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "lock.rotation", accessibilityDescription: nil)
        alert.messageText = t("定时锁屏", "Timed Lock")
        alert.informativeText = t("锁屏、解锁都不会影响「持续」倒计时。",
                                  "Locking or unlocking won't affect the countdown.")
        alert.addButton(withTitle: t("开始", "Start"))
        alert.addButton(withTitle: t("取消", "Cancel"))

        // 两行「短句 + 内嵌数字」:无操作 [5] 分钟即锁屏 / 持续 [120] 分钟后自动停止
        let leadW: CGFloat = 78, fieldX: CGFloat = 84, fieldW: CGFloat = 56, tailX: CGFloat = 146
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 78))
        func text(_ s: String, x: CGFloat, y: CGFloat, w: CGFloat, _ align: NSTextAlignment) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.frame = NSRect(x: x, y: y, width: w, height: 22)
            l.alignment = align
            return l
        }
        func field(y: CGFloat, _ value: Int, _ placeholder: String) -> NSTextField {
            let f = NSTextField(frame: NSRect(x: fieldX, y: y - 1, width: fieldW, height: 24))
            f.alignment = .center
            f.placeholderString = placeholder
            if value > 0 { f.stringValue = "\(value)" }
            let fmt = NumberFormatter()
            fmt.numberStyle = .none; fmt.allowsFloats = false
            fmt.minimum = 1; fmt.maximum = 1440
            f.formatter = fmt
            return f
        }
        let intervalField = field(y: 44, tlInterval, "5")
        let windowField   = field(y: 8,  tlWindowMin, "120")
        // 第 1 行:无操作 [5] 分钟即锁屏
        container.addSubview(text(t("无操作", "Lock after"), x: 0, y: 44, w: leadW, .right))
        container.addSubview(intervalField)
        container.addSubview(text(t("分钟即锁屏", "min idle"), x: tailX, y: 44, w: 300 - tailX, .left))
        // 第 2 行:持续 [120] 分钟后自动停止
        container.addSubview(text(t("持续", "Run for"), x: 0, y: 8, w: leadW, .right))
        container.addSubview(windowField)
        container.addSubview(text(t("分钟后自动停止", "min, then stop"), x: tailX, y: 8, w: 300 - tailX, .left))
        intervalField.nextKeyView = windowField
        alert.accessoryView = container

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = intervalField
        if alert.runModal() == .alertFirstButtonReturn {
            let iv = Int(intervalField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
            let wv = Int(windowField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
            guard iv > 0, wv > 0 else { return }
            startTimedLock(interval: iv, window: max(wv, iv))  // 持续时长至少容纳一个间隔
        }
    }

    private func startTimedLock(interval: Int, window: Int) {
        stopCaffeinateIfRunning()          // 停掉 caffeinate(互斥)
        tlInterval  = interval
        tlWindowMin = window
        UserDefaults.standard.set(interval, forKey: "tlInterval")
        UserDefaults.standard.set(window, forKey: "tlWindowMin")

        tlActive = true
        tlWindowEnd = Date().addingTimeInterval(TimeInterval(window * 60))

        tlWindowTimer?.invalidate()
        let wt = Timer(timeInterval: TimeInterval(window * 60), repeats: false) { [weak self] _ in
            self?.stopTimedLock()
        }
        wt.tolerance = 5
        RunLoop.main.add(wt, forMode: .common)
        tlWindowTimer = wt

        // 刚点过菜单 = 有输入,idle≈0,先安排一个完整间隔后检查
        scheduleIdleCheck(after: TimeInterval(interval * 60))
        refreshUI(); updateChecks()
    }

    // 仅停掉 caffeinate 常亮进程(不影响定时锁屏自身状态)
    private func stopCaffeinateIfRunning() {
        if activeMinutes != nil { goIdle() }
    }

    private func stopTimedLock() {
        guard tlActive || tlTimer != nil || tlWindowTimer != nil else { return }
        tlActive = false
        tlWindowEnd = nil
        tlTimer?.invalidate(); tlTimer = nil
        tlWindowTimer?.invalidate(); tlWindowTimer = nil
        refreshUI(); updateChecks()
    }

    // 自适应调度:把下次检查安排在 seconds 之后(不超过窗口剩余),用宽松容差让系统合并唤醒
    private func scheduleIdleCheck(after seconds: TimeInterval) {
        tlTimer?.invalidate(); tlTimer = nil
        guard tlActive, let end = tlWindowEnd else { return }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 { stopTimedLock(); return }
        let delay = max(1, min(seconds, remaining))
        let tm = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.idleCheck() }
        tm.tolerance = max(2, delay * 0.1)
        RunLoop.main.add(tm, forMode: .common)
        tlTimer = tm
    }

    private func idleCheck() {
        guard tlActive, let end = tlWindowEnd else { return }
        if end.timeIntervalSinceNow <= 0 { stopTimedLock(); return }
        let idle = systemIdleSeconds()
        let intervalSec = TimeInterval(tlInterval * 60)
        if idle >= intervalSec {
            lockScreen()
            // 已锁屏:停掉检查,等 screenIsUnlocked 通知再重新武装(期间零轮询)
            tlTimer?.invalidate(); tlTimer = nil
        } else {
            scheduleIdleCheck(after: intervalSec - idle)   // 距最早可触发还差这么多
        }
    }

    // 只读查询系统空闲秒数(自上次键鼠输入),无需任何权限
    private func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }

    @objc private func screenDidLock() {
        // 进入锁定(无论自动还是手动):空闲检查无意义,停掉,等解锁
        guard tlActive else { return }
        tlTimer?.invalidate(); tlTimer = nil
    }

    @objc private func screenDidUnlock() {
        guard tlActive, let end = tlWindowEnd else { return }
        if end.timeIntervalSinceNow <= 0 { stopTimedLock(); return }
        scheduleIdleCheck(after: TimeInterval(tlInterval * 60))   // idle 刚归零,重新武装
    }

    // MARK: - 开机自启 (SMAppService;仅对 .app 包生效,无需权限)

    // 是否以 .app 包形式运行(DMG 安装),而非裸可执行文件(run.sh / install.sh)
    private var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func launchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() }
            else                      { try svc.register() }
        } catch {
            let alert = NSAlert()
            alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            alert.messageText = t("无法设置开机自启", "Couldn't set Launch at Login")
            alert.informativeText = t(
                "请将 SleepBar.app 移动到「应用程序」文件夹后再试。",
                "Move SleepBar.app to your Applications folder and try again.")
            alert.addButton(withTitle: t("好", "OK"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        updateChecks()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

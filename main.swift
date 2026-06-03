import AppKit

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
    private var iconShowsActive: Bool?    // 记录当前图标状态,避免重复赋值

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
        let active = (activeMinutes != nil)
        if iconShowsActive != active {            // 仅在空闲↔计时切换时才换图标
            button.image = active ? activeIcon : idleIcon
            button.imagePosition = .imageLeading
            iconShowsActive = active
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

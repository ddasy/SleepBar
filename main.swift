import AppKit
import CoreGraphics
import ServiceManagement

// SleepBar — a menu-bar tool for temporarily scheduling "screen off time".
//
// Semantics:
//  · "Screen Off Timer" picks one duration → the screen stays awake for that long
//    (caffeinate -dis), then the "When Time's Up" action runs. "Never" = stay awake
//    indefinitely. Clicking the selected item again = cancel (back to system defaults).
//  · "When Time's Up" is a remembered preference: lock & turn off display /
//    lock, turn off & sleep.

enum EndAction: String {
    case lockOnly  = "lockOnly"   // lock the screen
    case lockOff   = "lockOff"    // lock & turn off the display
    case lockSleep = "lockSleep"  // lock, turn off & sleep
}

enum Lang: String, CaseIterable {
    case zh, en, es, ar, pt, ja, de   // pt = Brazilian Portuguese

    // Shown in the Language submenu, always in the language itself
    var nativeName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        case .es: return "Español"
        case .ar: return "العربية"
        case .pt: return "Português (Brasil)"
        case .ja: return "日本語"
        case .de: return "Deutsch"
        }
    }

    // Best match for the system's preferred language; English if none matches
    static var systemDefault: Lang {
        let pref = Locale.preferredLanguages.first ?? "en"
        for l in Lang.allCases where pref.hasPrefix(l.rawValue) { return l }
        return .en
    }
}

// MARK: - Localization tables

// UI strings for every supported language, keyed by a stable identifier.
// %d / %@ placeholders are filled via String(format:).
private let l10n: [Lang: [String: String]] = [
    .zh: [
        "section.screenOff":   "屏幕关闭时间",
        "menu.custom":         "自定义时长…",
        "menu.customFmt":      "自定义 (%@)",
        "menu.never":          "永不",
        "section.endAction":   "到时间后",
        "menu.lockOnly":       "锁定屏幕",
        "menu.lockOff":        "锁定并熄屏",
        "menu.lockSleep":      "锁定、熄屏并休眠",
        "section.timedLock":   "定时锁屏",
        "menu.language":       "语言",
        "menu.launchAtLogin":  "开机自启",
        "menu.quit":           "退出",
        "unit.min":            "%d 分钟",
        "unit.hour":           "%d 小时",
        "unit.hours":          "%d 小时",
        "custom.title":        "自定义屏幕关闭时间",
        "custom.prompt":       "输入分钟数,回车确认:",
        "custom.placeholder":  "分钟,例如 45",
        "btn.start":           "开始",
        "btn.cancel":          "取消",
        "btn.ok":              "好",
        "tl.ellipsis":         "定时锁屏…",
        "tl.activeFmt":        "定时锁屏:每 %d 分 · 剩 %@",
        "tl.savedFmt":         "定时锁屏 (%d 分 / %@)…",
        "tl.note":             "锁屏、解锁都不会影响「持续」倒计时。",
        "tl.lockAfter":        "无操作",
        "tl.minIdle":          "分钟即锁屏",
        "tl.runFor":           "持续",
        "tl.thenStop":         "分钟后自动停止",
        "login.errTitle":      "无法设置开机自启",
        "login.errMsg":        "请将 SleepBar.app 移动到「应用程序」文件夹后再试。",
    ],
    .en: [
        "section.screenOff":   "Screen Off Timer",
        "menu.custom":         "Custom…",
        "menu.customFmt":      "Custom (%@)",
        "menu.never":          "Never",
        "section.endAction":   "When Time's Up",
        "menu.lockOnly":       "Lock Screen",
        "menu.lockOff":        "Lock & Turn Off Display",
        "menu.lockSleep":      "Lock, Off & Sleep",
        "section.timedLock":   "Timed Lock",
        "menu.language":       "Language",
        "menu.launchAtLogin":  "Launch at Login",
        "menu.quit":           "Quit",
        "unit.min":            "%d min",
        "unit.hour":           "%d hour",
        "unit.hours":          "%d hours",
        "custom.title":        "Custom Screen-Off Time",
        "custom.prompt":       "Enter minutes, press Return:",
        "custom.placeholder":  "minutes, e.g. 45",
        "btn.start":           "Start",
        "btn.cancel":          "Cancel",
        "btn.ok":              "OK",
        "tl.ellipsis":         "Timed Lock…",
        "tl.activeFmt":        "Timed Lock: every %dm · %@ left",
        "tl.savedFmt":         "Timed Lock (%dm / %@)…",
        "tl.note":             "Locking or unlocking won't affect the countdown.",
        "tl.lockAfter":        "Lock after",
        "tl.minIdle":          "min idle",
        "tl.runFor":           "Run for",
        "tl.thenStop":         "min, then stop",
        "login.errTitle":      "Couldn't set Launch at Login",
        "login.errMsg":        "Move SleepBar.app to your Applications folder and try again.",
    ],
    .es: [
        "section.screenOff":   "Temporizador de pantalla",
        "menu.custom":         "Personalizado…",
        "menu.customFmt":      "Personalizado (%@)",
        "menu.never":          "Nunca",
        "section.endAction":   "Al terminar",
        "menu.lockOnly":       "Bloquear pantalla",
        "menu.lockOff":        "Bloquear y apagar pantalla",
        "menu.lockSleep":      "Bloquear, apagar y suspender",
        "section.timedLock":   "Bloqueo programado",
        "menu.language":       "Idioma",
        "menu.launchAtLogin":  "Abrir al iniciar sesión",
        "menu.quit":           "Salir",
        "unit.min":            "%d min",
        "unit.hour":           "%d hora",
        "unit.hours":          "%d horas",
        "custom.title":        "Tiempo personalizado",
        "custom.prompt":       "Introduce los minutos y pulsa Intro:",
        "custom.placeholder":  "minutos, p. ej. 45",
        "btn.start":           "Iniciar",
        "btn.cancel":          "Cancelar",
        "btn.ok":              "Aceptar",
        "tl.ellipsis":         "Bloqueo programado…",
        "tl.activeFmt":        "Bloqueo: cada %d min · quedan %@",
        "tl.savedFmt":         "Bloqueo programado (%d min / %@)…",
        "tl.note":             "Bloquear o desbloquear no afecta a la cuenta atrás.",
        "tl.lockAfter":        "Bloquear tras",
        "tl.minIdle":          "min inactivo",
        "tl.runFor":           "Durante",
        "tl.thenStop":         "min, luego parar",
        "login.errTitle":      "No se pudo configurar el inicio de sesión",
        "login.errMsg":        "Mueve SleepBar.app a la carpeta Aplicaciones e inténtalo de nuevo.",
    ],
    .ar: [
        "section.screenOff":   "مؤقّت إطفاء الشاشة",
        "menu.custom":         "مخصّص…",
        "menu.customFmt":      "مخصّص (%@)",
        "menu.never":          "أبدًا",
        "section.endAction":   "عند انتهاء الوقت",
        "menu.lockOnly":       "قفل الشاشة",
        "menu.lockOff":        "قفل وإطفاء الشاشة",
        "menu.lockSleep":      "قفل وإطفاء وسبات",
        "section.timedLock":   "قفل دوري",
        "menu.language":       "اللغة",
        "menu.launchAtLogin":  "الفتح عند تسجيل الدخول",
        "menu.quit":           "إنهاء",
        "unit.min":            "%d دقيقة",
        "unit.hour":           "%d ساعة",
        "unit.hours":          "%d ساعات",
        "custom.title":        "وقت مخصّص لإطفاء الشاشة",
        "custom.prompt":       "أدخل عدد الدقائق ثم اضغط Return:",
        "custom.placeholder":  "دقائق، مثل 45",
        "btn.start":           "بدء",
        "btn.cancel":          "إلغاء",
        "btn.ok":              "حسنًا",
        "tl.ellipsis":         "قفل دوري…",
        "tl.activeFmt":        "قفل دوري: كل %dد · متبقٍ %@",
        "tl.savedFmt":         "قفل دوري (%d دقيقة / %@)…",
        "tl.note":             "القفل أو فتح القفل لا يؤثّر على العدّاد.",
        "tl.lockAfter":        "القفل بعد",
        "tl.minIdle":          "دقيقة خمول",
        "tl.runFor":           "التشغيل لمدة",
        "tl.thenStop":         "دقيقة ثم التوقّف",
        "login.errTitle":      "تعذّر تفعيل الفتح عند تسجيل الدخول",
        "login.errMsg":        "انقل SleepBar.app إلى مجلد التطبيقات وحاول مجددًا.",
    ],
    .pt: [
        "section.screenOff":   "Temporizador de tela",
        "menu.custom":         "Personalizado…",
        "menu.customFmt":      "Personalizado (%@)",
        "menu.never":          "Nunca",
        "section.endAction":   "Ao terminar",
        "menu.lockOnly":       "Bloquear tela",
        "menu.lockOff":        "Bloquear e desligar a tela",
        "menu.lockSleep":      "Bloquear, desligar e suspender",
        "section.timedLock":   "Bloqueio programado",
        "menu.language":       "Idioma",
        "menu.launchAtLogin":  "Abrir ao fazer login",
        "menu.quit":           "Encerrar",
        "unit.min":            "%d min",
        "unit.hour":           "%d hora",
        "unit.hours":          "%d horas",
        "custom.title":        "Tempo personalizado",
        "custom.prompt":       "Digite os minutos e pressione Return:",
        "custom.placeholder":  "minutos, ex.: 45",
        "btn.start":           "Iniciar",
        "btn.cancel":          "Cancelar",
        "btn.ok":              "OK",
        "tl.ellipsis":         "Bloqueio programado…",
        "tl.activeFmt":        "Bloqueio: a cada %d min · faltam %@",
        "tl.savedFmt":         "Bloqueio programado (%d min / %@)…",
        "tl.note":             "Bloquear ou desbloquear não afeta a contagem.",
        "tl.lockAfter":        "Bloquear após",
        "tl.minIdle":          "min inativo",
        "tl.runFor":           "Durante",
        "tl.thenStop":         "min, depois parar",
        "login.errTitle":      "Não foi possível ativar a abertura ao fazer login",
        "login.errMsg":        "Mova o SleepBar.app para a pasta Aplicativos e tente novamente.",
    ],
    .ja: [
        "section.screenOff":   "画面オフタイマー",
        "menu.custom":         "カスタム…",
        "menu.customFmt":      "カスタム (%@)",
        "menu.never":          "オフにしない",
        "section.endAction":   "時間になったら",
        "menu.lockOnly":       "画面をロック",
        "menu.lockOff":        "ロックして画面をオフ",
        "menu.lockSleep":      "ロック・オフしてスリープ",
        "section.timedLock":   "定期ロック",
        "menu.language":       "言語",
        "menu.launchAtLogin":  "ログイン時に起動",
        "menu.quit":           "終了",
        "unit.min":            "%d 分",
        "unit.hour":           "%d 時間",
        "unit.hours":          "%d 時間",
        "custom.title":        "カスタム画面オフ時間",
        "custom.prompt":       "分数を入力し、Return キーを押してください:",
        "custom.placeholder":  "分(例: 45)",
        "btn.start":           "開始",
        "btn.cancel":          "キャンセル",
        "btn.ok":              "OK",
        "tl.ellipsis":         "定期ロック…",
        "tl.activeFmt":        "定期ロック:%d 分ごと · 残り %@",
        "tl.savedFmt":         "定期ロック (%d 分 / %@)…",
        "tl.note":             "ロック/ロック解除してもカウントダウンは止まりません。",
        "tl.lockAfter":        "無操作",
        "tl.minIdle":          "分でロック",
        "tl.runFor":           "継続",
        "tl.thenStop":         "分後に自動停止",
        "login.errTitle":      "ログイン時の起動を設定できません",
        "login.errMsg":        "SleepBar.app を「アプリケーション」フォルダに移動してからもう一度お試しください。",
    ],
    .de: [
        "section.screenOff":   "Bildschirm-Timer",
        "menu.custom":         "Eigene Dauer…",
        "menu.customFmt":      "Eigene Dauer (%@)",
        "menu.never":          "Nie",
        "section.endAction":   "Nach Ablauf",
        "menu.lockOnly":       "Bildschirm sperren",
        "menu.lockOff":        "Sperren und Bildschirm ausschalten",
        "menu.lockSleep":      "Sperren, ausschalten & Ruhezustand",
        "section.timedLock":   "Zeitgesteuerte Sperre",
        "menu.language":       "Sprache",
        "menu.launchAtLogin":  "Bei der Anmeldung öffnen",
        "menu.quit":           "Beenden",
        "unit.min":            "%d Min.",
        "unit.hour":           "%d Stunde",
        "unit.hours":          "%d Stunden",
        "custom.title":        "Eigene Ausschaltzeit",
        "custom.prompt":       "Minuten eingeben, Eingabetaste drücken:",
        "custom.placeholder":  "Minuten, z. B. 45",
        "btn.start":           "Starten",
        "btn.cancel":          "Abbrechen",
        "btn.ok":              "OK",
        "tl.ellipsis":         "Zeitgesteuerte Sperre…",
        "tl.activeFmt":        "Sperre: alle %d Min. · noch %@",
        "tl.savedFmt":         "Zeitgesteuerte Sperre (%d Min. / %@)…",
        "tl.note":             "Sperren oder Entsperren beeinflusst den Countdown nicht.",
        "tl.lockAfter":        "Sperren nach",
        "tl.minIdle":          "Min. Inaktivität",
        "tl.runFor":           "Dauer",
        "tl.thenStop":         "Min., dann stoppen",
        "login.errTitle":      "„Bei der Anmeldung öffnen“ konnte nicht aktiviert werden",
        "login.errMsg":        "Verschiebe SleepBar.app in den Ordner „Programme“ und versuche es erneut.",
    ],
]

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var task: Process?            // current caffeinate process
    private var endDate: Date?            // countdown end time (nil for never/idle)
    private var ticker: Timer?

    // activeMinutes: nil = idle (system defaults); -1 = never (always awake); >0 = countdown minutes
    private var activeMinutes: Int?

    private var endAction: EndAction = .lockOff
    private var customMinutes: Int = 0   // last custom duration in minutes (0 = never set)
    private var lang: Lang = .en

    // —— Timed Lock ——
    // Within the window, lock the screen every time idle input reaches "interval".
    // The window is a fixed countdown; locking/unlocking never resets it.
    private var tlActive = false
    private var tlInterval: Int = 0       // lock interval (minutes), also remembers the last value
    private var tlWindowMin: Int = 0      // window length (minutes), also remembers the last value
    private var tlWindowEnd: Date?        // absolute end time of the window
    private var tlTimer: Timer?           // adaptive idle check (not a per-second poll)
    private var tlWindowTimer: Timer?     // one-shot stop when the window ends
    private var tlItem: NSMenuItem!
    private var launchItem: NSMenuItem!   // "Launch at Login" toggle (.app builds only)

    // Preset durations (minutes); titles are generated per language
    private let presets: [Int] = [5, 10, 15, 30, 60]

    // Menu item references (for updating checkmarks)
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
            lang = Lang.systemDefault
        }

        tlInterval  = UserDefaults.standard.integer(forKey: "tlInterval")
        tlWindowMin = UserDefaults.standard.integer(forKey: "tlWindowMin")

        // Observe lock/unlock (event-driven; zero polling while locked)
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(screenDidLock),
                       name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dc.addObserver(self, selector: #selector(screenDidUnlock),
                       name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        // install.sh passes --register-login on the first launch after installing:
        // register as a Login Item (SMAppService; uncheck anytime via "Launch at Login")
        if CommandLine.arguments.contains("--register-login"), isAppBundle,
           #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        refreshUI()
    }

    // MARK: - Localization

    private func t(_ key: String) -> String {
        l10n[lang]?[key] ?? l10n[.en]?[key] ?? key
    }

    // Minutes → localized title: "5 min" / "1 hour" (or their localized equivalents)
    private func durationTitle(_ minutes: Int) -> String {
        if minutes >= 60 && minutes % 60 == 0 {
            let h = minutes / 60
            return String(format: t(h == 1 ? "unit.hour" : "unit.hours"), h)
        }
        return String(format: t("unit.min"), minutes)
    }

    private func customLabel() -> String {
        guard customMinutes > 0 else { return t("menu.custom") }
        return String(format: t("menu.customFmt"), durationTitle(customMinutes))
    }

    // MARK: - Menu building

    private func icon(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        presetItems = []

        // —— Screen Off Timer ——
        menu.addItem(.sectionHeader(title: t("section.screenOff")))
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

        neverItem = NSMenuItem(title: t("menu.never"), action: #selector(pickNever), keyEquivalent: "")
        neverItem.target = self
        neverItem.image = icon("nosign")
        menu.addItem(neverItem)

        // —— When Time's Up ——
        menu.addItem(.sectionHeader(title: t("section.endAction")))
        lockOnlyItem = NSMenuItem(title: t("menu.lockOnly"), action: #selector(pickLockOnly), keyEquivalent: "")
        lockOnlyItem.target = self
        lockOnlyItem.image = icon("lock")
        menu.addItem(lockOnlyItem)

        lockOffItem = NSMenuItem(title: t("menu.lockOff"), action: #selector(pickLockOff), keyEquivalent: "")
        lockOffItem.target = self
        lockOffItem.image = icon("lock.display")
        menu.addItem(lockOffItem)

        lockSleepItem = NSMenuItem(title: t("menu.lockSleep"), action: #selector(pickLockSleep), keyEquivalent: "")
        lockSleepItem.target = self
        lockSleepItem.image = icon("powersleep")
        menu.addItem(lockSleepItem)

        // —— Timed Lock ——
        menu.addItem(.sectionHeader(title: t("section.timedLock")))
        tlItem = NSMenuItem(title: tlLabel(), action: #selector(toggleTimedLock), keyEquivalent: "")
        tlItem.target = self
        tlItem.image = icon("lock.rotation")
        menu.addItem(tlItem)

        // —— Language ——
        menu.addItem(.separator())
        let langItem = NSMenuItem(title: t("menu.language"), action: nil, keyEquivalent: "")
        langItem.image = icon("globe")
        let langMenu = NSMenu()
        for l in Lang.allCases {
            let item = NSMenuItem(title: l.nativeName, action: #selector(pickLang(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = l.rawValue
            item.state = (lang == l) ? .on : .off
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // —— Launch at Login (shown when running as .app; both install.sh and the DMG
        //    install an .app — only run.sh's bare-binary dev mode hides it) ——
        if isAppBundle {
            launchItem = NSMenuItem(title: t("menu.launchAtLogin"),
                                    action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            launchItem.target = self
            launchItem.image = icon("power.circle")
            menu.addItem(launchItem)
        }

        // —— Quit ——
        let quit = NSMenuItem(title: t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
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
        if tlItem != nil {                       // remaining time is computed only when the menu opens (saves power)
            tlItem.title = tlLabel()
            tlItem.state = tlActive ? .on : .off
        }
        if launchItem != nil {
            launchItem.state = launchAtLoginEnabled() ? .on : .off
        }
    }

    // MARK: - Screen-off timer actions

    @objc private func pickPreset(_ sender: NSMenuItem) {
        if activeMinutes == sender.tag { goIdle() }      // clicking again = cancel
        else { startTimed(minutes: sender.tag) }
    }

    @objc private func pickCustom() {
        if isCustomActive() { goIdle(); return }   // clicking mid-countdown = cancel
        promptCustom()                             // idle = show input dialog (pre-filled, Return confirms)
    }

    // Whether a "custom duration" countdown is running (as opposed to a preset or never)
    private func isCustomActive() -> Bool {
        guard let m = activeMinutes, m != -1 else { return false }
        return !presets.contains(m)
    }

    private func promptCustom() {
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        alert.messageText = t("custom.title")
        alert.informativeText = t("custom.prompt")
        alert.addButton(withTitle: t("btn.start"))
        alert.addButton(withTitle: t("btn.cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        field.alignment = .center
        field.font = .systemFont(ofSize: 15)
        field.placeholderString = t("custom.placeholder")
        if customMinutes > 0 { field.stringValue = "\(customMinutes)" }  // pre-fill the last value
        let fmt = NumberFormatter()
        fmt.numberStyle = .none
        fmt.minimum = 1
        fmt.maximum = 1440
        fmt.allowsFloats = false
        field.formatter = fmt
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field   // ready for typing as soon as it appears
        if alert.runModal() == .alertFirstButtonReturn {
            if let mins = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), mins > 0 {
                customMinutes = mins
                UserDefaults.standard.set(mins, forKey: "customMinutes")  // remember
                startTimed(minutes: mins)
            }
        }
    }

    @objc private func pickNever() {
        if activeMinutes == -1 { goIdle() } else { startForever() }
    }

    // MARK: - When Time's Up (preference)

    @objc private func pickLockOnly()  { setEndAction(.lockOnly) }
    @objc private func pickLockOff()   { setEndAction(.lockOff) }
    @objc private func pickLockSleep() { setEndAction(.lockSleep) }

    private func setEndAction(_ a: EndAction) {
        endAction = a
        UserDefaults.standard.set(a.rawValue, forKey: "endAction")
        updateChecks()
    }

    // MARK: - Language

    @objc private func pickLang(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let l = Lang(rawValue: raw) else { return }
        setLang(l)
    }

    private func setLang(_ l: Lang) {
        guard l != lang else { return }
        lang = l
        UserDefaults.standard.set(l.rawValue, forKey: "lang")
        buildMenu()    // rebuild the whole menu in the new language
        refreshUI()
    }

    @objc private func quit() { killTask(); NSApp.terminate(nil) }

    // MARK: - caffeinate control

    private func startTimed(minutes: Int) {
        stopTimedLock()   // mutually exclusive with Timed Lock (one keeps awake, the other locks on idle)
        killTask()
        let seconds = minutes * 60
        let p = makeCaffeinate(args: ["-dis", "-t", "\(seconds)"]) { [weak self] proc in
            guard let self = self, self.task === proc else { return }
            self.performEndAction()         // run the action when time is up
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
        stopTimedLock()   // mutually exclusive with Timed Lock
        killTask()
        let p = makeCaffeinate(args: ["-dis"]) { _ in }   // no -t: stay awake until cancelled
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

    // End the current process manually: detach the handler first so the end action doesn't fire
    private func killTask() {
        if let t = task { t.terminationHandler = nil; t.terminate() }
        task = nil
    }

    // MARK: - End-of-countdown actions

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

    // MARK: - Countdown / icon

    // Cached menu-bar icons: avoid rebuilding NSImage every second during a countdown
    private lazy var idleIcon: NSImage?   = makeIcon("moon.zzz")
    private lazy var activeIcon: NSImage? = makeIcon("display")
    private lazy var tlIcon: NSImage?     = makeIcon("lock.rotation")
    private var iconState: Int?           // 0 idle / 1 awake / 2 timed lock; avoids redundant assignment

    private func makeIcon(_ name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: "SleepBar")?
            .withSymbolConfiguration(cfg)
    }

    private func startTicker() {
        stopTicker()
        // Refresh only the text title once per second; tolerance lets the system
        // coalesce wake-ups and stay in low-power states
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateTitle() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    // Full refresh: called only on state changes (swap icon + update title)
    private func refreshUI() {
        guard let button = statusItem.button else { return }
        // Icon priority: awake > timed lock > idle
        let state = (activeMinutes != nil) ? 1 : (tlActive ? 2 : 0)
        if iconState != state {                   // swap the icon only when the state changes
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

    // Light refresh: during a countdown only the title string updates each second, zero allocations
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

    // MARK: - Timed Lock

    // Menu item title: when active, "every N min · H:MM:SS left"; otherwise the last settings / default hint
    private func tlLabel() -> String {
        if tlActive, let end = tlWindowEnd {
            let left = format(max(0, Int(end.timeIntervalSinceNow)))
            return String(format: t("tl.activeFmt"), tlInterval, left)
        }
        if tlInterval > 0 && tlWindowMin > 0 {
            return String(format: t("tl.savedFmt"), tlInterval, durationTitle(tlWindowMin))
        }
        return t("tl.ellipsis")
    }

    @objc private func toggleTimedLock() {
        if tlActive { stopTimedLock() } else { promptTimedLock() }
    }

    private func promptTimedLock() {
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "lock.rotation", accessibilityDescription: nil)
        alert.messageText = t("section.timedLock")
        alert.informativeText = t("tl.note")
        alert.addButton(withTitle: t("btn.start"))
        alert.addButton(withTitle: t("btn.cancel"))

        // Two rows of "short sentence + inline number":
        // "Lock after [5] min idle" / "Run for [120] min, then stop"
        let leadW: CGFloat = 100, fieldX: CGFloat = 106, fieldW: CGFloat = 56, tailX: CGFloat = 168
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 78))
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
        // Row 1: lock after [5] min idle
        container.addSubview(text(t("tl.lockAfter"), x: 0, y: 44, w: leadW, .right))
        container.addSubview(intervalField)
        container.addSubview(text(t("tl.minIdle"), x: tailX, y: 44, w: 330 - tailX, .left))
        // Row 2: run for [120] min, then stop
        container.addSubview(text(t("tl.runFor"), x: 0, y: 8, w: leadW, .right))
        container.addSubview(windowField)
        container.addSubview(text(t("tl.thenStop"), x: tailX, y: 8, w: 330 - tailX, .left))
        intervalField.nextKeyView = windowField
        alert.accessoryView = container

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = intervalField
        if alert.runModal() == .alertFirstButtonReturn {
            let iv = Int(intervalField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
            let wv = Int(windowField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
            guard iv > 0, wv > 0 else { return }
            startTimedLock(interval: iv, window: max(wv, iv))  // window must fit at least one interval
        }
    }

    private func startTimedLock(interval: Int, window: Int) {
        stopCaffeinateIfRunning()          // stop caffeinate (mutually exclusive)
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

        // The menu was just clicked = there was input, idle ≈ 0,
        // so schedule the first check a full interval from now
        scheduleIdleCheck(after: TimeInterval(interval * 60))
        refreshUI(); updateChecks()
    }

    // Stop only the caffeinate keep-awake process (doesn't touch Timed Lock state)
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

    // Adaptive scheduling: run the next check `seconds` from now (capped at the window's
    // remaining time), with a loose tolerance so the system can coalesce wake-ups
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
            // Screen is locked: stop checking and wait for screenIsUnlocked to
            // re-arm (zero polling in the meantime)
            tlTimer?.invalidate(); tlTimer = nil
        } else {
            scheduleIdleCheck(after: intervalSec - idle)   // time left until the earliest possible trigger
        }
    }

    // Read-only query of system idle seconds (since the last keyboard/mouse input); needs no permissions
    private func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }

    @objc private func screenDidLock() {
        // Locked (whether automatic or manual): idle checks are pointless, stop and wait for unlock
        guard tlActive else { return }
        tlTimer?.invalidate(); tlTimer = nil
    }

    @objc private func screenDidUnlock() {
        guard tlActive, let end = tlWindowEnd else { return }
        if end.timeIntervalSinceNow <= 0 { stopTimedLock(); return }
        scheduleIdleCheck(after: TimeInterval(tlInterval * 60))   // idle just reset to zero, re-arm
    }

    // MARK: - Launch at Login (SMAppService; .app bundles only, no permissions needed)

    // Whether we're running as an .app bundle (install.sh / DMG) rather than
    // a bare executable (run.sh dev mode)
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
            alert.messageText = t("login.errTitle")
            alert.informativeText = t("login.errMsg")
            alert.addButton(withTitle: t("btn.ok"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        updateChecks()
    }
}

// Called by uninstall.sh: just unregister the Login Item and exit without
// starting the UI (must run before the .app is deleted)
if CommandLine.arguments.contains("--unregister-login") {
    if #available(macOS 13.0, *) { try? SMAppService.mainApp.unregister() }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

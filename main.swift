import AppKit
import CoreGraphics
import IOKit.ps
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
    case lockOnly        = "lockOnly"        // lock the screen
    case lockOff         = "lockOff"         // lock & turn off the display
    case lockSleep       = "lockSleep"       // lock, turn off & sleep
    case lockOffNoSleep  = "lockOffNoSleep"  // lock & turn off the display but keep the system awake
    case screenOff       = "screenOff"       // dim the built-in display to 0 (no lock), keep awake, auto-restore on return
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
        "menu.now":            "立即",
        "menu.custom":         "自定义时长…",
        "menu.customFmt":      "自定义 (%@)",
        "menu.never":          "永不",
        "section.endAction":   "到时间后",
        "menu.lockOnly":       "锁定屏幕",
        "menu.lockOff":        "锁定并息屏",
        "menu.lockSleep":      "锁定、息屏并休眠",
        "menu.lockOffNoSleep": "锁定、息屏且不休眠",
        "menu.screenOff":      "息屏",
        "section.timedLock":   "定时锁屏",
        "menu.language":       "语言",
        "menu.keepAwake":      "不休眠",
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
        "tl.until":            "到",
        "tl.untilStop":        "自动停止",
        "tl.savedUntilFmt":    "定时锁屏 (%d 分 / 到 %@)…",
        "tl.pickOne":          "「持续」和「到点」二选一,填一个另一个会自动清空。",
        "tl.badTime":          "请输入 24 小时制时间,例如 23:30。",
        "login.errTitle":      "无法设置开机自启",
        "login.errMsg":        "请将 SleepBar.app 移动到「应用程序」文件夹后再试。",
        "section.sysOff":      "系统关屏",
        "sys.offAfterFmt":     "关屏时间: %@",
        "sys.autoOff":         "提前 1 分钟自动息屏",
        "sys.writeFailed":     "屏幕关闭时间未能修改",
        "update.availableFmt": "有新版本 %@ · 点击下载",
    ],
    .en: [
        "section.screenOff":   "Screen Off Timer",
        "menu.now":            "Now",
        "menu.custom":         "Custom…",
        "menu.customFmt":      "Custom (%@)",
        "menu.never":          "Never",
        "section.endAction":   "When Time's Up",
        "menu.lockOnly":       "Lock Screen",
        "menu.lockOff":        "Lock & Turn Off Display",
        "menu.lockSleep":      "Lock, Off & Sleep",
        "menu.lockOffNoSleep": "Lock, Off & Stay Awake",
        "menu.screenOff":      "Screen Off",
        "section.timedLock":   "Timed Lock",
        "menu.language":       "Language",
        "menu.keepAwake":      "Keep Awake",
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
        "tl.until":            "Until",
        "tl.untilStop":        "then stop",
        "tl.savedUntilFmt":    "Timed Lock (%dm / until %@)…",
        "tl.pickOne":          "\u{201C}Run for\u{201D} and \u{201C}Until\u{201D} are either/or \u{2014} filling one clears the other.",
        "tl.badTime":          "Enter a 24-hour time, e.g. 23:30.",
        "login.errTitle":      "Couldn't set Launch at Login",
        "login.errMsg":        "Move SleepBar.app to your Applications folder and try again.",
        "section.sysOff":      "System Display Off",
        "sys.offAfterFmt":     "Turn Off After: %@",
        "sys.autoOff":         "Auto Screen Off 1 Min Early",
        "sys.writeFailed":     "Couldn't change the display-off time",
        "update.availableFmt": "Version %@ available · click to download",
    ],
    .es: [
        "section.screenOff":   "Temporizador de pantalla",
        "menu.now":            "Ahora",
        "menu.custom":         "Personalizado…",
        "menu.customFmt":      "Personalizado (%@)",
        "menu.never":          "Nunca",
        "section.endAction":   "Al terminar",
        "menu.lockOnly":       "Bloquear pantalla",
        "menu.lockOff":        "Bloquear y apagar pantalla",
        "menu.lockSleep":      "Bloquear, apagar y suspender",
        "menu.lockOffNoSleep": "Bloquear, apagar, sin suspender",
        "menu.screenOff":      "Apagar pantalla",
        "section.timedLock":   "Bloqueo programado",
        "menu.language":       "Idioma",
        "menu.keepAwake":      "Mantener activo",
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
        "tl.until":            "Hasta las",
        "tl.untilStop":        "detener",
        "tl.savedUntilFmt":    "Bloqueo programado (%d min / hasta %@)…",
        "tl.pickOne":          "«Durante» y «Hasta» son excluyentes: al rellenar uno se borra el otro.",
        "tl.badTime":          "Introduce una hora de 24 h, p. ej. 23:30.",
        "login.errTitle":      "No se pudo configurar el inicio de sesión",
        "login.errMsg":        "Mueve SleepBar.app a la carpeta Aplicaciones e inténtalo de nuevo.",
        "section.sysOff":      "Apagado del sistema",
        "sys.offAfterFmt":     "Apagar tras: %@",
        "sys.autoOff":         "Apagar pantalla 1 min antes",
        "sys.writeFailed":     "No se pudo cambiar el tiempo de apagado",
        "update.availableFmt": "Versión %@ disponible · haz clic para descargar",
    ],
    .ar: [
        "section.screenOff":   "مؤقّت إطفاء الشاشة",
        "menu.now":            "الآن",
        "menu.custom":         "مخصّص…",
        "menu.customFmt":      "مخصّص (%@)",
        "menu.never":          "أبدًا",
        "section.endAction":   "عند انتهاء الوقت",
        "menu.lockOnly":       "قفل الشاشة",
        "menu.lockOff":        "قفل وإطفاء الشاشة",
        "menu.lockSleep":      "قفل وإطفاء وسبات",
        "menu.lockOffNoSleep": "قفل وإطفاء دون سبات",
        "menu.screenOff":      "إطفاء الشاشة",
        "section.timedLock":   "قفل دوري",
        "menu.language":       "اللغة",
        "menu.keepAwake":      "منع السكون",
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
        "tl.until":            "حتى",
        "tl.untilStop":        "ثم التوقّف",
        "tl.savedUntilFmt":    "قفل دوري (%d دقيقة / حتى %@)…",
        "tl.pickOne":          "«التشغيل لمدة» و«حتى» بديلان: تعبئة أحدهما تمسح الآخر.",
        "tl.badTime":          "أدخل وقتًا بنظام 24 ساعة، مثل 23:30.",
        "login.errTitle":      "تعذّر تفعيل الفتح عند تسجيل الدخول",
        "login.errMsg":        "انقل SleepBar.app إلى مجلد التطبيقات وحاول مجددًا.",
        "section.sysOff":      "إطفاء شاشة النظام",
        "sys.offAfterFmt":     "الإطفاء بعد: %@",
        "sys.autoOff":         "إطفاء تلقائي قبل دقيقة",
        "sys.writeFailed":     "تعذّر تغيير مدة إطفاء الشاشة",
        "update.availableFmt": "الإصدار %@ متاح · انقر للتنزيل",
    ],
    .pt: [
        "section.screenOff":   "Temporizador de tela",
        "menu.now":            "Agora",
        "menu.custom":         "Personalizado…",
        "menu.customFmt":      "Personalizado (%@)",
        "menu.never":          "Nunca",
        "section.endAction":   "Ao terminar",
        "menu.lockOnly":       "Bloquear tela",
        "menu.lockOff":        "Bloquear e desligar a tela",
        "menu.lockSleep":      "Bloquear, desligar e suspender",
        "menu.lockOffNoSleep": "Bloquear, desligar, sem suspender",
        "menu.screenOff":      "Desligar a tela",
        "section.timedLock":   "Bloqueio programado",
        "menu.language":       "Idioma",
        "menu.keepAwake":      "Manter ativo",
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
        "tl.until":            "Até",
        "tl.untilStop":        "parar",
        "tl.savedUntilFmt":    "Bloqueio programado (%d min / até %@)…",
        "tl.pickOne":          "«Durante» e «Até» são alternativos: preencher um limpa o outro.",
        "tl.badTime":          "Digite um horário de 24 h, ex.: 23:30.",
        "login.errTitle":      "Não foi possível ativar a abertura ao fazer login",
        "login.errMsg":        "Mova o SleepBar.app para a pasta Aplicativos e tente novamente.",
        "section.sysOff":      "Desligamento do sistema",
        "sys.offAfterFmt":     "Desligar após: %@",
        "sys.autoOff":         "Desligar a tela 1 min antes",
        "sys.writeFailed":     "Não foi possível alterar o tempo de desligamento",
        "update.availableFmt": "Versão %@ disponível · clique para baixar",
    ],
    .ja: [
        "section.screenOff":   "画面オフタイマー",
        "menu.now":            "今すぐ",
        "menu.custom":         "カスタム…",
        "menu.customFmt":      "カスタム (%@)",
        "menu.never":          "オフにしない",
        "section.endAction":   "時間になったら",
        "menu.lockOnly":       "画面をロック",
        "menu.lockOff":        "ロックして画面をオフ",
        "menu.lockSleep":      "ロック・オフしてスリープ",
        "menu.lockOffNoSleep": "ロック・オフ（スリープしない）",
        "menu.screenOff":      "画面オフ",
        "section.timedLock":   "定期ロック",
        "menu.language":       "言語",
        "menu.keepAwake":      "スリープしない",
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
        "tl.until":            "終了時刻",
        "tl.untilStop":        "に自動停止",
        "tl.savedUntilFmt":    "定期ロック (%d 分 / %@ まで)…",
        "tl.pickOne":          "「継続」と「終了時刻」はどちらか一方です。片方を入力すると他方は消えます。",
        "tl.badTime":          "24 時間制で入力してください(例: 23:30)。",
        "login.errTitle":      "ログイン時の起動を設定できません",
        "login.errMsg":        "SleepBar.app を「アプリケーション」フォルダに移動してからもう一度お試しください。",
        "section.sysOff":      "システムの画面オフ",
        "sys.offAfterFmt":     "オフまでの時間: %@",
        "sys.autoOff":         "1分前に自動で画面オフ",
        "sys.writeFailed":     "画面オフ時間を変更できませんでした",
        "update.availableFmt": "新しいバージョン %@ · クリックしてダウンロード",
    ],
    .de: [
        "section.screenOff":   "Bildschirm-Timer",
        "menu.now":            "Jetzt",
        "menu.custom":         "Eigene Dauer…",
        "menu.customFmt":      "Eigene Dauer (%@)",
        "menu.never":          "Nie",
        "section.endAction":   "Nach Ablauf",
        "menu.lockOnly":       "Bildschirm sperren",
        "menu.lockOff":        "Sperren und Bildschirm ausschalten",
        "menu.lockSleep":      "Sperren, ausschalten & Ruhezustand",
        "menu.lockOffNoSleep": "Sperren, ausschalten, wach bleiben",
        "menu.screenOff":      "Bildschirm aus",
        "section.timedLock":   "Zeitgesteuerte Sperre",
        "menu.language":       "Sprache",
        "menu.keepAwake":      "Wach bleiben",
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
        "tl.until":            "Bis",
        "tl.untilStop":        "dann stoppen",
        "tl.savedUntilFmt":    "Zeitgesteuerte Sperre (%d Min. / bis %@)…",
        "tl.pickOne":          "„Dauer“ und „Bis“ schließen sich aus – eines auszufüllen leert das andere.",
        "tl.badTime":          "Bitte eine 24-Stunden-Zeit eingeben, z. B. 23:30.",
        "login.errTitle":      "„Bei der Anmeldung öffnen“ konnte nicht aktiviert werden",
        "login.errMsg":        "Verschiebe SleepBar.app in den Ordner „Programme“ und versuche es erneut.",
        "section.sysOff":      "System-Bildschirm aus",
        "sys.offAfterFmt":     "Ausschalten nach: %@",
        "sys.autoOff":         "1 Min. vorher Bildschirm aus",
        "sys.writeFailed":     "Bildschirm-Auszeit konnte nicht geändert werden",
        "update.availableFmt": "Version %@ verfügbar · zum Herunterladen klicken",
    ],
]

// Built-in keyboard backlight control via CoreBrightness's private KeyboardBrightnessClient.
@objc private protocol KeyboardBacklight {
    func brightnessForKeyboard(_ keyboard: Int64) -> Float
    func setBrightness(_ brightness: Float, forKeyboard keyboard: Int64) -> Bool
}

// Keeps the Timed Lock dialog's two end-time fields mutually exclusive: typing into one
// blanks the other, so the dialog can never carry two conflicting answers to "until when".
private final class ExclusiveFields: NSObject, NSTextFieldDelegate {
    private let a: NSTextField, b: NSTextField
    init(_ a: NSTextField, _ b: NSTextField) {
        self.a = a; self.b = b
        super.init()
        a.delegate = self; b.delegate = self
    }
    func controlTextDidChange(_ note: Notification) {
        guard let edited = note.object as? NSTextField else { return }
        let other = edited === a ? b : a
        guard !edited.stringValue.trimmingCharacters(in: .whitespaces).isEmpty,
              !other.stringValue.isEmpty else { return }
        other.stringValue = ""
    }
}

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
    private var tlUntil: String = ""      // "23:30" when the window was given as a clock time ("" = a duration was used)
    private var tlWindowEnd: Date?        // absolute end time of the window
    private var tlTimer: Timer?           // adaptive idle check (not a per-second poll)
    private var tlWindowTimer: Timer?     // one-shot stop when the window ends
    private var tlItem: NSMenuItem!
    private var launchItem: NSMenuItem!   // "Launch at Login" toggle (.app builds only)

    // —— Keep Awake ——
    // An always-on toggle (no trigger logic): while checked, a standalone caffeinate
    // process blocks idle/system sleep (but not display sleep). Independent of the
    // Screen Off Timer; persists across launches.
    private var keepAwake = false
    private var keepAwakeTask: Process?
    private var keepAwakeItem: NSMenuItem!

    // —— Update check ——
    // A fortnightly, fire-and-forget GET of the repo's latest release tag. Nothing is
    // downloaded or installed and no data is sent: when a newer version exists, a single
    // menu item appears that opens the release page, and the user updates by hand.
    private let updateFeedURL = URL(string: "https://api.github.com/repos/ddasy/SleepBar/releases/latest")!
    private let updateReleasesURL = URL(string: "https://github.com/ddasy/SleepBar/releases/latest")!
    private let updateInterval: TimeInterval = 14 * 24 * 3600
    private var latestVersion: String?     // set only when the remote tag is newer than ours
    private var latestURL: URL?            // that release's page
    private var updateTimer: Timer?
    private var updateItem: NSMenuItem!
    private var updateSeparator: NSMenuItem!

    // —— System display-off time (pmset displaysleep) ——
    // Reading the current power source's displaysleep needs no privileges; changing it
    // goes through pmset behind a one-time admin-password prompt (root is required to
    // write power settings). autoOff triggers the "息屏" action (no lock, mouse wakes it)
    // one minute before the system would sleep the display, so the system's
    // "require password after display off" lock never engages.
    private var sysOffMinutes: Int = -1        // current-source displaysleep; -1 = not read yet, 0 = never
    private var sysOffOnAC = true              // which power source the value (and a write) applies to
    private var sysOffItem: NSMenuItem!
    private var sysOffPresetItems: [(min: Int, item: NSMenuItem)] = []
    private let sysOffPresets = [1, 2, 5, 10, 15, 20, 30, 45, 60, 180, 0]  // System Settings pillars; 0 = never
    private var autoOffEnabled = false
    private var autoOffTimer: Timer?           // adaptive idle check, same pattern as Timed Lock
    private var autoOffItem: NSMenuItem!
    private var powerSourceRunLoopSource: CFRunLoopSource?   // held for the app's lifetime
    private var sigtermSource: DispatchSourceSignal?         // ditto

    // —— Screen off via brightness (the "息屏" / Screen Off end action) ——
    // Instead of sleeping the display (which stalls GPU rendering), drop the built-in
    // display brightness to 0 and keep things awake; the watcher restores it on return.
    private var savedBrightness: [CGDirectDisplayID: Float] = [:]
    private var screenOffMonitor: Any?            // global mouse monitor: restore on user return
    private var screenOffIdleTimer: Timer?        // keyboard fallback: watch HID idle for a drop
    private var lastScreenOffIdle: TimeInterval = 0
    private var screenOffActive = false

    // Keyboard backlight (built-in keyboard = id 1). The client is held for the app's
    // lifetime so the level we set actually sticks. savedKeyboardBrightness = pre-dim level.
    private let keyboardID: Int64 = 1
    private lazy var keyboardClientObj: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()
    private var keyboardBacklight: KeyboardBacklight? { keyboardClientObj.map { unsafeBitCast($0, to: KeyboardBacklight.self) } }
    private var savedKeyboardBrightness: Float?

    // Output volume (system slider, 0…100) dimmed to 1% and muted alongside the screen;
    // the pre-dim level and mute state are restored on wake, same as brightness.
    // savedVolume stays nil on outputs with no software volume control (HDMI, most USB
    // DACs, AirPlay) — there, muting is the whole of the effect. savedMuted != nil is the
    // "we dimmed something and owe a restore" marker.
    private var savedVolume: Int?
    private var savedMuted: Bool?

    // Preset durations (minutes); titles are generated per language
    private let presets: [Int] = [5, 10, 15, 30, 60]

    // Menu item references (for updating checkmarks)
    private var presetItems: [(min: Int, item: NSMenuItem)] = []
    private var customItem: NSMenuItem!
    private var neverItem: NSMenuItem!
    private var lockOnlyItem: NSMenuItem!
    private var lockOffItem: NSMenuItem!
    private var lockSleepItem: NSMenuItem!
    private var lockOffNoSleepItem: NSMenuItem!
    private var screenOffItem: NSMenuItem!

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
        tlUntil     = UserDefaults.standard.string(forKey: "tlUntil") ?? ""
        keepAwake   = UserDefaults.standard.bool(forKey: "keepAwake")
        autoOffEnabled = UserDefaults.standard.bool(forKey: "autoScreenOff")

        // Observe lock/unlock (event-driven; zero polling while locked)
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(screenDidLock),
                       name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dc.addObserver(self, selector: #selector(screenDidUnlock),
                       name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        // Plugging in or unplugging swaps macOS to the other displaysleep profile, so both
        // the menu label and any pending auto-off deadline have to be recomputed.
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx = ctx else { return }
            Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue().powerSourceChanged()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSourceRunLoopSource = src
        }

        // Timers don't run while the machine is asleep, so a pending auto-off deadline comes
        // back stale (and idle is zero again anyway). Recompute it from the wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        // install.sh passes --register-login on the first launch after installing:
        // register as a Login Item (SMAppService; uncheck anytime via "Launch at Login")
        if CommandLine.arguments.contains("--register-login"), isAppBundle,
           #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }

        installTerminationHandler()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        refreshUI()
        if keepAwake { startKeepAwake() }   // restore the always-on keep-awake assertion
        readSysOff { [weak self] _ in self?.rearmAutoOff() }   // populate the menu; arm auto screen-off
        scheduleUpdateCheck()
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

        // —— Update notice (stays hidden unless a newer release was found) ——
        updateItem = NSMenuItem(title: "", action: #selector(openLatestRelease), keyEquivalent: "")
        updateItem.target = self
        updateItem.image = icon("arrow.down.circle.fill")
        menu.addItem(updateItem)
        updateSeparator = .separator()
        menu.addItem(updateSeparator)

        // —— Screen Off Timer ——
        menu.addItem(.sectionHeader(title: t("section.screenOff")))
        let nowItem = NSMenuItem(title: t("menu.now"), action: #selector(pickNow), keyEquivalent: "")
        nowItem.target = self
        nowItem.image = icon("bolt")
        menu.addItem(nowItem)
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
        // Items are ordered shortest-label-first, so "息屏" (Screen Off) comes first.
        screenOffItem = NSMenuItem(title: t("menu.screenOff"), action: #selector(pickScreenOff), keyEquivalent: "")
        screenOffItem.target = self
        screenOffItem.image = icon("sun.min")
        menu.addItem(screenOffItem)

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

        lockOffNoSleepItem = NSMenuItem(title: t("menu.lockOffNoSleep"), action: #selector(pickLockOffNoSleep), keyEquivalent: "")
        lockOffNoSleepItem.target = self
        lockOffNoSleepItem.image = icon("lock.open.display")
        menu.addItem(lockOffNoSleepItem)

        // —— Timed Lock ——
        menu.addItem(.sectionHeader(title: t("section.timedLock")))
        tlItem = NSMenuItem(title: tlLabel(), action: #selector(toggleTimedLock), keyEquivalent: "")
        tlItem.target = self
        tlItem.image = icon("lock.rotation")
        menu.addItem(tlItem)

        // —— System Display Off (read/write pmset displaysleep + auto early screen-off) ——
        menu.addItem(.sectionHeader(title: t("section.sysOff")))
        sysOffItem = NSMenuItem(title: sysOffLabel(), action: nil, keyEquivalent: "")
        sysOffItem.image = icon("timer")
        let sysMenu = NSMenu()
        sysOffPresetItems = []
        for minutes in sysOffPresets {
            let title = (minutes == 0) ? t("menu.never") : durationTitle(minutes)
            let item = NSMenuItem(title: title, action: #selector(pickSysOff(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            sysMenu.addItem(item)
            sysOffPresetItems.append((minutes, item))
        }
        sysOffItem.submenu = sysMenu
        menu.addItem(sysOffItem)

        autoOffItem = NSMenuItem(title: t("sys.autoOff"), action: #selector(toggleAutoOff), keyEquivalent: "")
        autoOffItem.target = self
        autoOffItem.image = icon("moon")
        menu.addItem(autoOffItem)

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

        // —— Keep Awake (always-on toggle; no trigger logic) ——
        keepAwakeItem = NSMenuItem(title: t("menu.keepAwake"),
                                   action: #selector(toggleKeepAwake), keyEquivalent: "")
        keepAwakeItem.target = self
        keepAwakeItem.image = icon("cup.and.saucer")
        menu.addItem(keepAwakeItem)

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

    func menuWillOpen(_ menu: NSMenu) {
        updateChecks()
        readSysOff()   // async refresh; the submenu label updates in place when it lands
    }

    private func updateChecks() {
        let m = activeMinutes
        for (min, item) in presetItems { item.state = (m == min) ? .on : .off }
        customItem.title = customLabel()
        customItem.state = isCustomActive() ? .on : .off
        neverItem.state = (m == -1) ? .on : .off
        lockOnlyItem.state = (endAction == .lockOnly) ? .on : .off
        lockOffItem.state = (endAction == .lockOff) ? .on : .off
        lockSleepItem.state = (endAction == .lockSleep) ? .on : .off
        lockOffNoSleepItem.state = (endAction == .lockOffNoSleep) ? .on : .off
        screenOffItem.state = (endAction == .screenOff) ? .on : .off
        if tlItem != nil {                       // remaining time is computed only when the menu opens (saves power)
            tlItem.title = tlLabel()
            tlItem.state = tlActive ? .on : .off
        }
        if keepAwakeItem != nil {
            keepAwakeItem.state = keepAwake ? .on : .off
        }
        if autoOffItem != nil {
            autoOffItem.state = autoOffEnabled ? .on : .off
        }
        updateSysOffUI()
        if updateItem != nil {
            let available = latestVersion != nil
            updateItem.isHidden = !available
            updateSeparator.isHidden = !available
            if let v = latestVersion {
                updateItem.title = String(format: t("update.availableFmt"), v)
            }
        }
        if launchItem != nil {
            launchItem.state = launchAtLoginEnabled() ? .on : .off
        }
    }

    // MARK: - Screen-off timer actions

    // "Now": run the configured end action immediately; any running countdown
    // has served its purpose, so cancel it (Timed Lock keeps running — this is
    // just like a manual lock, which never affects its window)
    @objc private func pickNow() {
        if activeMinutes != nil { goIdle() }
        performEndAction()
    }

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

    @objc private func pickLockOnly()    { setEndAction(.lockOnly) }
    @objc private func pickLockOff()     { setEndAction(.lockOff) }
    @objc private func pickLockSleep()   { setEndAction(.lockSleep) }
    @objc private func pickLockOffNoSleep() { setEndAction(.lockOffNoSleep) }
    @objc private func pickScreenOff()      { setEndAction(.screenOff) }

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

    // MARK: - Keep Awake (always-on, independent of the Screen Off Timer)

    @objc private func toggleKeepAwake() { setKeepAwake(!keepAwake) }

    // Set the always-on Keep Awake state, persist it, start/stop the caffeinate, and
    // sync the checkmark. Also called by the .lockSleep end action to drop the assertion
    // (it would otherwise fight pmset sleepnow and keep the machine dark-wake-thrashing).
    private func setKeepAwake(_ on: Bool) {
        keepAwake = on
        UserDefaults.standard.set(keepAwake, forKey: "keepAwake")
        if keepAwake { startKeepAwake() } else { stopKeepAwake() }
        updateChecks()
    }

    private func startKeepAwake() {
        stopKeepAwake()
        // -is: block idle/system sleep (but not display sleep), with no -t so it
        // lasts until the toggle is switched off or the app quits.
        let p = makeCaffeinate(args: ["-is"]) { _ in }
        if launch(p) { keepAwakeTask = p }
    }

    private func stopKeepAwake() {
        if let p = keepAwakeTask { p.terminationHandler = nil; p.terminate() }
        keepAwakeTask = nil
    }

    @objc private func quit() { wakeFromScreenOff(); stopKeepAwake(); NSApp.terminate(nil) }

    // MARK: - caffeinate control

    private func startTimed(minutes: Int) {
        stopTimedLock()   // mutually exclusive with Timed Lock (one keeps awake, the other locks on idle)
        killTask()
        let seconds = minutes * 60
        let p = makeCaffeinate(args: ["-dis", "-t", "\(seconds)"]) { [weak self] proc in
            guard let self = self, self.task === proc else { return }
            // Reset to idle first (the timer process already ended), then run the
            // end action — so an action that installs its own task (lockOffNoSleep)
            // isn't immediately torn down.
            self.task = nil
            self.activeMinutes = nil
            self.endDate = nil
            self.stopTicker()
            self.performEndAction()         // run the action when time is up
            self.refreshUI(); self.updateChecks()
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
        // A countdown suppresses the automatic early-screen-off checks. Recalculate
        // immediately when it is cancelled so macOS cannot win the race while the
        // previous (coarse) retry is still pending.
        rearmAutoOff()
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
            // Drop any lingering per-run caffeinate first: a leftover "息屏" assertion
            // (caffeinate -dis) blocks display sleep, so displaysleepnow would be fought.
            if screenOffActive { wakeFromScreenOff() } else { killTask() }
            lockScreen()
            runPmset("displaysleepnow")
        case .lockSleep:
            // A forced sleep can't hold against a live "prevent sleep" assertion: pmset
            // sleepnow with a caffeinate still running makes the Mac dark-wake-thrash (fans
            // ramp on an idle, cool CPU) instead of staying asleep. Release every sleep
            // blocker first — any per-run caffeinate (task) and the always-on Keep Awake
            // toggle, which directly contradicts "sleep now".
            if screenOffActive { wakeFromScreenOff() } else { killTask() }
            if keepAwake { setKeepAwake(false) }
            lockScreen()
            runPmset("sleepnow")
        case .lockOffNoSleep:
            // Lock, turn the display off, but keep the system awake: start a lingering
            // caffeinate that blocks idle/system sleep (but not display sleep).
            // Cancelled by killTask() on the next screen-off action or on quit.
            lockScreen()
            killTask()
            runPmset("displaysleepnow")
            let keep = makeCaffeinate(args: ["-is"]) { _ in }
            if launch(keep) { task = keep }
        case .screenOff:
            activateScreenOff()
        }
    }

    // "Screen off" (no lock): built-in brightness → 0, external display → DDC
    // power-off, and keyboard backlight → 0 — all a true black that, unlike display
    // sleep, keeps the GPU rendering (the built-in stays on at brightness 0 as the
    // GPU's wake anchor). Output volume also drops to 1%. Keep the system awake
    // (caffeinate -dis). The watcher restores brightness + keyboard + volume and
    // re-lights the external when the user returns.
    // Called by the .screenOff end action and by the auto-early-screen-off trigger.
    private func activateScreenOff() {
        killTask()
        stopScreenOffWatch()
        dimBuiltInToZero()
        externalDisplayOff()
        dimKeyboardToZero()
        dimVolumeToOne()
        let keep = makeCaffeinate(args: ["-dis"]) { _ in }
        if launch(keep) { task = keep }
        startScreenOffWatch()
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

    // MARK: - Screen off via brightness (keep rendering alive instead of sleeping the display)

    // Private DisplayServices: control the real panel backlight on Apple Silicon. The
    // built-in display dims to (near) black; external displays are best-effort — many
    // ignore software brightness and only respond to DDC. Resolved once, like the
    // login.framework lookup in lockScreen().
    private typealias DSGetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let dsGet: DSGetFn? = dsHandle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: DSGetFn.self) }
    private static let dsSet: DSSetFn? = dsHandle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: DSSetFn.self) }

    private func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    // Save the built-in display's current brightness, then set it to 0. Only the built-in
    // panel is touched — external displays (which can't be reliably restored over DDC) are
    // left alone. Re-entry keeps the first-saved value so a second call can't record 0.
    private func dimBuiltInToZero() {
        guard let get = Self.dsGet, let set = Self.dsSet else { return }
        for id in activeDisplays() where CGDisplayIsBuiltin(id) != 0 {
            if savedBrightness[id] != nil { _ = set(id, 0); continue }   // re-entry: keep first-saved level
            var cur: Float = 0
            guard get(id, &cur) == 0 else { continue }   // can't read it → can't guarantee restore → leave it alone
            savedBrightness[id] = cur
            _ = set(id, 0)
        }
    }

    private func restoreBrightness() {
        if let set = Self.dsSet {
            for (id, value) in savedBrightness { _ = set(id, value) }
        }
        savedBrightness.removeAll()
    }

    // Save the keyboard backlight level and turn it off. Re-entry keeps the first saved value.
    private func dimKeyboardToZero() {
        guard let kb = keyboardBacklight else { return }
        let cur = kb.brightnessForKeyboard(keyboardID)
        guard cur >= 0 else { return }                 // no controllable backlight on this machine
        if savedKeyboardBrightness == nil { savedKeyboardBrightness = cur }
        _ = kb.setBrightness(0, forKeyboard: keyboardID)
    }

    private func restoreKeyboardBrightness() {
        guard let kb = keyboardBacklight, let saved = savedKeyboardBrightness else { return }
        _ = kb.setBrightness(saved, forKeyboard: keyboardID)
        savedKeyboardBrightness = nil
    }

    // Output volume + mute, via AppleScript's volume settings (0…100).
    //
    // Muting matters as much as the 1%: on outputs macOS can't attenuate in software
    // (HDMI, most USB DACs, AirPlay) `output volume` reads back as `missing value` and
    // setting it does nothing — the mute flag is the only thing that actually silences
    // those. The previous code bailed out on exactly those devices and left the volume
    // untouched, with no sign anything had gone wrong.
    //
    // One osascript run reads the pre-dim state *and* applies the new one, so there is no
    // window in which a wake can race the dim, and the main thread stalls once, not twice.
    // Re-entry keeps the first saved state so a second call can't record the dimmed 1.
    private func dimVolumeToOne() {
        guard savedMuted == nil else { return }
        let script = """
        set s to (get volume settings)
        set v to output volume of s
        set m to output muted of s
        set volume output volume 1 with output muted
        return (v as string) & "|" & (m as string)
        """
        guard let out = runOsascript(script) else { return }   // script failed → nothing applied
        let parts = out.split(separator: "|", omittingEmptySubsequences: false)
                       .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return }
        savedVolume = parts[0] == "missing value" ? nil : Int(parts[0])
        savedMuted  = parts[1] == "true"                      // "missing value" → treat as unmuted
    }

    // savedMuted (not savedVolume) is the "we dimmed something" marker: on a device with no
    // software volume there is no level to restore, but the mute we applied still has to go.
    private func restoreVolume() {
        guard let muted = savedMuted else { return }
        let level = savedVolume.map { "output volume \($0) " } ?? ""
        _ = runOsascript("set volume \(level)\(muted ? "with" : "without") output muted")
        savedVolume = nil
        savedMuted = nil
    }

    // Returns stdout, or nil if osascript failed. Waiting (rather than fire-and-forget)
    // reaps the child, keeps dim and restore ordered, and makes a failure visible to the
    // caller instead of silently doing nothing.
    @discardableResult
    private func runOsascript(_ script: String) -> String? {
        let r = Self.runCaptureStatus("/usr/bin/osascript", ["-e", script])
        guard r.status == 0 else { return nil }
        return r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // After "息屏", restore the moment the user comes back. A short grace period skips the
    // input that triggered the action (and any immediate residual); then a global event
    // monitor fires on the first real mouse input. Event-driven, so the intermittent activity
    // that defeated idle-polling can't defeat it. (Mouse events need no Accessibility permission.)
    private func startScreenOffWatch() {
        stopScreenOffWatch()
        screenOffActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.screenOffActive, self.screenOffMonitor == nil else { return }
            self.screenOffMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            ) { [weak self] _ in self?.wakeFromScreenOff() }
            self.startScreenOffIdleWatch()
        }
    }

    // Keyboard fallback for the mouse monitor above. A global .keyDown monitor would need
    // Accessibility permission, so watch the HID idle clock instead — keystrokes reset it
    // too. Without this, returning via the keyboard leaves the screen black and the audio
    // muted with no way out but a mouse nudge (and macOS won't sleep the display either:
    // our own caffeinate -d is holding it awake).
    //
    // A *drop* in idle seconds means new input, which is timing-independent — comparing
    // against a fixed threshold would miss a keystroke that lands just after a tick.
    // Polling is only appropriate here because systemIdleSeconds() reads hardware HID
    // state: on the combined source an event posted by any other process reads as user
    // activity, which would wake the screen for no reason.
    private func startScreenOffIdleWatch() {
        lastScreenOffIdle = systemIdleSeconds()
        let tm = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, self.screenOffActive else { return }
            let idle = self.systemIdleSeconds()
            let dropped = idle < self.lastScreenOffIdle - 0.1
            self.lastScreenOffIdle = idle
            if dropped { self.wakeFromScreenOff() }
        }
        tm.tolerance = 0.3
        RunLoop.main.add(tm, forMode: .common)
        screenOffIdleTimer = tm
    }

    private func stopScreenOffWatch() {
        screenOffActive = false
        if let m = screenOffMonitor { NSEvent.removeMonitor(m); screenOffMonitor = nil }
        screenOffIdleTimer?.invalidate()
        screenOffIdleTimer = nil
    }

    // User returned: restore built-in brightness + keyboard backlight, re-light the external
    // display, and drop the keep-awake caffeinate we started.
    private func wakeFromScreenOff() {
        stopScreenOffWatch()
        restoreBrightness()
        restoreKeyboardBrightness()
        restoreVolume()
        externalDisplayWake()
        killTask()
        rearmAutoOff()   // idle just reset; schedule the next early-screen-off check
    }

    // MARK: - System display-off time (pmset displaysleep) + auto early screen-off

    private func sysOffLabel() -> String {
        let value: String
        if sysOffMinutes < 0 { value = "…" }
        else if sysOffMinutes == 0 { value = t("menu.never") }
        else { value = durationTitle(sysOffMinutes) }
        return String(format: t("sys.offAfterFmt"), value)
    }

    private func updateSysOffUI() {
        guard sysOffItem != nil else { return }
        sysOffItem.title = sysOffLabel()
        for (min, item) in sysOffPresetItems { item.state = (min == sysOffMinutes) ? .on : .off }
    }

    private static func runCapture(_ path: String, _ args: [String]) -> String {
        runCaptureStatus(path, args).out
    }

    // Same, but keeps stderr and the exit status. The pmset write path needs both to tell
    // "the user cancelled the password prompt" apart from "the write actually failed".
    // Outputs here are a few hundred bytes, well under a pipe buffer, so draining stdout
    // before stderr can't deadlock.
    private static func runCaptureStatus(_ path: String, _ args: [String]) -> (out: String, err: String, status: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return ("", "\(error)", -1) }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: outData, as: UTF8.self),
                String(decoding: errData, as: UTF8.self),
                p.terminationStatus)
    }

    // Which power source is live. In-process (IOKit) rather than parsing `pmset -g ps`, so
    // it is cheap enough to re-check on every power-source notification and immediately
    // before a write. Desktops report AC; an unknown type is treated as AC too.
    private static func onACPower() -> Bool {
        guard let type = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String?
        else { return true }
        return type != kIOPSBatteryPowerValue
    }

    // Read the active power source and its displaysleep minutes (no privileges needed).
    // `pmset -g` reports the profile currently in use, which is the one that matters.
    // Off the main thread; cache + UI update and the completion land back on main.
    private func readSysOff(_ completion: ((Int) -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let onAC = Self.onACPower()
            let out = Self.runCapture("/usr/bin/pmset", ["-g"])
            var mins = 0
            for line in out.split(separator: "\n") {
                let l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("displaysleep") {
                    let rest = l.dropFirst("displaysleep".count).trimmingCharacters(in: .whitespaces)
                    mins = Int(rest.prefix(while: { $0.isNumber })) ?? 0
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.sysOffOnAC = onAC
                self.sysOffMinutes = mins
                self.updateSysOffUI()
                completion?(mins)
            }
        }
    }

    // The power-source notification also fires on battery-percentage ticks, so only act
    // when the AC/battery state actually flipped — that is when macOS swaps in the other
    // displaysleep profile (e.g. 30 min on AC, 5 min on battery) and both the menu label
    // and the pending auto-off deadline are suddenly computed from the wrong number.
    private func powerSourceChanged() {
        guard Self.onACPower() != sysOffOnAC else { return }
        readSysOff { [weak self] _ in self?.rearmAutoOff() }
    }

    @objc private func pickSysOff(_ sender: NSMenuItem) {
        // No "already selected, nothing to do" shortcut: sysOffMinutes is a cache, and
        // skipping on a stale one silently swallows the click.
        setSysOff(minutes: sender.tag)
    }

    // Write displaysleep for the current power source only (-c on AC, -b on battery),
    // mirroring how System Settings keeps the two independent. pmset needs root, so this
    // runs through osascript's admin-password prompt; a cancel simply changes nothing —
    // the re-read afterwards restores the true state either way.
    private func setSysOff(minutes: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Read the source at write time instead of trusting sysOffOnAC: the cache can be
            // minutes old, and writing the wrong profile leaves the live one untouched —
            // "I set 30 minutes and it still turns off after 5".
            let onAC = Self.onACPower()
            let cmd = "/usr/bin/pmset \(onAC ? "-c" : "-b") displaysleep \(minutes)"
            let r = Self.runCaptureStatus("/usr/bin/osascript",
                                          ["-e", "do shell script \"\(cmd)\" with administrator privileges"])
            // Cancelling the password prompt is a deliberate choice, not a failure worth an alert.
            let cancelled = r.err.contains("-128") || r.err.contains("User canceled")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.sysOffOnAC = onAC
                self.readSysOff { got in
                    self.rearmAutoOff()
                    // The write claimed to work but the value didn't move: surface it rather
                    // than quietly repainting the old number back into the menu.
                    guard got != minutes, !cancelled else { return }
                    self.reportSysOffFailure(r.err)
                }
            }
        }
    }

    private func reportSysOffFailure(_ detail: String) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = t("sys.writeFailed")
        a.informativeText = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        a.addButton(withTitle: t("btn.ok"))
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    @objc private func toggleAutoOff() {
        autoOffEnabled.toggle()
        UserDefaults.standard.set(autoOffEnabled, forKey: "autoScreenOff")
        if autoOffEnabled { rearmAutoOff() } else { stopAutoOffTimer() }
        updateChecks()
    }

    private func stopAutoOffTimer() {
        autoOffTimer?.invalidate()
        autoOffTimer = nil
    }

    // (Re)start the adaptive idle check. Safe to call anytime: it no-ops when the
    // toggle is off and the first check computes the precise delay itself.
    private func rearmAutoOff() {
        stopAutoOffTimer()
        guard autoOffEnabled else { return }
        scheduleAutoOffCheck(after: 1)
    }

    // Longest we will ever sleep between checks. The deadline is derived from the *current*
    // power profile, so a long wait is only valid while that profile holds: on AC the next
    // check can be 29 minutes out, and unplugging inside that window drops macOS to the
    // 5-minute battery profile — the display sleeps (and the lock screen engages) with the
    // pending check still 20-plus minutes away, silently skipping that whole round.
    //
    // The power-source notification is the mechanism meant to catch this; the cap is
    // defence in depth for when it is missed, and it is only that — a cap above the 60s
    // lead cannot *guarantee* a catch, it just bounds a 29-minute miss down to one check.
    // 120s is the compromise: at 300s an unplug landed one second past the battery
    // deadline; at 120s the same case fires with the full 59s lead. It costs one
    // `pmset -g` per 2 idle minutes and does not blunt the timing — once idle is within
    // the cap of the deadline, `threshold - idle` wins and the final check lands on the
    // exact second it always did.
    private static let autoOffMaxCheckInterval: TimeInterval = 120

    private func scheduleAutoOffCheck(after seconds: TimeInterval) {
        stopAutoOffTimer()
        guard autoOffEnabled else { return }
        let delay = min(max(1, seconds), Self.autoOffMaxCheckInterval)
        let tm = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.autoOffCheck() }
        // This timer must beat the system display-sleep deadline by one minute.
        // A percentage-based tolerance is unsafe here: at a 30-minute setting,
        // 5% lets the 29-minute timer slip by 87 seconds, after macOS has already
        // turned the display off. Keep the leeway tightly bounded instead.
        tm.tolerance = min(1, delay * 0.05)
        RunLoop.main.add(tm, forMode: .common)
        autoOffTimer = tm
    }

    private func autoOffCheck() {
        guard autoOffEnabled else { return }
        // Re-read pmset each check: the value or the power source may have changed.
        readSysOff { [weak self] mins in
            guard let self = self, self.autoOffEnabled else { return }
            if self.screenOffActive { return }                       // already dark; wake re-arms
            guard mins >= 2 else {                                   // never / too short to lead by 1 min
                self.scheduleAutoOffCheck(after: 300); return
            }
            if self.activeMinutes != nil {                           // countdown/∞ already blocks display sleep
                self.scheduleAutoOffCheck(after: 120); return
            }
            let threshold = TimeInterval(mins * 60 - 60)             // fire 1 min before the system would
            let idle = self.systemIdleSeconds()
            if idle >= threshold { self.activateScreenOff() }
            else { self.scheduleAutoOffCheck(after: threshold - idle) }
        }
    }

    // MARK: - External display off / wake (DDC power-off + DisplayPort link-retrain)

    // External monitors don't expose software brightness reliably, so "brightness 0" just
    // leaves them dimly lit. Instead we turn the panel truly black with a DDC/CI power-off
    // (VCP 0xD6 = 0x04), via IOAVService — the same path m1ddc uses. It CANNOT be turned
    // back on over DDC (the channel is dead while the panel is off), so we wake it by forcing
    // a DisplayPort link retrain (briefly switch resolution and back). Targets the default
    // external display (IOAVServiceCreate), matching the common laptop + one monitor setup.
    private typealias AVCreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias AVWriteFn  = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private static let avHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private static let avCreate: AVCreateFn? = avHandle.flatMap { dlsym($0, "IOAVServiceCreate") }.map { unsafeBitCast($0, to: AVCreateFn.self) }
    private static let avWrite:  AVWriteFn?  = avHandle.flatMap { dlsym($0, "IOAVServiceWriteI2C") }.map { unsafeBitCast($0, to: AVWriteFn.self) }

    private var externalIsOff = false   // only attempt a wake for a display we turned off

    private func externalDisplays() -> [CGDirectDisplayID] {
        activeDisplays().filter { CGDisplayIsBuiltin($0) == 0 }
    }

    // Turn the external display truly black via DDC power mode (VCP 0xD6 = 0x04 = DPMS off).
    private func externalDisplayOff() {
        guard let create = Self.avCreate, let write = Self.avWrite, !externalDisplays().isEmpty,
              let avU = create(kCFAllocatorDefault) else { return }
        let av = avU.takeRetainedValue()
        let inputAddr: UInt8 = 0x51
        var data: [UInt8] = [0x84, 0x03, 0xD6, 0x00, 0x04, 0]           // DDC "Set VCP" D6 = 0x04
        data[5] = 0x6E ^ inputAddr ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4]
        for _ in 0..<2 {                                                 // write twice, like m1ddc
            usleep(10_000)
            _ = data.withUnsafeMutableBytes { write(av, 0x37, UInt32(inputAddr), $0.baseAddress!, 6) }
        }
        externalIsOff = true
    }

    // Wake the external display by forcing a DisplayPort link retrain: switch to another
    // resolution and back. Non-blocking — the switch-back is scheduled, not slept on.
    private func externalDisplayWake() {
        guard externalIsOff else { return }
        externalIsOff = false
        for id in externalDisplays() {
            guard let current = CGDisplayCopyDisplayMode(id),
                  let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] else { continue }
            // Prefer a same-resolution / different-refresh mode: it retrains the DisplayPort
            // link (waking the panel) without changing resolution, so it's fast and doesn't
            // reshuffle windows. Fall back to any different mode. Switching straight back with
            // no delay lets the panel sync just once, directly to the original mode.
            let alt = modes.first { $0.width == current.width && $0.height == current.height
                                    && $0.refreshRate != current.refreshRate && $0.refreshRate > 0 }
                   ?? modes.first { $0.width != current.width || $0.height != current.height }
            guard let alt = alt else { continue }
            applyDisplayMode(alt, to: id)
            applyDisplayMode(current, to: id)
        }
    }

    private func applyDisplayMode(_ mode: CGDisplayMode, to id: CGDirectDisplayID) {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        CGConfigureDisplayWithDisplayMode(cfg, id, mode, nil)
        CGCompleteDisplayConfiguration(cfg, .forSession)
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
        if tlInterval > 0 && !tlUntil.isEmpty {
            return String(format: t("tl.savedUntilFmt"), tlInterval, tlUntil)
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
        alert.informativeText = t("tl.note") + "\n" + t("tl.pickOne")
        alert.addButton(withTitle: t("btn.start"))
        alert.addButton(withTitle: t("btn.cancel"))

        // Three rows of "short sentence + inline value":
        // "Lock after [5] min idle" / "Run for [120] min, then stop" / "Until [23:30] then stop".
        // The last two are either/or — the window is one end time, given either way.
        let leadW: CGFloat = 100, fieldX: CGFloat = 106, fieldW: CGFloat = 56, tailX: CGFloat = 168
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 114))
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
        // A clock time is free text, not a bounded count, so it gets no number formatter.
        func clockField(y: CGFloat, _ value: String) -> NSTextField {
            let f = NSTextField(frame: NSRect(x: fieldX, y: y - 1, width: fieldW, height: 24))
            f.alignment = .center
            f.placeholderString = "23:30"
            f.stringValue = value
            return f
        }
        let intervalField = field(y: 80, tlInterval, "5")
        // Only one of the two end-time fields is ever pre-filled: whichever was used last.
        let windowField   = field(y: 44, tlUntil.isEmpty ? tlWindowMin : 0, "120")
        let untilField    = clockField(y: 8, tlUntil)
        // Row 1: lock after [5] min idle
        container.addSubview(text(t("tl.lockAfter"), x: 0, y: 80, w: leadW, .right))
        container.addSubview(intervalField)
        container.addSubview(text(t("tl.minIdle"), x: tailX, y: 80, w: 330 - tailX, .left))
        // Row 2: run for [120] min, then stop
        container.addSubview(text(t("tl.runFor"), x: 0, y: 44, w: leadW, .right))
        container.addSubview(windowField)
        container.addSubview(text(t("tl.thenStop"), x: tailX, y: 44, w: 330 - tailX, .left))
        // Row 3: until [23:30] then stop — mutually exclusive with row 2
        container.addSubview(text(t("tl.until"), x: 0, y: 8, w: leadW, .right))
        container.addSubview(untilField)
        container.addSubview(text(t("tl.untilStop"), x: tailX, y: 8, w: 330 - tailX, .left))
        intervalField.nextKeyView = windowField
        windowField.nextKeyView = untilField
        untilField.nextKeyView = intervalField
        // Held for the life of the modal: NSTextField does not retain its delegate.
        let exclusive = ExclusiveFields(windowField, untilField)
        alert.accessoryView = container

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = intervalField
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        withExtendedLifetime(exclusive) {}
        guard confirmed else { return }
        let iv = Int(intervalField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        guard iv > 0 else { return }
        let clock = untilField.stringValue.trimmingCharacters(in: .whitespaces)
        if !clock.isEmpty {
            guard let until = parseClock(clock) else { badTimeAlert(); return }
            // window must fit at least one interval, or it would stop before ever locking
            startTimedLock(interval: iv, window: max(until.minutes, iv), until: until.text)
            return
        }
        let wv = Int(windowField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        guard wv > 0 else { return }
        startTimedLock(interval: iv, window: max(wv, iv), until: "")
    }

    // "23:30" / "23:30" with a full-width colon / "2330" / "9" → how many minutes from now
    // until the clock next reads that, plus the normalized text to show and remember. A
    // time that has already passed today means tomorrow, so the answer is always ahead.
    private func parseClock(_ raw: String) -> (minutes: Int, text: String)? {
        let s = raw.trimmingCharacters(in: .whitespaces)
                   .replacingOccurrences(of: "：", with: ":")
        var h = -1, m = -1
        if s.contains(":") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) else { return nil }
            h = a; m = b
        } else if s.count == 4, let v = Int(s) {
            h = v / 100; m = v % 100
        } else if s.count <= 2, let v = Int(s) {
            h = v; m = 0
        } else { return nil }
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }

        let cal = Calendar.current, now = Date()
        guard var target = cal.date(bySettingHour: h, minute: m, second: 0, of: now) else { return nil }
        if target <= now { target = cal.date(byAdding: .day, value: 1, to: target) ?? target }
        // Round up, never down: "stop at 23:30" should stop just after 23:30, not at 23:29.
        let minutes = max(1, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
        return (minutes, String(format: "%02d:%02d", h, m))
    }

    private func badTimeAlert() {
        let a = NSAlert()
        a.icon = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        a.messageText = t("section.timedLock")
        a.informativeText = t("tl.badTime")
        a.addButton(withTitle: t("btn.ok"))
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    private func startTimedLock(interval: Int, window: Int, until: String) {
        stopCaffeinateIfRunning()          // stop caffeinate (mutually exclusive)
        tlInterval  = interval
        tlWindowMin = window
        tlUntil     = until                // "" when the window came from the duration field
        UserDefaults.standard.set(interval, forKey: "tlInterval")
        UserDefaults.standard.set(window, forKey: "tlWindowMin")
        UserDefaults.standard.set(until, forKey: "tlUntil")

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

    // Read-only query of system idle seconds (since the last keyboard/mouse input); needs no permissions.
    //
    // .hidSystemState, NOT .combinedSessionState: the combined source is also reset by
    // events *posted* by other processes (automation tools, remote-desktop agents, apps
    // that synthesize mouse moves), so a single stray event can push the idle count below
    // the real one — while macOS times display sleep off hardware HID idle. On a quiet
    // machine the two agree; measuring the clock macOS actually uses is what keeps
    // "one minute early" from drifting on a machine that isn't quiet.
    private func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }

    // Brightness, keyboard backlight and volume are process state we owe the user back, and
    // caffeinate is a child that outlives us (it reparents to launchd and goes on blocking
    // sleep forever). Only the Quit menu item used to clean any of that up, so a logout or
    // an upgrade-in-place while the screen was dark left the panel at brightness 0 and the
    // audio muted, with the watcher that would have undone it gone.
    func applicationWillTerminate(_ note: Notification) {
        cleanUpBeforeExit()
    }

    // AppKit does not route SIGTERM through applicationWillTerminate, so `pkill SleepBar`
    // — which is how install.sh and any upgrade-in-place replace a running copy — would
    // skip the cleanup entirely and orphan the keep-awake caffeinate. Ignore the default
    // disposition and handle it on the main queue instead.
    private func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        s.setEventHandler { [weak self] in
            self?.cleanUpBeforeExit()
            NSApp.terminate(nil)
        }
        s.resume()
        sigtermSource = s
    }

    private func cleanUpBeforeExit() {
        wakeFromScreenOff()
        stopKeepAwake()
    }

    @objc private func systemDidWake() {
        rearmAutoOff()          // the machine just woke: idle is back to zero, recompute the deadline
        scheduleUpdateCheck()   // a timer that came due mid-sleep never fired
    }

    @objc private func screenDidLock() {
        // Locked: the system handles the display from here (auto screen-off must not keep
        // a locked screen lit at brightness 0), so pause the early-screen-off checks too
        stopAutoOffTimer()
        // Locked (whether automatic or manual): idle checks are pointless, stop and wait for unlock
        guard tlActive else { return }
        tlTimer?.invalidate(); tlTimer = nil
    }

    @objc private func screenDidUnlock() {
        // Safety net: if a brightness-0 screen-off is still active at unlock, make sure the
        // brightness is back (the watcher normally handles this before the prompt is reached).
        if !savedBrightness.isEmpty || savedMuted != nil { wakeFromScreenOff() }
        rearmAutoOff()   // unlocked = user is back; restart the early-screen-off watch
        guard tlActive, let end = tlWindowEnd else { return }
        if end.timeIntervalSinceNow <= 0 { stopTimedLock(); return }
        scheduleIdleCheck(after: TimeInterval(tlInterval * 60))   // idle just reset to zero, re-arm
    }

    // MARK: - Update check (notify only; never downloads or installs anything)

    // Our own version, from the bundle. run.sh's bare binary has no Info.plist, so dev
    // builds never check — and neither does anything else without a version to compare.
    private var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    // Compare dotted versions segment by segment. A string comparison gets this backwards
    // as soon as a segment reaches two digits ("1.0.9" would sort above "1.0.10").
    private func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // A one-shot timer for exactly when the next check is due, not a poll: a Mac left
    // running for months wakes the CPU once a fortnight for this. Timers don't fire while
    // the machine is asleep, so systemDidWake re-arms it.
    private func scheduleUpdateCheck() {
        guard isAppBundle, currentVersion != nil else { return }
        updateTimer?.invalidate()
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        let due = last <= 0 ? 0 : (last + updateInterval) - Date().timeIntervalSince1970
        guard due > 0 else {
            // First launch, or overdue — let the launch settle before touching the network.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkForUpdate() }
            return
        }
        let tm = Timer(timeInterval: due, repeats: false) { [weak self] _ in self?.checkForUpdate() }
        tm.tolerance = 3600      // nothing here is time-critical; let the system coalesce it
        RunLoop.main.add(tm, forMode: .common)
        updateTimer = tm
    }

    // One anonymous GET of the public releases endpoint. The timestamp is written before
    // the request, so an offline machine waits out the interval instead of retrying; any
    // failure is silent by design — a background check is not worth an error dialog.
    private func checkForUpdate() {
        guard let current = currentVersion else { return }
        // Self-gating, so overlapping arms (a wake right after launch, say) can't stack up
        // into two requests. The minute of slack absorbs timer drift.
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard last <= 0 || Date().timeIntervalSince1970 >= last + updateInterval - 60 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        var req = URLRequest(url: updateFeedURL, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("SleepBar/\(current)", forHTTPHeaderField: "User-Agent")   // GitHub rejects requests without one
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let tag = data
                .flatMap { try? JSONSerialization.jsonObject(with: $0) }
                .flatMap { $0 as? [String: Any] }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let name = tag?["tag_name"] as? String {
                    let version = name.hasPrefix("v") ? String(name.dropFirst()) : name
                    if self.isNewer(version, than: current) {
                        self.latestVersion = version
                        self.latestURL = (tag?["html_url"] as? String).flatMap(URL.init(string:))
                        self.updateChecks()
                    }
                }
                self.scheduleUpdateCheck()
            }
        }.resume()
    }

    @objc private func openLatestRelease() {
        NSWorkspace.shared.open(latestURL ?? updateReleasesURL)
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

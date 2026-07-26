<div align="center">

# 🌙 SleepBar

**菜单栏里的「屏幕关闭」定时器 —— 睡前给电脑派个活,到点自动锁屏 / 休眠。**

*A lightweight macOS menu bar timer that locks, dims, or sleeps your Mac after a countdown.*

[English](README.md) · **简体中文**

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![language](https://img.shields.io/badge/built%20with-Swift-orange)
![license](https://img.shields.io/badge/license-MIT-green)
![cpu](https://img.shields.io/badge/idle%20CPU-0%25-success)

</div>

---

## 这是什么?

睡前你常常想再给电脑安排点事 —— 让脚本跑完、让 AI 把任务处理完、等下载结束。但 macOS 的「关闭显示器」时间是**固定**的:这次想撑 5 分钟,下次想撑 1 小时,每次都要钻进系统设置里改来改去,太麻烦。

**SleepBar** 把这件事搬到菜单栏:点一下,选个时长,这段时间屏幕保持常亮;**到点后自动锁屏、息屏,甚至直接休眠** —— 你想怎样,它就怎样。任务跑完,电脑也睡了。

> 全程不修改你的系统设置、不需要 `sudo`。计时一结束就恢复原状。

## ✨ 功能特性

- ⏱️ **倒计时关屏** —— 预设 5 / 10 / 15 / 30 分钟、1 小时,或**自定义任意时长**,菜单栏实时显示剩余时间。
- ⚡ **立即执行** —— 不想等倒计时?点「立即」一键直接锁屏 / 息屏 / 休眠。
- 🔒 **锁屏** —— 到点把屏幕锁到登录界面。
- 🖥️ **息屏** —— 「锁定并息屏」锁屏 + 关显示器更省电;另有独立的「息屏」让**内置屏亮度调到 0、外接屏经 DDC 关到真黑、键盘背光一并关闭**(都不锁屏、不休眠显示器),屏幕全黑但 GPU 渲染不停摆,适合挂着跑渲染 / AI 任务过夜;回来动一下键鼠自动恢复(含键盘背光,外接屏靠 DisplayPort 链路重训点亮)。
- 💤 **休眠** —— 到点直接让整机进入睡眠。
- ♾️ **强制不锁屏(永不)** —— 一键让屏幕一直常亮、绝不自动关闭,适合长任务 / 演示 / 看片。
- 🔁 **定时锁屏** —— 一句话设定:*「无操作 **5** 分钟即锁屏,持续 **2** 小时后自动停止」*。两个数字、一句话:多久没动键鼠就锁、整件事跑多久。设定后,每次空闲到时长就自动锁一次,解锁后重新开始计时,直到「持续」时间结束。「持续」是固定倒计时,**锁屏 / 解锁都不会重置它**。**无需任何权限**(只读取系统空闲时间,绝不拦截输入)。
- 🕹️ **系统关屏时间** —— 菜单里直接显示系统「若无操作则关闭显示器」的当前档位(读 `pmset`,无需权限),两下点击即可改成 macOS 支持的任意档位(1 分钟 – 3 小时或永不)。修改时会弹一次管理员密码框——这是 macOS 对电源设置的硬性要求。
- 🌙 **提前 1 分钟自动息屏** —— 系统自己关屏后往往要重新输密码(哪怕你设了「不需要密码」)。打开此开关后,SleepBar 会在系统关屏前 1 分钟(如系统设 30 分钟,则在空闲 29 分钟时)先执行自家的无锁「息屏」:屏幕全黑但系统保持唤醒,动一下鼠标立刻恢复、不用输密码。系统档位或电源(电池/适配器)变化时自动适应。
- 🧠 **记住自定义时长** —— 上次输入的分钟数会被记住并预填,常用时间一点即用。
- 🌐 **7 种语言** —— 中文、English、Español、العربية、Português (Brasil)、日本語、Deutsch,整个菜单一键切换,首次启动自动跟随系统语言。
- 🪶 **极致轻量** —— 单文件 Swift,无依赖、无后台服务,**空闲时 CPU 约 0%**。

## 📸 截图

| 中文界面 | English |
|:---:|:---:|
| ![SleepBar 中文菜单栏屏幕关闭定时器演示](screenshots/CN.gif) | ![SleepBar English menu bar auto lock and sleep timer demo](screenshots/English.gif) |

## 🚀 安装

### 方式一:一条命令(推荐)

```bash
curl -fsSL https://raw.githubusercontent.com/ddasy/SleepBar/main/install.sh | bash
```

### 方式二:克隆后安装

```bash
git clone https://github.com/ddasy/SleepBar.git
cd SleepBar
./install.sh
```

安装脚本会自动:**检测 Swift 工具链 → 编译 → 生成 `~/Applications/SleepBar.app` → 添加 `sleepbar` 命令别名 → 启动并开启开机自启**。全程**无需 sudo**,所有文件都在你的用户目录里。完成后菜单栏右上角立刻出现 💤 图标,**以后开机自动常驻**(随时可在菜单栏图标 →「**开机自启**」里取消勾选)。

不小心退出了?用 **Spotlight(⌘空格)搜 SleepBar** 重新打开,或在终端输入:

```bash
sleepbar
```

> `sleepbar` 别名写在 `~/.zshrc` 里,安装后**新开的终端窗口**即可使用。

> 首次若提示安装「Xcode 命令行工具」,在弹窗里点安装,完成后重跑一次脚本即可。这是 macOS 自带的编译环境,无需完整 Xcode。

### 方式三:下载 App(DMG)

从 [**Releases**](https://github.com/ddasy/SleepBar/releases) 页面下载最新的 `SleepBar-vX.Y.Z.dmg`,打开后把 **SleepBar.app** 拖进「应用程序」。然后点菜单栏图标 →「**开机自启**」,即可每次登录自动启动。

> DMG 为 ad-hoc 签名、未经 Apple 公证,首次打开可能需要**右键点 App →「打开」**。(上面两种从源码安装的方式不会有此提示。)

### 卸载

```bash
./uninstall.sh
```

会停止运行、移除开机自启、删除 App、`sleepbar` 别名和偏好设置,干净利落。

## 🖱️ 使用

点开菜单栏的 💤 图标:

| 区块 | 选项 | 说明 |
|---|---|---|
| **屏幕关闭时间** | 立即 | **马上执行**「到时间后」选定的动作,无需倒计时 |
| | 5 / 10 / 15 / 30 分钟、1 小时 | 选中即开始倒计时;**再点一次取消** |
| | 自定义时长… | 弹窗输入任意分钟数,**记住并预填**上次的值 |
| | 永不 | 屏幕一直常亮,绝不自动关闭(菜单栏显示 `∞`) |
| **到时间后** | 息屏 | **内置屏**亮度调到 0、**外接屏**经 DDC 关屏、**键盘背光**关闭(都真黑、**不锁屏**),保持唤醒、GPU 渲染不停摆;动一下键鼠**自动恢复**(含键盘背光,外接屏靠链路重训点亮) |
| | 锁定屏幕 | 仅锁屏 |
| | 锁定并息屏 | 锁屏 + 关闭(休眠)显示器,更省电 |
| | 锁定、息屏并休眠 | 锁屏 + 整机直接休眠 |
| | 锁定、息屏且不休眠 | 锁屏 + 关闭显示器,但系统保持唤醒不休眠 |
| **定时锁屏** | 定时锁屏… | 两行弹窗:**「无操作 `[N]` 分钟即锁屏」** 和 **「持续 `[M]` 分钟后自动停止」**。空闲到时长就自动锁一次,直到「持续」时间结束。**再点一次停止。** 两个值都会记住并预填 |
| **语言** | 中文 · English · Español · العربية · Português (Brasil) · 日本語 · Deutsch | 整个菜单即时切换 |
| **开机自启** | 开关 | 登录时自动启动(标准 macOS「登录项」)。install.sh 安装后默认**开启**,不需要就在这里取消勾选 |
| **退出** | | 关闭 SleepBar |

「到时间后」是一次设定、长期记住的偏好;选好后,每次计时到点都会执行它。

**定时锁屏**与「屏幕关闭时间」互斥(开启一个会自动停掉另一个)。举例:中午 12:00 设定 *无操作 5 分钟即锁屏、持续 120 分钟*,那么 12:00–14:00 期间,只要 5 分钟没动键鼠就自动锁屏;解锁后再离开,过 5 分钟又会锁。这 2 小时的倒计时不受锁屏 / 解锁次数影响,到点自动停止。

## ⚙️ 工作原理

SleepBar 只是把 macOS 自带的几个系统能力包了一层友好的菜单:

| 功能 | 底层 |
|---|---|
| 保持常亮 / 倒计时 | `caffeinate -dis -t <秒>`(无 `sudo`,到点自动失效) |
| 关闭显示器 / 锁屏息屏 | `pmset displaysleepnow` |
| 息屏 · 内置屏 | `DisplayServicesSetBrightness` 仅对内置屏调 0 + `caffeinate -dis`;用 `IOHIDSystem` 的 `HIDIdleTime` 检测回归后自动恢复亮度 |
| 息屏 · 外接屏 | `IOAVServiceWriteI2C` 发 DDC 电源关(VCP `D6=04`)关到真黑;回来时瞬间切一次刷新率再切回(同分辨率,`CGConfigureDisplayWithDisplayMode`)强制 DP 链路重训点亮——快且不重排窗口 |
| 息屏 · 键盘背光 | `CoreBrightness` 的 `KeyboardBrightnessClient` 存当前值后调 0,回来还原 |
| 休眠 | `pmset sleepnow` |
| 锁屏 | `login.framework` 的 `SACLockScreenImmediate` |
| 定时锁屏 —— 空闲检测 | `CGEventSource.secondsSinceLastEventType`(只读系统空闲时间,**无需辅助功能权限**) |
| 定时锁屏 —— 解锁后重新武装 | `com.apple.screenIsUnlocked` 分布式通知(事件驱动,锁屏期间零轮询) |
| 偏好记忆 | `UserDefaults`(语言 / 到时间后动作 / 自定义时长 / 锁屏间隔 / 持续时长) |

因为用的是 `caffeinate` 的临时机制,**不会改动你的系统节能设置**,计时一结束就完全恢复原样。

## 🔋 为低功耗而设计

- **空闲时 CPU 约 0%** —— 没有计时任务时不运行任何定时器。
- 倒计时期间仅一个 1Hz 定时器,并设了 `tolerance` 让系统合并唤醒;每次只更新一小段文字,**无逐帧对象分配**。
- **定时锁屏从不每秒轮询。** 它不每秒查输入,而是把下一次唤醒精确安排在「间隔 − 当前空闲」秒之后——活跃时每个间隔最多唤醒一次 CPU;而屏幕锁定期间**完全零轮询**,只是静静等待解锁通知。剩余时间也只在你打开菜单时才计算,平时没有任何后台刷新。
- 以 `-O` 发布优化编译;单一可执行文件,不内嵌框架、无辅助进程。

## 🛠️ 从源码运行(开发)

```bash
git clone https://github.com/ddasy/SleepBar.git
cd SleepBar
./run.sh          # 编译并启动,改完代码再跑一次即可热更新
```

或手动:

```bash
swiftc -O main.swift -o SleepBar -framework AppKit
./SleepBar
```

整个程序就是一个 `main.swift`(约 580 行 AppKit),没有任何第三方依赖。

## 📋 系统要求

- macOS 14 (Sonoma) 及以上(用到原生 `sectionHeader` 菜单)
- Xcode 命令行工具(`xcode-select --install`,安装脚本会自动提示)

## ❓ 常见问题

**Q:「锁屏」用的是私有接口,安全吗?**
A: 调用的是系统 `login.framework` 里的锁屏函数(等同你按下锁屏快捷键),不需要辅助功能权限,也不上传任何数据。若某次系统大版本更新后失效,提个 issue 即可。

**Q: 会偷偷让我的电脑一直不睡吗?**
A: 不会。只有你**主动选了时长或「永不」**才会保持常亮;启动默认是空闲状态,完全按你的系统设置走。

**Q: 重启后还在吗?**
A: 在。安装脚本把 SleepBar 注册为系统「登录项」,登录后自动出现在菜单栏。不需要的话,在菜单里取消勾选「开机自启」即可。

**Q: 不小心退出了,怎么重新打开?**
A: **Spotlight(⌘空格)搜 SleepBar**,或在终端输入 `sleepbar`。

## 🔎 关键词

一个免费开源的 macOS **菜单栏**小工具:**自动锁屏**、**空闲定时反复锁屏**、**定时休眠 / 睡眠定时器**、**屏幕关闭定时**、**保持唤醒 / 防止睡眠**、友好的 **caffeinate 图形界面**。原生 **Swift** 编写,可作为 Amphetamine、KeepingYouAwake、Caffeine 的轻量替代。

建议的 GitHub Topics:`macos` · `menubar` · `menu-bar` · `swift` · `appkit` · `caffeinate` · `sleep-timer` · `screen-lock` · `auto-lock` · `idle-lock` · `keep-awake` · `display-sleep` · `productivity` · `macos-app`

## 📄 许可证

[MIT](LICENSE) © 2026

## 📦 Install / Update · 安装与更新

**Update the same way you installed** — there's no need to uninstall first, and your settings are kept.
**用当初的安装方式更新即可** —— 不必先卸载，偏好设置会保留。

### A · DMG

Quit the running copy first (menu-bar 💤 → **Quit**), then open the `.dmg` attached below and drag **SleepBar.app** into **Applications**, choosing **Replace**.
先在菜单栏 💤 →「退出」关掉正在运行的版本，再打开下方的 `.dmg`，把 **SleepBar.app** 拖进「应用程序」并选择「替换」。

> Ad-hoc signed but **not Apple-notarized**, so macOS may block the first launch: **right-click the app → Open → Open**, or run the command below.
> 本版本为 ad-hoc 签名、**未经 Apple 公证**，首次打开可能被拦截：**右键点 App →「打开」→「打开」**，或执行:
> ```
> xattr -dr com.apple.quarantine /Applications/SleepBar.app
> ```

### B · One-line installer · 一行命令安装的

Re-run the very same command. It pulls the latest source, rebuilds, restarts the app, and keeps launch-at-login.
重跑同一条命令即可：拉取最新源码重新编译、重启 App，并保留开机自启。

```bash
curl -fsSL https://raw.githubusercontent.com/ddasy/SleepBar/main/install.sh | bash
```

### C · Cloned repo · 克隆仓库安装的

```bash
cd SleepBar && git pull && ./install.sh
```

B and C compile on your own machine, so Gatekeeper never gets involved.
B、C 都是在本机编译，不会遇到 Gatekeeper 拦截。

### Not sure which one you used? · 不确定自己是哪种?

```bash
ls -d /Applications/SleepBar.app ~/Applications/SleepBar.app 2>/dev/null
```

`/Applications` → **A** (DMG) · `~/Applications` → **B** or **C**.
If both paths exist you have two copies installed: keep one and `rm -rf` the other, otherwise you'll get two moons in the menu bar.
两个路径都在,说明装了两份:留一份、`rm -rf` 删掉另一份,否则菜单栏会出现两个月亮。

**Requirements · 系统要求:** macOS 14 (Sonoma) or later · Apple Silicon (arm64)

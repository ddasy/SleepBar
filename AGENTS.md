# SleepBar

macOS 菜单栏倒计时睡眠工具（单文件 Swift，AppKit，arm64，macOS 14+）。

## 发布流程（重要）

每次修改代码后，必须打包 DMG 并发布到 GitHub Release，不能让代码领先于已发布的 DMG。
（`*.dmg` 和 `build/` 在 .gitignore 中，不进仓库；用户通过 GitHub Releases 下载 DMG。）

1. 提交并推送代码到 `origin/main`
2. 递增版本号，运行 `./package.sh <version>`（如 `./package.sh 1.0.4`）生成 `SleepBar-v<version>.dmg`
3. 打 tag：`git tag -a v<version> -m "SleepBar v<version> — <亮点>"` 并 `git push origin v<version>`
4. 创建 Release 并附上 DMG：
   `gh release create v<version> SleepBar-v<version>.dmg --title "SleepBar v<version>" --notes "..."`
   （Release notes 格式参考上一个版本：`gh release view v1.0.3 --json body -q .body`）

仅文档/截图类改动无需发版。

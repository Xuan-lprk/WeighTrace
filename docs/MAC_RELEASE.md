# Mac 测试版发布

## 生成安装包

在工程目录执行 `bash scripts/package-mac.sh`。脚本用 Release 配置构建 Apple 芯片与 Intel 通用 App、临时签名并验证，生成带 Applications 快捷方式的 DMG 和 SHA-256 文件到 `dist/`。不会上传、创建 GitHub Release 或携带本机用户数据。

同时保留可直接打开的 `WeighTrace-<版本>-<构建号>-test.app`。DMG 附带 LICENSE 和 SOURCE.txt，记录源码提交与构建时工作区是否干净；对外分发时应使用已提交、已推送的干净源码。版本 1.6 的当前本地测试包使用 Build 9，不覆盖旧包。

这是 ad-hoc 测试签名，不是 Developer ID。无法进行 Apple 公证，也不保证所有接收者的系统都允许打开。接收者无需开发者账号；有管理策略的 Mac 可能禁止未经公证的软件。

## 发布更新

1. 增加 Xcode 中 Version 和 Build；当前检查器根据 Version 判断新版，同 Version 仅增加 Build 不会提示更新。
2. 生成并用另一台 Mac 检查安装、蓝牙权限、实际称重、重启后历史，以及覆盖安装后数据保留。
3. 审查并提交相应代码后，在 GitHub 建立指向该提交的 Release 标签，例如 `v1.7`。上传脚本生成的 `AFU-Scale-Mac-*.dmg` 和校验文件；发布说明可使用下方模板。测试版应如实标记为预发布，不要只为触发更新而标为正式版（当前更新检查会跳过预发布）。
4. 更新检查读取最近 30 个 Release，跳过 draft/prerelease 和没有 Mac DMG 的版本。当前地址在 `MacUpdateChecker.swift`，仓库迁移时必须一起调整。

自动检查默认关闭；开启后进入资料页时检查，当前会话内最多每天一次。当前交付的是自动检查和下载入口，自动下载、签名验证后安装及重启尚未实现。版本尚未公开发布时，不能进行端到端更新验收。

## 发布前的文档检查

- 发布说明只列入本安装包实际包含的功能，不能直接照搬整个“开发中”更新日志。
- 写清实测 macOS、芯片与秤型号；未做的安装、升级或硬件测试标记为“未验证”。
- 保留上游署名及许可证说明，在安装包旁提供该标签的对应源码下载入口，包括构建脚本。当前打包脚本不会自动把 LICENSE 复制进 DMG，发布前须核对分发材料。
- 下载链接指向本仓库，不使用读者无法访问的本机路径；截图使用演示或已脱敏数据。

## 发布说明模板

复制后替换所有占位内容；不要保留未经确认的验收结论。

```markdown
## Mac 测试版 <版本号>

支持 macOS 15.6+，Apple 芯片 / Intel。无需 Xcode 或开发者账号。
仅验证 AFU-WL-TZ-A1；Mac 不支持 Apple 健康，数据保存在本地。

### 下载与安装

在本页 Assets 下载 AFU-Scale-Mac-<版本>-<构建号>-test.dmg，
打开后拖进“应用程序”。Source code 是源码，不是安装包。
测试包未经 Apple 公证；请阅读仓库 docs/MAC_INSTALL.md。
升级前请先导出 JSON 备份，再退出 App 并覆盖安装。

### 本版变化

- <本版实际包含的变化>

### 验证与已知限制

- 实测环境：<系统 / 芯片 / 秤型号；未验证则明确写出>
- 安装、覆盖升级与数据保留：<验证结果或未验证>
- 已知限制：<如实填写>
- 当前仅检查更新并打开下载页，不会自动安装。

### 源码与许可证

本修改版按 GPLv3 发布，保留上游署名。
对应源码：<本 Release 标签的源码链接，包含构建脚本>
许可证：<该标签下 LICENSE 的链接>

反馈问题时请提供版本和复现步骤，不要公开完整健康备份或设备标识。
```

## 完整自动安装后续

Mac Catalyst 的 Sparkle 接入需要 AppKit 插件桥接及沙盒安装服务。应采用 Sparkle 的签名更新机制，保存独立更新签名私钥，并用两版真实发布包验证升级和数据保留。Developer ID 和公证能改善首次安装体验；它们与 Sparkle 的更新签名是两回事，未购买开发者账号并不代表技术上无法实现自动更新。

参考：[Sparkle 沙盒接入](https://sparkle-project.org/documentation/sandboxing/)、[Catalyst 桥接示例](https://github.com/elegantchaos/CatalystSparkle)、[Apple Developer ID 分发](https://developer.apple.com/developer-id/)。

# Mac 测试版发布

## 生成安装包

在工程目录执行 `bash scripts/package-mac.sh`。脚本用 Release 配置构建 Apple 芯片与 Intel 通用 App、临时签名并验证，生成带 Applications 快捷方式的 DMG 和 SHA-256 文件到 `dist/`。不会上传、创建 GitHub Release 或携带本机用户数据。

这是 ad-hoc 测试签名，不是 Developer ID。无法进行 Apple 公证，也不保证所有接收者的系统都允许打开。接收者无需开发者账号；有管理策略的 Mac 可能禁止未经公证的软件。

## 发布更新

1. 增加 Xcode 中 Version 和 Build；当前检查器根据 Version 判断新版，同 Version 仅增加 Build 不会提示更新。
2. 生成并用另一台 Mac 检查安装、蓝牙权限、实际称重、重启后历史，以及覆盖安装后数据保留。
3. 审查并提交相应代码后，在 GitHub 建立正式 Release，例如 `v1.7`。上传脚本生成的 `AFU-Scale-Mac-*.dmg` 和校验文件。
4. 更新检查读取最近 30 个 Release，跳过 draft/prerelease 和没有 Mac DMG 的版本。当前地址在 `MacUpdateChecker.swift`，仓库迁移时必须一起调整。

自动检查默认关闭；开启后进入资料页时检查，当前会话内最多每天一次。当前交付的是自动检查和下载入口，自动下载、签名验证后安装及重启尚未实现。版本尚未公开发布时，不能进行端到端更新验收。

## 完整自动安装后续

Mac Catalyst 的 Sparkle 接入需要 AppKit 插件桥接及沙盒安装服务。应采用 Sparkle 的签名更新机制，保存独立更新签名私钥，并用两版真实发布包验证升级和数据保留。Developer ID 和公证能改善首次安装体验；它们与 Sparkle 的更新签名是两回事，未购买开发者账号并不代表技术上无法实现自动更新。

参考：[Sparkle 沙盒接入](https://sparkle-project.org/documentation/sandboxing/)、[Catalyst 桥接示例](https://github.com/elegantchaos/CatalystSparkle)、[Apple Developer ID 分发](https://developer.apple.com/developer-id/)。

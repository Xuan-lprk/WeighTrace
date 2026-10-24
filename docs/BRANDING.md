# 秤迹 / WeighTrace

核心定位：直接连接已验证的 AFU-WL-TZ-A1 体脂秤，不依赖厂商账号，在本地接收和保存测量。趋势、Apple 健康、备份与双 ADC 对照是围绕这项连接能力的补充，而不是泛用健康平台的承诺。

名称是本项目采用的创意名称，尚未完成商标或重名检索。保留非官方和上游来源说明，不使用厂商品牌作为 App 的独立名称。

## 图标资源

- `design/app-icon-source.png`：保留的第一版原图，仅用于回看。
- `design/app-icon-source-v2.png`：当前原图；移除外围深色场景、将秤面铺满方形画布。
- `体脂秤/Assets.xcassets/AppIcon.appiconset/AppIcon.png`：1024×1024、不透明、sRGB PNG，普通和深色外观复用。画布铺满背景，未预裁系统的外层圆角。
- `AppIcon-Tinted.png`：同尺寸、不透明的 Gray Gamma 2.2 灰度版本，供系统着色。
- `AppIcon-mac-*.png`：Mac 的 16、32、128、256、512 pt 各 1x/2x 资源，最高 1024 像素。使用独立透明画布、连续圆角和留边，不直接复用 iOS 的实心方形图。
- `docs/images/weightrace-icon.png`：256×256、带透明外缘的圆角 README 预览；不是 iOS 打包源图。
- `design/WeighTrace.icns`：完整 Mac 图标文件，包含 16 至 1024 像素尺寸。打包脚本在签名前复制到 Mac App 的 `AppIcon.icns`，补齐 Catalyst 自动生成文件可能缺少的大尺寸回退。

使用 `bash scripts/prepare-app-icons.sh` 从 v2 原图重建上述资源：先居中保留 94% 边长（每边裁掉约 3%），再输出 1024 像素图；不对已经处理过的图重复裁剪。Mac 通过 `scripts/render-mac-icon.swift` 使用 SwiftUI 连续圆角裁切并加入透明留边；824 像素主体与 100 像素留边是本项目的视觉选择，不是宣称 Apple 强制该尺寸。Xcode 通过现有 AppIcon 资源目录编译图标，并为 Catalyst 输出 `AppIcon.icns` 与 `Assets.car`；完整 `.icns` 的安装包替换由打包脚本完成，无需用户手工配置。

当前不是 Icon Composer 的分层 `.icon` 工程，也不宣称实现了分层 Liquid Glass 图标。若后续制作分层图标，需从独立的主体与背景素材重新设计，不能仅把 PNG 改扩展名。

参考：[Apple 资源目录图标配置](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)、[官方图标模板](https://developer.apple.com/design/resources/)、[Create icons with Icon Composer 示例](https://developer.apple.com/videos/play/wwdc2025/361/)。参考其构图和遮罩区分，不复制 Apple 图标或声称官方认证。

## 改名兼容性

中文系统显示“秤迹”，英文系统显示“WeighTrace”。系统桌面名称使用系统的 App 语言偏好，不受 App 内即时界面语言选项控制。

工程、Target 和 Scheme 仍叫“体脂秤”，避免无关文件迁移；构建产物改为 `WeighTrace.app`。Bundle ID、UserDefaults 键和 HealthKit 元数据标识保持原值。DMG 继续使用 `AFU-Scale-Mac-` 前缀，让旧客户端仍能发现新包；DMG 卷名改为 WeighTrace。

图标由内置 imagegen 生成并编辑。v2 编辑提示：保留原图的深青显示窗、青绿趋势曲线和浅薄荷秤面，去掉外围深色背景、悬浮阴影与外层小圆角方块；秤面铺满画布，简化厚重倒角，保留可辨识的内部细节；输出不透明正方形、无文字、无厂商标志。iOS 外层圆角交给系统，Mac 旧式 ICNS 使用单独的透明边缘裁切。

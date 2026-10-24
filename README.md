# 蚂蚁阿福体脂秤 iOS / macOS 客户端

简体中文 | [English](README_EN.md)

用自己的设备连接体脂秤，记录体重、查看趋势，不需要注册厂商账号。支持特定 AFU-WL / Welland 体脂秤，iPhone/iPad 可选写入 Apple 健康，Mac 保存本地历史。

[下载 Mac 测试版](https://github.com/Xuan-lprk/smart-body-scale-IOS/releases)  · [更新日志](docs/CHANGELOG.md) · [反馈问题](https://github.com/Xuan-lprk/smart-body-scale-IOS/issues)

> **先确认型号：目前已验证的是 `AFU-WL-TZ-A1`（即一分钱购买的那款）。** 不是所有阿福、沃莱或其他品牌的体脂秤都能连接。体重来自秤的测量，体脂等身体成分是本地估算，不保证与厂商 App 一致，也不用于医疗判断。

## 下载与安装

| 你的设备 | 怎么安装 | Apple 健康 |
|---|---|---|
| Mac：macOS 15.6+，Apple 芯片或 Intel | 在 [Releases 发布页](https://github.com/Xuan-lprk/smart-body-scale-IOS/releases) 展开 **Assets**，下载 `AFU-Scale-Mac-…-test.dmg` | 不支持；记录保存在 Mac 本地 |
| iPhone / iPad：iOS / iPadOS 18.6+ | 当前需使用 Mac 和 Xcode 自行构建；见下方[开发者运行说明](#开发者构建与运行) | 可选读取与写入 |
| Android | 暂无 App，有需求我再移植 | 不适用 |

Mac 用户**不需要 Xcode，也不需要开发者账号**。下载的是 `.dmg` 安装包，不是页面上的 `Source code (zip)` 源码。[Mac 安装说明](docs/MAC_INSTALL.md)



目前没有提供 App Store 或 TestFlight 安装入口。iPhone/iPad 用户如果不方便自行构建，可以先关注仓库后续发布，或者使用官方客户端。

## 第一次称重

1. 先填写本人的身高、生日和性别；这些资料会影响 BMI 和身体成分估算。
2. 将秤放在坚硬平整的地面，光脚站稳，等待体重与阻抗采集完成。
3. 在测量预览中查看结果，保留或删除本次记录。日常观察趋势时，尽量固定时间、测量条件和所选 ADC。
4. 在“我的 → 备份与导出”保存一份 JSON 备份。**本地记录不等于自动云备份**；Mac 和手机也不会自动互相同步。

搜不到秤？先检查蓝牙权限、秤是否亮屏，以及手机厂商 App、另一台设备或 CLI 是否占用了连接。更完整的排查见下方[开发者构建与运行](#开发者构建与运行)。

## 它能帮你做什么

- **日常记录**：实时称重、测量预览、家庭成员和历史趋势。
- **比较算法**：保留双 ADC，通过手动录入或本机识别阿福截图，对比两路估算与参考结果。
- **管理自己的数据**：JSON 备份恢复、CSV 导出；iPhone/iPad 可选接入 Apple 健康，查看其他来源和疑似重复记录。
- **小工具**：三次重复性检查、动态历史回放，以及宠物、行李等抱物称重。抱物结果是两次称重相减的粗略值，不是专用宠物秤或包裹秤。

这些功能的详细范围见下面的列表和各功能文档。当前项目仍在迭代，发布前的实体秤与跨设备验收不能由编译通过替代。

## 项目与来源

> 本项目来自社区逆向研究，与蚂蚁阿福、沃莱、Fitdays、Icomon 或 Apple 没有隶属或授权关系。

本修改版基于 [maoziban/smart-body-scale-IOS](https://github.com/maoziban/smart-body-scale-IOS) 开发，并保留了原仓库的 Git 提交历史。新增内容包括 HealthKit 写入、ADC 选择、更稳定的广播解析、设备身份绑定、算法与隐私说明等。

## 当前功能

- 扫描并连接 `AFU-WL-TZ-A1`、`subtype=7` 的已验证设备；
- 实时显示体重，稳定后保存一条本地记录；
- 保留秤发送的两个 ADC，并允许选择用于估算的 ADC 1 或 ADC 2；
- 根据体重和阻抗估算体脂，并展示由体脂按比例推算的其他指标；
- 本人资料、家庭成员匹配和本地历史；
- 趋势页按成员、30 天 / 90 天 / 全部及体重 / 体脂 / BMI 筛选，展示原始点、每日体重中位数与 7 日趋势；
- JSON 完整备份与冲突预览合并恢复，CSV 分析导出（详见 [趋势与备份](docs/TRENDS_BACKUP.md)）；
- 三次测量重复性检查、按成员的 ADC 差异图、自定义首页、条件标签与备注（详见 [测量工具](docs/MEASUREMENT_TOOLS.md)）；
- 数据回放与抱物称重：动态重看历史，给宠物、行李或包裹独立记录粗略重量（详见 [回放与抱物称重](docs/PLAYBACK_ASSISTED.md)）；
- 支持 iPhone、iPad 和 Mac（Mac Catalyst）前台蓝牙测量；
- iPhone/iPad 可选写入 Apple 健康：
  - 体重；
  - BMI；
  - 体脂率；
  - 去脂体重；
- iPhone/iPad 可读取 Apple 健康中最近一年的身体测量记录，识别来源 App；
- 提示不同 App 在短时间内写入的疑似重复体重，不自动删除数据；
- 不包含账号、广告或第三方统计 SDK；Mac 可选连接 GitHub 检查版本，不上传测量数据。
- 支持简体中文和英文，并自动跟随系统语言。

## 数据分别来自哪里

| 数据 | 来源 | 含义 |
|---|---|---|
| 体重 | 秤直接测量 | BLE 包解析结果 |
| ADC 1 / ADC 2 | 秤直接发送 | 物理含义尚未完全确认 |
| 阻抗 | 协议换算 | 从所选 ADC 得到 |
| BMI | 本地计算 | 体重 ÷ 身高² |
| 体脂率 | 本地 BIA 公式估算 | 不是秤返回的官方体脂字段 |
| 水分、肌肉、骨量、蛋白质、皮下脂肪 | 本地粗略推算 | 不能视为独立测量 |

当前 BIA 主公式参考 Segal 等人在 1988 年发表的人体成分估算公式；其研究人群主要为成人，因此儿童和青少年的结果尤其需要谨慎解读。没有有效阻抗时使用基于 BMI、年龄和性别的回退估算。

公式来源：

- Segal KR et al. (1988), [Lean body mass estimation by bioelectrical impedance analysis: a four-site cross-validation study](https://pubmed.ncbi.nlm.nih.gov/3337041/)
- Deurenberg P et al. (1991), [Body mass index as a measure of body fatness: age- and sex-specific prediction formulas](https://doi.org/10.1079/BJN19910073)

## 误差与限制

体重为秤直接测量，ADC 为秤直接发送；阻抗来自协议换算。体脂、水分、肌肉、骨量等身体成分均为本地公式估算，不应替代医疗检查。

ADC 对比用于观察两路本地估算与阿福参考结果之间的差异；更接近官方结果，不代表更接近真实体脂。不要仅凭某一次结果选择 ADC，也不要把对照统计当作医学准确性验证。

观察长期趋势时，建议固定使用同一个 ADC，并保持相似的测量条件。

## 已验证硬件

- 广播名称：`AFU-WL-TZ-A1`
- category：`2`
- subtype：`7`
- 服务：`FFB0`
- Notify 特征：`FFB2`

其他型号和固件可能使用不同广播或数据格式。详细逆向记录见 [协议笔记](docs/PROTOCOL.md)。

## 开发环境要求

- Xcode 26.4 或更高版本；
- iOS / iPadOS 18.6 或更高版本；
- Mac Catalyst 构建当前最低对应 macOS 15.6；
- 支持蓝牙低功耗的实体 iPhone、iPad 或 Mac；
- 写入 Apple 健康需要在个人开发团队或正式团队中启用 HealthKit。

模拟器可以用于编译和检查界面，但不能完成真实蓝牙测量。

## 开发者构建与运行

1. 克隆仓库并打开 `体脂秤.xcodeproj`。
2. 选择 App Target，在 **Signing & Capabilities** 中选择自己的 Team。
3. 如有需要，将 Bundle Identifier 改成自己拥有的唯一标识。
4. iPhone/iPad 选择对应真机；Mac 选择 **My Mac (Mac Catalyst)** 并运行。
5. 完全退出其他设备上的蚂蚁阿福；如果秤仍被占用，可以关闭那些设备的蓝牙。不要关闭正在运行本 App 的设备蓝牙。
6. 光脚站上秤将其唤醒，在配对页选择发现的设备。

如果秤无法出现，请依次确认：

- 系统设置中已允许本 App 使用蓝牙；
- 厂商 App、另一台手机和电脑端 CLI 均未连接；
- 秤已经亮屏并靠近设备；
- 广播名称和 subtype 与上面的已验证设备一致。

## Apple 健康

Apple 健康功能仅在 iPhone/iPad 版显示。Mac 版不支持访问 HealthKit，测量结果只写入 Mac 上的 App 本地历史。

在“我的资料 → Apple 健康”中启用同步并选择指标。App 只自动写入归属于“本人”的新实时测量，不会批量上传旧历史或家庭成员记录。

体重属于直接测量；BMI、体脂率和去脂体重包含本地公式计算。HealthKit 样本会携带算法版本、阻抗和 ADC 编号等元数据，用于之后追溯。

在“我的资料 → 跨体重秤数据”中，可以授权读取体重、BMI、体脂率和去脂体重，查看记录来自哪个 App。疑似重复规则为：不同来源在 5 分钟内写入、体重相差不超过 0.1 kg。检测只作提示，不会修改 Apple 健康。

## 隐私

资料和历史全部保存在 App 沙盒中，不上传测量数据。Mac 检查更新仅会访问 GitHub 的公开版本信息。启用 Apple 健康后，所选数据会交给 HealthKit，是否通过 iCloud 同步由用户的系统设置决定。完整说明见 [PRIVACY.md](docs/PRIVACY.md)。

Mac 测试包使用 `bash scripts/package-mac.sh` 生成，输出到 `dist/`。朋友无需 Xcode，安装说明见 [MAC_INSTALL.md](docs/MAC_INSTALL.md)。当前支持检查更新和下载页入口，安装仍需手动覆盖。


Android 版暂未实现，已确定的 BLE、本地存储和 Health Connect 移植方法见 [Android 实现路线](docs/ANDROID_PORT.md)。

## 项目结构

```text
体脂秤/
├── App/                    # App 入口与根界面
├── Models/                 # 测量、成员与 ADC 对照数据模型
├── Services/               # 蓝牙、HealthKit、用户资料、算法与 OCR
├── Views/                  # 所有 SwiftUI 功能页面与共用组件
├── Assets.xcassets/        # 图标与颜色资源
├── 体脂秤.entitlements      # iOS/iPadOS HealthKit entitlement
└── 体脂秤Mac.entitlements   # macOS 蓝牙沙盒权限
docs/
├── ANDROID_PORT.md         # Android 移植方法
├── CHANGELOG.md            # 更新日志
├── PRIVACY.md              # 隐私说明
└── PROTOCOL.md             # AFU-WL 协议逆向笔记
```

## 构建检查

```bash
xcodebuild \
  -project "体脂秤.xcodeproj" \
  -scheme "体脂秤" \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Mac Catalyst 无签名构建：

```bash
xcodebuild \
  -project "体脂秤.xcodeproj" \
  -scheme "体脂秤" \
  -destination "generic/platform=macOS,variant=Mac Catalyst" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

GitHub Actions 会在 Push 和 Pull Request 时执行相同的无签名构建。

## 贡献

欢迎提交兼容性修复和脱敏后的协议样本。请避免：

- 把真实健康数据、设备 UUID 或 Apple 开发团队信息提交到仓库；
- 把估算指标描述成医疗测量；
- 在没有对照数据时修改生产公式或默认 ADC。

## 许可证

本修改版已取得上游作者授权，并按照 [GNU General Public License v3.0](LICENSE) 发布。

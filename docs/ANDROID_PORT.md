# Android 版实现路线（暂不开发）

## 结论

可以做，而且不需要再逆向一遍秤的协议。最稳妥的第一版是用 **Kotlin + Jetpack Compose** 做原生 Android App，把现有 Swift 项目中的协议解析、测量状态机和身体算法逐段移植。不建议第一版就上 Flutter 或 Kotlin Multiplatform：这个项目最容易出问题的是平台蓝牙行为，原生 API 最容易排查。

Android 版可先只做与 Mac 版相同的闭环：

1. 前台扫描并连接 `AFU-WL-TZ-A1`；
2. 接收实时体重、稳定包和双 ADC；
3. 本地计算并展示结果；
4. 用 Room 保存个人资料、设备标识和测量历史；
5. 稳定后再可选接入 Health Connect。

## BLE 实现方法

- Android 12 / API 31 及以上申请 `BLUETOOTH_SCAN` 和 `BLUETOOTH_CONNECT`。
- Android 11 及以下按系统要求申请蓝牙和定位权限。
- 使用 `BluetoothLeScanner` 前台扫描。与当前 iOS/CLI 一致，不先用 `FFB0` 服务 UUID 限制扫描，而是收到广播后再筛选：
  - 名称以 `AFU-WL` 开头；
  - 从 manufacturer data 或 service data 重建 `0xAC` 包；
  - 确认 `category=2` 且 `subtype=7`。
- 用 `BluetoothGatt` 连接，发现 `FFB0` 服务，订阅 `FFB2` Notify 特征及其 CCCD。
- 将 `AFUPacket.swift` 的 D5/D6/D8/DF 解析按位移、端序和校验规则直接改写为纯 Kotlin，并用相同的脱敏原始包做单元测试。
- 测量状态机沿用现有规则：同一次上秤必须同时得到稳定体重和有效 ADC，离秤后才能保存下一条。

Android 官方对 Android 12+的近距蓝牙权限有单独说明；如果声明 `neverForLocation`，系统可能过滤某些 BLE 广播，因此需要用真秤验证后再决定是否使用该标志：

- [Android Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [Android 12 Bluetooth behavior changes](https://developer.android.com/about/versions/12/behavior-changes-12#bluetooth-permissions)

## 建议的项目结构

```text
android/
├── app/                 # Compose UI 和导航
├── protocol/            # 纯 Kotlin AFU 包解析，不依赖 Android
├── bluetooth/           # 扫描、GATT、重连和测量状态机
├── domain/              # 测量模型、双 ADC 与身体算法
├── data/                # Room 数据库与 JSON 备份
└── healthconnect/       # 后续可选，不影响基础测量
```

`protocol/` 应该从 Android framework 中独立，这样以后如果真的需要 Kotlin Multiplatform，才有可能与 iOS 共享协议和算法。

## Health Connect（可选第二阶段）

Health Connect 可直接保存 `WeightRecord`、`BodyFatRecord`、`LeanBodyMassRecord`、`BodyWaterMassRecord` 和 `BoneMassRecord`。它没有对应 Apple Health BMI 样本的常用独立 BMI 记录，BMI 可留在 App 内根据身高和体重计算。

每条写入记录应使用本地测量 UUID 作为 `clientRecordId`，并标注 `Device.TYPE_SCALE`、厂商和型号。这样可以去重、更新，也能在用户删除本地测量时删除关联的 Health Connect 记录。

- [Health Connect 数据类型](https://developer.android.com/health-and-fitness/guides/health-connect/data-types)
- [Health Connect 数据同步](https://developer.android.com/health-and-fitness/guides/health-connect/sync-data)
- [Health Connect 写入指南](https://developer.android.com/health-and-fitness/guides/health-connect/write-data)

## 实际开发顺序

1. 先做纯 Kotlin 包解析和现有样本回归测试。
2. 再做扫描页和 GATT 日志，用实体 Android 手机确认能收到两类数据包。
3. 移植测量状态机、双 ADC 选择和算法。
4. 用 Room 完成本地历史和删除。
5. 最后再做 Compose UI 打磨和可选 Health Connect。

第一个技术验收点不是界面，而是：**Android 真机能稳定扫到秤、连接 FFB0/FFB2，并用同一份原始包得到与 iOS/CLI 一致的体重和双 ADC。**

---

## English summary

An Android version is feasible without reverse-engineering the scale again. The recommended first implementation is native Kotlin with Jetpack Compose: port the packet parser into a framework-independent Kotlin module, use `BluetoothLeScanner` and `BluetoothGatt` for `FFB0`/`FFB2`, preserve the existing measurement-session rules, and store profiles and measurements in Room. Add Health Connect only after the BLE path is reliable. Use each local measurement UUID as the Health Connect `clientRecordId` so updates and deletions remain traceable.

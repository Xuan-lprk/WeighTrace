import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profile: UserProfile
    @EnvironmentObject private var scale: ScaleManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AppPageHeader(title: "我的空间", subtitle: "资料、设备和数据，各就其位。")
                    HStack(spacing: 18) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 54))
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("本人").font(.title2.bold())
                            Text("身高 \(Int(profile.height)) cm").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(scale.history.count)").font(.system(.title, design: .rounded, weight: .bold))
                            Text("已保存记录").font(.caption).foregroundStyle(.secondary)
                        }
                    }.appCard(padding: 24)
                    Text("日常设置").font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .leading)], spacing: 14) {
                        AppRouteCard(title: "个人资料", subtitle: "用于估算的基础资料", icon: "person.text.rectangle") {
                            ProfileSettingsView(category: .personal)
                        }
                        AppRouteCard(title: "我的设备", subtitle: "连接管理与软件更新", icon: "scalemass") {
                            ProfileSettingsView(category: .device)
                        }
                        AppRouteCard(title: "家庭成员", subtitle: "管理一起使用体脂秤的人", icon: "person.2") {
                            ProfileSettingsView(category: .family)
                        }
                        AppRouteCard(title: "阻抗选择", subtitle: "默认 ADC 与估算说明", icon: "waveform.path") {
                            ProfileSettingsView(category: .algorithm)
                        }
                    }
                    Text("数据与隐私").font(.title3.bold())
                    AppRouteCard(title: "备份与导出", subtitle: "完整备份、恢复与分析表", icon: "externaldrive") { BackupView() }
                        .disabled(scale.isDemo)
#if !targetEnvironment(macCatalyst)
                    AppRouteCard(title: "Apple 健康", subtitle: "同步权限、数据来源与恢复", icon: "heart") {
                        ProfileSettingsView(category: .health)
                    }
#endif
                    AppRouteCard(title: "说明", subtitle: "本地存储与估算边界", icon: "lock.shield") {
                        ProfileSettingsView(category: .about)
                    }
                    Text("更多").font(.title3.bold())
                    AppRouteCard(title: "调试日志", subtitle: "查看连接与测量过程", icon: "terminal") {
                        ProfileSettingsView(category: .debug)
                    }
                    AppRouteCard(title: "显示与演示", subtitle: "语言与独立演示数据", icon: "globe") {
                        ProfileSettingsView(category: .display)
                    }
                }.padding(24).appContentWidth(980)
            }.appScreenBackground().navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacUpdateSection: View {
    @StateObject private var updater = MacUpdateChecker()
    @AppStorage(MacUpdateChecker.automaticKey) private var automaticallyCheck = false
    private var currentVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "—") (\(info?["CFBundleVersion"] as? String ?? "—"))"
    }

    var body: some View {
        Section {
            LabeledContent("当前版本", value: currentVersion)
            Toggle("自动检查更新", isOn: $automaticallyCheck)
            Button("检查更新") { Task { await updater.check() } }
                .disabled(updater.isChecking)
            if !updater.status.isEmpty {
                Text(updater.status).font(.caption).foregroundStyle(.secondary)
            }
            if let detail = updater.errorDetail {
                Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Link("打开 GitHub 发布页", destination: MacUpdateChecker.releasesURL)
            }
            if let url = updater.downloadURL {
                Link("下载新版本", destination: url)
            }
        } header: {
            Text("软件更新")
        } footer: {
            Text("检查更新会连接 GitHub，不发送测量数据。下载后需手动覆盖安装。")
        }
        .task { await updater.checkAutomaticallyIfNeeded() }
        .onChange(of: automaticallyCheck) { _, enabled in
            if enabled { Task { await updater.checkAutomaticallyIfNeeded() } }
        }
    }
}
#endif

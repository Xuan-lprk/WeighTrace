#if targetEnvironment(macCatalyst)
import Foundation
import Combine

/// Checks only the public release listing; never includes measurement data.
@MainActor
final class MacUpdateChecker: ObservableObject {
    static let automaticKey = "xuanlprk.mac.automaticUpdateChecks"
    @Published private(set) var isChecking = false
    @Published private(set) var status = ""
    @Published private(set) var downloadURL: URL?
    @Published private(set) var errorDetail: String?
    static let releasesURL = URL(string: "https://github.com/Xuan-lprk/WeighTrace/releases")!
    private var lastAutomaticCheck = Date.distantPast

    func checkAutomaticallyIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: Self.automaticKey),
              Date().timeIntervalSince(lastAutomaticCheck) > 86_400 else { return }
        lastAutomaticCheck = Date()
        await check()
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        downloadURL = nil
        errorDetail = nil
        status = String(appLocalized: "正在检查更新…")
        defer { isChecking = false }
        do {
            let url = URL(string: "https://api.github.com/repos/Xuan-lprk/WeighTrace/releases?per_page=30")!
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard http.statusCode == 200 else {
                errorDetail = "GitHub API HTTP \(http.statusCode)" + (http.statusCode == 403 || http.statusCode == 429 ? " · " + String(appLocalized: "请求可能受到限流，请稍后重试或打开发布页。") : "")
                throw URLError(.badServerResponse)
            }
            let releases = try JSONDecoder().decode([MacRelease].self, from: data)
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let build = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
            let installed = MacRelease.Version(number: current, build: build)
            let newer = releases.filter { $0.packageVersion?.isNewer(than: installed) == true }
                .sorted { $0.packageVersion!.isNewer(than: $1.packageVersion!) }
            guard let release = newer.first else {
                status = String(appLocalized: "暂无可用的 Mac 新版本")
                return
            }
            guard release.html_url.scheme == "https", release.html_url.host == "github.com",
                  release.html_url.path.hasPrefix("/Xuan-lprk/WeighTrace/releases/") else {
                throw URLError(.badURL)
            }
            downloadURL = release.html_url
            status = String(appLocalized: "发现新版本") + " " + release.tag_name
        } catch {
            status = String(appLocalized: "检查更新失败，请稍后重试")
            if errorDetail == nil {
                let failure = error as NSError
                errorDetail = "\(failure.localizedDescription) (\(failure.domain) \(failure.code))"
            }
        }
    }
}
#endif

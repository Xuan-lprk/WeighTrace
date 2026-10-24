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
    private var lastAutomaticCheck = Date.distantPast

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable { let name: String }

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
        status = String(appLocalized: "正在检查更新…")
        defer { isChecking = false }
        do {
            let url = URL(string: "https://api.github.com/repos/Xuan-lprk/smart-body-scale-IOS/releases?per_page=30")!
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let available = releases.filter {
                !$0.draft && !$0.prerelease &&
                $0.assets.contains { $0.name.hasPrefix("AFU-Scale-Mac-") && $0.name.hasSuffix(".dmg") }
            }
            let newer = available.filter {
                let version = $0.tag_name.hasPrefix("v") ? String($0.tag_name.dropFirst()) : $0.tag_name
                return version.range(of: #"^\d+(\.\d+){1,2}$"#, options: .regularExpression) != nil &&
                    version.compare(current, options: .numeric) == .orderedDescending
            }.sorted { $0.tag_name.compare($1.tag_name, options: .numeric) == .orderedDescending }
            guard let release = newer.first else {
                status = String(appLocalized: "暂无可用的 Mac 新版本")
                return
            }
            guard release.html_url.scheme == "https", release.html_url.host == "github.com",
                  release.html_url.path.hasPrefix("/Xuan-lprk/smart-body-scale-IOS/releases/") else {
                throw URLError(.badURL)
            }
            downloadURL = release.html_url
            status = String(appLocalized: "发现新版本") + " " + release.tag_name
        } catch {
            status = String(appLocalized: "检查更新失败，请稍后重试")
        }
    }
}
#endif

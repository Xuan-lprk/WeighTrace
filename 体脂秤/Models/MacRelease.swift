import Foundation

struct MacRelease: Decodable {
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    struct Asset: Decodable { let name: String }

    struct Version: Equatable {
        let number: String
        let build: Int
        func isNewer(than other: Version) -> Bool {
            let order = number.compare(other.number, options: .numeric)
            return order == .orderedDescending || (order == .orderedSame && build > other.build)
        }
    }

    var packageVersion: Version? {
        guard !draft, !prerelease else { return nil }
        // Prefer the package version to tags: early releases used V1.6.9 for
        // a 1.6 (9) binary, and another release was simply tagged "Release".
        return assets.compactMap { asset -> Version? in
            let pattern = #"^(?:AFU-Scale-Mac-|WeighTrace-?)(\d+(?:\.\d+){1,2})-(\d+)(?:-test)?\.dmg$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: asset.name, range: NSRange(asset.name.startIndex..., in: asset.name)),
                  let versionRange = Range(match.range(at: 1), in: asset.name),
                  let buildRange = Range(match.range(at: 2), in: asset.name),
                  let build = Int(asset.name[buildRange]) else { return nil }
            return Version(number: String(asset.name[versionRange]), build: build)
        }.sorted { $0.isNewer(than: $1) }.first
    }
}

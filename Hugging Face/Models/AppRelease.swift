import Foundation

struct ReleaseVersion: Comparable {
    let components: [Int]

    init?(_ string: String) {
        let value = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.map { Int($0)! }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }

    var description: String { components.map(String.init).joined(separator: ".") }
}

struct AppRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    var version: ReleaseVersion? { ReleaseVersion(tag_name) }

    var installAssets: (image: URL, checksum: URL)? {
        guard !draft, !prerelease, let version else { return nil }
        let name = "Hugging-Face-\(version.description).dmg"
        let prefix = "https://github.com/ehcalabres/Hugging-Face-MacOS/releases/download/\(tag_name)/"
        guard let image = assets.first(where: { $0.name == name }),
              let checksum = assets.first(where: { $0.name == name + ".sha256" }),
              image.browser_download_url.absoluteString == prefix + name,
              checksum.browser_download_url.absoluteString == prefix + name + ".sha256" else { return nil }
        return (image.browser_download_url, checksum.browser_download_url)
    }
}

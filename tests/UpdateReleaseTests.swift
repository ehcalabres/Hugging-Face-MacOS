import Foundation

@main
struct UpdateReleaseTests {
    static func main() throws {
        assert(ReleaseVersion("v0.1.10")! > ReleaseVersion("0.1.9")!)
        assert(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!)
        assert(ReleaseVersion("v1.2.3")! == ReleaseVersion("1.2.3")!)
        for invalid in ["", "1.2", "1.2.3.4", "1.2.3-beta", "-1.2.3", "1..3", "1.2.99999999999999999999999"] {
            assert(ReleaseVersion(invalid) == nil, invalid)
        }
        let prefix = "https://github.com/ehcalabres/Hugging-Face-MacOS/releases/download/v1.2.3/"
        func release(prerelease: Bool = false, draft: Bool = false, host: String = prefix, checksum: Bool = true) throws -> AppRelease {
            let name = "Hugging-Face-1.2.3.dmg"
            var assets = [["name": name, "browser_download_url": host + name]]
            if checksum { assets.append(["name": name + ".sha256", "browser_download_url": host + name + ".sha256"]) }
            let data = try JSONSerialization.data(withJSONObject: [
                "tag_name": "v1.2.3", "draft": draft, "prerelease": prerelease, "assets": assets
            ])
            return try JSONDecoder().decode(AppRelease.self, from: data)
        }
        let valid = try release()
        assert(valid.installAssets != nil)
        let invalidReleases = try [release(prerelease: true), release(draft: true), release(checksum: false), release(host: "https://example.com/")]
        assert(invalidReleases.allSatisfy { $0.installAssets == nil })
        print("Release version and asset validation checks passed")
    }
}

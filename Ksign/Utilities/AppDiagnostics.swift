import Foundation

struct AppDiagnostics {
    let bundleSize: Int64
    let executableSize: Int64
    let frameworks: [String]
    let dylibs: [String]
    let extensions: [String]
    let urlSchemes: [String]
    let privacyManifestCount: Int
    let hasProvisioningProfile: Bool
    let warnings: [String]

    static func inspect(_ app: AppInfoPresentable) -> AppDiagnostics? {
        guard let root = Storage.shared.getUuidDirectory(for: app),
              let appURL = FileManager.default.getPath(in: root, for: "app") else { return nil }

        let fm = FileManager.default
        let bundle = Bundle(url: appURL)
        let info = bundle?.infoDictionary ?? [:]
        let executableURL = bundle?.executableURL

        var total: Int64 = 0
        var frameworks: [String] = []
        var dylibs: [String] = []
        var extensions: [String] = []
        var privacyCount = 0

        if let enumerator = fm.enumerator(at: appURL, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
                switch url.pathExtension.lowercased() {
                case "framework": frameworks.append(url.lastPathComponent)
                case "dylib": dylibs.append(url.lastPathComponent)
                case "appex": extensions.append(url.deletingPathExtension().lastPathComponent)
                case "xcprivacy": privacyCount += 1
                default: break
                }
            }
        }

        let schemes = ((info["CFBundleURLTypes"] as? [[String: Any]]) ?? [])
            .flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
            .sorted()

        let executableSize = Int64((try? executableURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let hasProvision = fm.fileExists(atPath: appURL.appendingPathComponent("embedded.mobileprovision").path)
        var warnings: [String] = []
        if bundle?.bundleIdentifier == nil { warnings.append("Missing bundle identifier") }
        if bundle?.executableURL == nil { warnings.append("Main executable could not be located") }
        if hasProvision { warnings.append("Embedded provisioning profile will be replaced or removed when signing") }
        if privacyCount == 0 { warnings.append("No PrivacyInfo.xcprivacy manifest was found") }

        return AppDiagnostics(
            bundleSize: total,
            executableSize: executableSize,
            frameworks: Array(Set(frameworks)).sorted(),
            dylibs: Array(Set(dylibs)).sorted(),
            extensions: Array(Set(extensions)).sorted(),
            urlSchemes: schemes,
            privacyManifestCount: privacyCount,
            hasProvisioningProfile: hasProvision,
            warnings: warnings
        )
    }
}

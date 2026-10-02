import Foundation

/// Read-only inspection of an installed/imported .app bundle.
struct IPAInspection {
    let bundleIdentifier: String?
    let displayName: String?
    let version: String?
    let build: String?
    let minimumOS: String?
    let architectures: [String]
    let entitlements: [String: String]
    let frameworks: [String]
    let dylibs: [String]
    let extensions: [String]
    let bundleSize: Int64
    let executableSize: Int64
    let hasProvisioningProfile: Bool
    let privacyManifestCount: Int
    let urlSchemes: [String]
    let warnings: [String]

    var architectureSummary: String { architectures.isEmpty ? String(localized: "Unknown") : architectures.joined(separator: ", ") }

    static func inspect(_ app: AppInfoPresentable) -> IPAInspection? {
        guard let root = Storage.shared.getUuidDirectory(for: app),
              let appURL = FileManager.default.getPath(in: root, for: "app") else { return nil }
        return inspect(bundleURL: appURL)
    }

    static func inspect(bundleURL appURL: URL) -> IPAInspection? {
        let fm = FileManager.default
        guard let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Info.plist")) as? [String: Any] else { return nil }
        let executableName = info["CFBundleExecutable"] as? String
        let executableURL = executableName.map { appURL.appendingPathComponent($0) }
        var total: Int64 = 0
        var frameworks: [String] = [], dylibs: [String] = [], extensions: [String] = []
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
            .flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }.sorted()
        let profileURL = appURL.appendingPathComponent("embedded.mobileprovision")
        let hasProfile = fm.fileExists(atPath: profileURL.path)
        var entitlements: [String: String] = [:]
        if hasProfile, let profile = Storage.shared.decodeProvisioningProfile(at: profileURL), let values = profile.Entitlements {
            for (key, value) in values { entitlements[key] = String(describing: value.value) }
        }
        var warnings: [String] = []
        if info["CFBundleIdentifier"] == nil { warnings.append(String(localized: "Missing bundle identifier")) }
        if executableURL == nil || !fm.fileExists(atPath: executableURL!.path) { warnings.append(String(localized: "Main executable could not be located")) }
        if hasProfile { warnings.append(String(localized: "The embedded provisioning profile will be replaced when signing")) }
        if privacyCount == 0 { warnings.append(String(localized: "No PrivacyInfo.xcprivacy manifest was found")) }
        if entitlements.keys.contains(where: { $0 == "com.apple.developer.ubiquity-container-identifiers" || $0.contains("push") }) {
            warnings.append(String(localized: "This app requests capabilities that may not work after re-signing"))
        }
        return IPAInspection(
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            displayName: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String),
            version: info["CFBundleShortVersionString"] as? String,
            build: info["CFBundleVersion"] as? String,
            minimumOS: (info["MinimumOSVersion"] as? String) ?? (info["LSMinimumSystemVersion"] as? String),
            architectures: MachOArchitectureReader.architectures(at: executableURL),
            entitlements: entitlements,
            frameworks: Array(Set(frameworks)).sorted(),
            dylibs: Array(Set(dylibs)).sorted(),
            extensions: Array(Set(extensions)).sorted(),
            bundleSize: total,
            executableSize: Int64((try? executableURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
            hasProvisioningProfile: hasProfile,
            privacyManifestCount: privacyCount,
            urlSchemes: schemes,
            warnings: warnings
        )
    }
}

/// Minimal Mach-O/fat-binary reader. It intentionally does not execute untrusted code.
enum MachOArchitectureReader {
    static func architectures(at url: URL?) -> [String] {
        guard let url, let data = try? Data(contentsOf: url), data.count >= 4 else { return [] }
        func u32(_ offset: Int) -> UInt32 { data[offset..<offset+4].reduce(0) { ($0 << 8) | UInt32($1) } }
        let magic = u32(0)
        if magic == 0xcafebabe || magic == 0xcafebabf {
            guard data.count >= 8 else { return [] }
            let count = Int(u32(4)); var result: [String] = []
            for index in 0..<min(count, 32) {
                let offset = 8 + index * (magic == 0xcafebabf ? 32 : 20)
                guard offset + 4 <= data.count else { break }
                result.append(name(for: u32(offset)))
            }
            return Array(Set(result)).sorted()
        }
        let cpu = data[4..<8].withUnsafeBytes { raw -> UInt32 in
            var value: UInt32 = 0
            for (index, byte) in raw.enumerated() { value |= UInt32(byte) << UInt32(index * 8) }
            return value
        }
        return [name(for: cpu)]
    }
    private static func name(for cpu: UInt32) -> String {
        switch cpu & 0x00ffffff { case 7: return "i386"; case 12: return "arm"; case 0x100000c: return "arm64"; case 0x1000007: return "x86_64"; default: return String(cpu, radix: 16, uppercase: true) }
    }
}

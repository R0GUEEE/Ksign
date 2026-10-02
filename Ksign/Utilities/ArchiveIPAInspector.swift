import Foundation
import ZIPFoundation

struct ArchiveIPAInspector {
    static func inspect(ipaURL: URL) throws -> IPAInspection {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("KsignInspect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let archive = try Archive(url: ipaURL, accessMode: .read)
        let entries = Array(archive)
        guard let appEntry = entries.first(where: { $0.path.hasPrefix("Payload/") && $0.path.hasSuffix(".app/Info.plist") }) else { throw NSError(domain: "Ksign", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "The IPA does not contain a valid Payload app")]) }
        let appPath = appEntry.path.dropLast("/Info.plist".count)
        for entry in entries where entry.path.hasPrefix(String(appPath)) {
            let destination = temp.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if entry.type == .file { _ = try archive.extract(entry, to: destination) }
        }
        guard let inspection = IPAInspection.inspect(bundleURL: temp.appendingPathComponent(String(appPath))) else {
            throw NSError(domain: "Ksign", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "The app bundle is missing a readable Info.plist")])
        }
        return inspection
    }
}

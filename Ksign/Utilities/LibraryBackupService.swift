import Foundation
import UIKit
import CoreData
import ZIPFoundation

struct LibraryBackupCertificate: Codable {
    let id: String
    let nickname: String?
    let password: String?
    let expiration: Date
    let ppqCheck: Bool
    let p12Path: String
    let provisionPath: String
}

struct LibraryBackupApp: Codable {
    let uuid: String
    let signed: Bool
    let source: URL?
    let date: Date
    let name: String?
    let identifier: String?
    let version: String?
    let icon: String?
    let userTitle: String?
    let userNotes: String?
    let userTags: [String]
    let isFavorite: Bool
    let certificateID: String?
    let payloadPath: String
}

struct LibraryBackupSource: Codable {
    let identifier: String
    let name: String?
    let sourceURL: URL?
    let iconURL: URL?
    let date: Date
    let isBuiltIn: Bool
}

struct LibraryBackupManifest: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let signingOptions: Options
    let signingProfiles: [SigningProfile]
    let certificates: [LibraryBackupCertificate]
    let apps: [LibraryBackupApp]
    let sources: [LibraryBackupSource]
}

enum LibraryBackupService {
    enum Error: Swift.Error, LocalizedError {
        case invalidArchive
        case unsupportedVersion(Int)
        case missingPayload(String)
        var errorDescription: String? {
            switch self {
            case .invalidArchive: return String(localized: "The backup archive is invalid.")
            case .unsupportedVersion(let version): return "Unsupported Ksign backup version \(version)."
            case .missingPayload(let path): return "The backup is missing payload \(path)."
            }
        }
    }

    static func makeArchive() throws -> URL {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent("KsignBackup-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let manifestURL = staging.appendingPathComponent("manifest.json")
        var certificates: [LibraryBackupCertificate] = []
        var apps: [LibraryBackupApp] = []
        var sources: [LibraryBackupSource] = []

        for cert in try Storage.shared.allCertificates() {
            guard let id = cert.uuid,
                  let p12 = Storage.shared.getFile(.certificate, from: cert),
                  let provision = Storage.shared.getFile(.provision, from: cert) else { continue }
            let p12Path = "certificates/\(id)/certificate.p12"
            let provisionPath = "certificates/\(id)/profile.mobileprovision"
            let decoded = Storage.shared.getProvisionFileDecoded(for: cert)
            certificates.append(LibraryBackupCertificate(id: id, nickname: cert.nickname, password: cert.password,
                expiration: cert.expiration ?? decoded?.ExpirationDate ?? Date(), ppqCheck: cert.ppQCheck == true,
                p12Path: p12Path, provisionPath: provisionPath))
            try copy(p12, to: staging.appendingPathComponent(p12Path))
            try copy(provision, to: staging.appendingPathComponent(provisionPath))
        }

        let imported = try Storage.shared.context.fetch(Imported.fetchRequest())
        for app in imported {
            if let record = try appRecord(app, signed: false, staging: staging) { apps.append(record) }
        }
        let signed = try Storage.shared.context.fetch(Signed.fetchRequest())
        for app in signed {
            if let record = try appRecord(app, signed: true, staging: staging) { apps.append(record) }
        }
        let altSources = try Storage.shared.context.fetch(AltSource.fetchRequest())
        sources = altSources.compactMap { source in
            guard let identifier = source.identifier else { return nil }
            return LibraryBackupSource(identifier: identifier, name: source.name, sourceURL: source.sourceURL,
                iconURL: source.iconURL, date: source.date ?? Date(), isBuiltIn: source.isBuiltIn)
        }

        let manifest = LibraryBackupManifest(formatVersion: 2, exportedAt: Date(), signingOptions: OptionsManager.shared.options,
            signingProfiles: OptionsManager.shared.profiles, certificates: certificates, apps: apps, sources: sources)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        let output = fileManager.temporaryDirectory.appendingPathComponent("Ksign-library-\(Int(Date().timeIntervalSince1970)).ksignbackup")
        try archive(staging, to: output)
        return output
    }

    static func restoreArchive(from url: URL, completion: @escaping (Result<Int, Swift.Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileManager = FileManager.default
                let staging = fileManager.temporaryDirectory.appendingPathComponent("KsignRestore-\(UUID().uuidString)", isDirectory: true)
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? fileManager.removeItem(at: staging) }
                let archive = try Archive(url: url, accessMode: .read)
                for entry in archive {
                    let destination = staging.appendingPathComponent(entry.path)
                    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if entry.type == .file { _ = try archive.extract(entry, to: destination) }
                }
                let manifestURL = staging.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifestURL) else { throw Error.invalidArchive }
                let manifest = try JSONDecoder().decode(LibraryBackupManifest.self, from: data)
                guard manifest.formatVersion == 2 else { throw Error.unsupportedVersion(manifest.formatVersion) }
                DispatchQueue.main.async {
                    do {
                        let count = try apply(manifest, staging: staging)
                        completion(.success(count))
                    } catch {
                        completion(.failure(error))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func appRecord(_ app: NSManagedObject, signed: Bool, staging: URL) throws -> LibraryBackupApp? {
        guard let uuid = app.value(forKey: "uuid") as? String else { return nil }
        let sourceURL = signed ? FileManager.default.signed(uuid) : FileManager.default.unsigned(uuid)
        let payloadPath = "apps/\(signed ? "signed" : "imported")/\(uuid)"
        let destination = staging.appendingPathComponent(payloadPath)
        try copyDirectory(sourceURL, to: destination)
        let certificateID = (app.value(forKey: "certificate") as? CertificatePair)?.uuid
        return LibraryBackupApp(uuid: uuid, signed: signed, source: app.value(forKey: "source") as? URL,
            date: app.value(forKey: "date") as? Date ?? Date(), name: app.value(forKey: "name") as? String,
            identifier: app.value(forKey: "identifier") as? String, version: app.value(forKey: "version") as? String,
            icon: app.value(forKey: "icon") as? String, userTitle: app.value(forKey: "userTitle") as? String,
            userNotes: app.value(forKey: "userNotes") as? String, userTags: app.value(forKey: "userTags") as? [String] ?? [],
            isFavorite: app.value(forKey: "isFavorite") as? Bool ?? false, certificateID: certificateID, payloadPath: payloadPath)
    }

    @MainActor private static func apply(_ manifest: LibraryBackupManifest, staging: URL) throws -> Int {
        OptionsManager.shared.options = manifest.signingOptions
        OptionsManager.shared.saveOptions()
        OptionsManager.shared.replaceProfiles(manifest.signingProfiles)
        var certificatesByID: [String: CertificatePair] = [:]
        for item in manifest.certificates {
            let directory = FileManager.default.certificates(item.id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let p12 = directory.appendingPathComponent("p12")
            let profile = directory.appendingPathComponent("mobileprovision")
            try copy(staging.appendingPathComponent(item.p12Path), to: p12)
            try copy(staging.appendingPathComponent(item.provisionPath), to: profile)
            let existing = try Storage.shared.context.fetch(CertificatePair.fetchRequest()).first { $0.uuid == item.id }
            let cert = existing ?? CertificatePair(context: Storage.shared.context)
            cert.uuid = item.id; cert.nickname = item.nickname; cert.password = item.password
            cert.expiration = item.expiration; cert.ppQCheck = item.ppqCheck; cert.date = cert.date ?? Date()
            certificatesByID[item.id] = cert
        }
        var restored = 0
        for item in manifest.apps {
            let root = item.signed ? FileManager.default.signed(item.uuid) : FileManager.default.unsigned(item.uuid)
            try copyDirectory(staging.appendingPathComponent(item.payloadPath), to: root)
            let request: NSFetchRequest<NSManagedObject> = item.signed ? Signed.fetchRequest() as! NSFetchRequest<NSManagedObject> : Imported.fetchRequest() as! NSFetchRequest<NSManagedObject>
            let object = try Storage.shared.context.fetch(request).first { $0.value(forKey: "uuid") as? String == item.uuid } ?? (item.signed ? Signed(context: Storage.shared.context) : Imported(context: Storage.shared.context))
            object.setValue(item.uuid, forKey: "uuid"); object.setValue(item.source, forKey: "source"); object.setValue(item.date, forKey: "date")
            object.setValue(item.name, forKey: "name"); object.setValue(item.identifier, forKey: "identifier"); object.setValue(item.version, forKey: "version"); object.setValue(item.icon, forKey: "icon")
            object.setValue(item.userTitle, forKey: "userTitle"); object.setValue(item.userNotes, forKey: "userNotes"); object.setValue(item.userTags, forKey: "userTags"); object.setValue(item.isFavorite, forKey: "isFavorite")
            if item.signed { object.setValue(item.certificateID.flatMap { certificatesByID[$0] }, forKey: "certificate") }
            restored += 1
        }
        for source in manifest.sources {
            guard let sourceURL = source.sourceURL, !Storage.shared.sourceExists(source.identifier) else { continue }
            Storage.shared.addSource(sourceURL, name: source.name, identifier: source.identifier, iconURL: source.iconURL, isBuiltIn: source.isBuiltIn) { _ in }
        }
        Storage.shared.saveContext()
        return restored
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
    private static func copyDirectory(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { throw Error.missingPayload(source.path) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
    private static func archive(_ directory: URL, to output: URL) throws {
        let archive = try Archive(url: output, accessMode: .create)
        try archive.addEntry(with: "manifest.json", relativeTo: directory)
        for root in ["apps", "certificates"] {
            let folder = directory.appendingPathComponent(root)
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for case let file as URL in enumerator {
                let values = try file.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory != true { try archive.addEntry(with: root + "/" + file.path.replacingOccurrences(of: folder.path + "/", with: ""), relativeTo: folder) }
            }
        }
    }
}

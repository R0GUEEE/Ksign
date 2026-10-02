import Foundation
import UIKit

struct KsignBackup: Codable {
    var formatVersion = 1
    var exportedAt = Date()
    var signingOptions: Options
    var signingProfiles: [SigningProfile]
    var certificateFiles: [BackupCertificate]
}

struct BackupCertificate: Codable {
    let id: String
    let nickname: String?
    let password: String?
    let p12: Data
    let provisioning: Data
}

enum BackupService {
    static func makeBackup() throws -> URL {
        let certs = try Storage.shared.allCertificates().compactMap { cert -> BackupCertificate? in
            guard let id = cert.uuid,
                  let p12 = Storage.shared.getFile(.certificate, from: cert),
                  let provision = Storage.shared.getFile(.provision, from: cert),
                  let p12Data = try? Data(contentsOf: p12), let provisionData = try? Data(contentsOf: provision) else { return nil }
            return BackupCertificate(id: id, nickname: cert.nickname, password: cert.password, p12: p12Data, provisioning: provisionData)
        }
        let backup = KsignBackup(signingOptions: OptionsManager.shared.options, signingProfiles: OptionsManager.shared.profiles, certificateFiles: certs)
        let data = try JSONEncoder().encode(backup)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ksign-backup-\(Int(Date().timeIntervalSince1970)).ksignbackup")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func restore(from url: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let backup = try JSONDecoder().decode(KsignBackup.self, from: Data(contentsOf: url))
                OptionsManager.shared.options = backup.signingOptions
                OptionsManager.shared.replaceProfiles(backup.signingProfiles)
                var count = 0
                for item in backup.certificateFiles {
                    let dir = FileManager.default.certificates(item.id)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let p12URL = dir.appendingPathComponent("p12")
                    let provisionURL = dir.appendingPathComponent("mobileprovision")
                    try item.p12.write(to: p12URL, options: .atomic)
                    try item.provisioning.write(to: provisionURL, options: .atomic)
                    FR.handleCertificateFiles(p12URL: p12URL, provisionURL: provisionURL, p12Password: item.password ?? "", certificateName: item.nickname ?? "") { _ in }
                    count += 1
                }
                DispatchQueue.main.async { completion(.success(count)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
}

extension Storage {
    func allCertificates() throws -> [CertificatePair] {
        try context.fetch(CertificatePair.fetchRequest())
    }
}

import Foundation

/// Stable certificate selection shared by signing, settings, and restore flows.
enum CertificateSelection {
    static let uuidKey = "feather.selectedCertificateUUID"
    static let legacyIndexKey = "feather.selectedCert"

    static func migrateLegacySelection(from certificates: [CertificatePair]) -> String? {
        if let uuid = UserDefaults.standard.string(forKey: uuidKey), !uuid.isEmpty { return uuid }
        let index = UserDefaults.standard.integer(forKey: legacyIndexKey)
        guard certificates.indices.contains(index), let uuid = certificates[index].uuid else { return nil }
        UserDefaults.standard.set(uuid, forKey: uuidKey)
        return uuid
    }

    static func set(_ certificate: CertificatePair) {
        if let uuid = certificate.uuid { UserDefaults.standard.set(uuid, forKey: uuidKey) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: uuidKey)
        UserDefaults.standard.set(0, forKey: legacyIndexKey)
    }
}

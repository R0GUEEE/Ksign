import Foundation

extension Storage {
    /// Decodes the plist payload from a mobileprovision file without logging secrets.
    func decodeProvisioningProfile(at url: URL) -> Certificate? {
        CertificateReader(url).decoded
    }
}

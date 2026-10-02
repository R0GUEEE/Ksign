import Foundation
import SwiftUI
import NimbleViews

struct CertificateHealth: Identifiable {
    let id: String
    let name: String
    let expiration: Date
    let revoked: Bool
    let teamID: String
    let appIDName: String
    let status: Status
    enum Status { case valid, expiring, expired, revoked
        var title: String { switch self { case .valid: String(localized: "Valid"); case .expiring: String(localized: "Expiring Soon"); case .expired: String(localized: "Expired"); case .revoked: String(localized: "Revoked") } }
        var color: Color { switch self { case .valid: .green; case .expiring: .orange; case .expired, .revoked: .red } }
    }
    static func make(_ cert: CertificatePair) -> CertificateHealth? {
        guard let uuid = cert.uuid, let data = Storage.shared.getProvisionFileDecoded(for: cert) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: data.ExpirationDate).day ?? 0
        let status: Status = cert.revoked == true ? .revoked : (data.ExpirationDate < Date() ? .expired : (days <= 14 ? .expiring : .valid))
        return CertificateHealth(id: uuid, name: cert.nickname ?? data.Name, expiration: data.ExpirationDate,
            revoked: cert.revoked, teamID: data.TeamIdentifier.first ?? String(localized: "Unknown"), appIDName: data.AppIDName, status: status)
    }
}

struct CertificateHealthView: View {
    @FetchRequest(entity: CertificatePair.entity(), sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.expiration, ascending: true)], animation: .snappy)
    private var certificates: FetchedResults<CertificatePair>
    var body: some View {
        List {
            Section {
                ForEach(certificates.compactMap(CertificateHealth.make)) { health in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(health.name).font(.headline); Spacer(); Text(health.status.title).foregroundStyle(health.status.color).font(.caption.bold()) }
                        LabeledContent(String(localized: "Team ID"), value: health.teamID)
                        LabeledContent(String(localized: "Expires"), value: health.expiration.formatted(date: .abbreviated, time: .omitted))
                        ProgressView(value: max(0, min(1, health.expiration.timeIntervalSinceNow / (365 * 24 * 3600))))
                            .tint(health.status.color)
                    }.padding(.vertical, 4)
                }
            } header: { Text(String(localized: "Certificate Health")) } footer: {
                Text(String(localized: "Certificates expiring within 14 days are highlighted. Revoke checks are performed from the certificate actions."))
            }
        }
        .navigationTitle(String(localized: "Certificate Health"))
    }
}

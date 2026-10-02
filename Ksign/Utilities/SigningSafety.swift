import Foundation

struct SigningWarning: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let severity: Severity
    enum Severity { case notice, warning, critical }
}

enum SigningSafety {
    static func warnings(options: Options, certificate: CertificatePair?, app: AppInfoPresentable) -> [SigningWarning] {
        var result: [SigningWarning] = []
        if options.doAdhocSigning { result.append(SigningWarning(title: String(localized: "Ad-hoc signing"), detail: String(localized: "This app will not receive a normal provisioning profile."), severity: .warning)) }
        if options.onlyModify { result.append(SigningWarning(title: String(localized: "Modify only"), detail: String(localized: "The resulting app will not be signed by Ksign."), severity: .critical)) }
        if options.removeProvisioning { result.append(SigningWarning(title: String(localized: "Provisioning removal enabled"), detail: String(localized: "The original embedded profile will be removed."), severity: .notice)) }
        if !options.injectionFiles.isEmpty { result.append(SigningWarning(title: String(localized: "Code injection enabled"), detail: String(localized: "Injected files can change app behavior and signing requirements."), severity: .warning)) }
        if let certificate {
            if certificate.revoked == true { result.append(SigningWarning(title: String(localized: "Certificate revoked"), detail: String(localized: "Choose another certificate before signing."), severity: .critical)) }
			if let expiration = certificate.expiration, expiration < Date() { result.append(SigningWarning(title: String(localized: "Certificate expired"), detail: String(localized: "Choose a valid certificate before signing."), severity: .critical)) }
            else if let expiration = certificate.expiration, expiration.timeIntervalSinceNow < 14 * 86400 { result.append(SigningWarning(title: String(localized: "Certificate expires soon"), detail: expiration.formatted(date: .abbreviated, time: .omitted), severity: .warning)) }
            else if certificate.expiration == nil { result.append(SigningWarning(title: String(localized: "Certificate expiration unavailable"), detail: String(localized: "Re-import the provisioning profile."), severity: .warning)) }
            if certificate.ppQCheck == true { result.append(SigningWarning(title: String(localized: "PPQ protection enabled"), detail: String(localized: "The bundle identifier may be modified for this certificate."), severity: .notice)) }
        }
        if app.identifier == nil { result.append(SigningWarning(title: String(localized: "Missing bundle identifier"), detail: String(localized: "Ksign cannot validate identifier compatibility."), severity: .critical)) }
        return result
    }
}

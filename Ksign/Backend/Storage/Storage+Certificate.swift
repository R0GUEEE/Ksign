//
//  Storage+Certificate.swift
//  Feather
//
//  Created by samara on 16.04.2025.
//

import CoreData
import UIKit.UIImpactFeedbackGenerator
import ZsignSwift

// MARK: - Class extension: certificate
extension Storage {
	func addCertificate(
		uuid: String,
		password: String? = nil,
		nickname: String? = nil,
		ppq: Bool = false,
		expiration: Date,
		completion: @escaping (Error?) -> Void
	) {
		let generator = UIImpactFeedbackGenerator(style: .light)
		
		let new = CertificatePair(context: context)
		new.uuid = uuid
		new.date = Date()
		new.password = password
		new.ppQCheck = ppq
		new.expiration = expiration
		new.nickname = nickname
		
        saveContext()
        generator.impactOccurred()
        CertificateExpiryManager.schedule(for: new)
        completion(nil)
	}
    
    func revokagedCertificate(for cert: CertificatePair) {
        guard !cert.revoked else { return }
		print("Checking revokage for \(cert.nickname ?? "Unknown")")
        Zsign.checkRevokage(
            provisionPath: Storage.shared.getFile(.provision, from: cert)?.path ?? "",
            p12Path: Storage.shared.getFile(.certificate, from: cert)?.path ?? "",
            p12Password: cert.password ?? ""
        ) { (status, _, _) in
            if status == 1 {
                DispatchQueue.main.async {
                    cert.revoked = true
                    Storage.shared.saveContext()
                    CertificateExpiryManager.cancel(for: cert)
                }
            }
        }
    }
    
    func getProvisionFileDecoded(for cert: CertificatePair) -> Certificate? {
        guard let url = getFile(.provision, from: cert) else {
            return nil
        }
        
        let read = CertificateReader(url)
        return read.decoded
    }
    
	func deleteCertificate(for cert: CertificatePair) {
		do {
			if cert.p12Data == nil && cert.provisionData == nil {
				if let url = getUuidDirectory(for: cert) {
					try FileManager.default.removeItem(at: url)
				}
			}
			CertificateExpiryManager.cancel(for: cert)
			context.delete(cert)
			saveContext()
		} catch {
			print(error)
		}
	}
	
	/// Renames a certificate — there is otherwise no way to change the
	/// nickname once it has been imported. Passing `nil` or a blank string
	/// clears it, falling back to the provisioning profile's own name.
	func renameCertificate(_ cert: CertificatePair, to nickname: String?) {
		let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
		cert.nickname = (trimmed?.isEmpty ?? true) ? nil : trimmed
		saveContext()
	}
	
	/// The `.p12` + `.mobileprovision` pair backing a certificate, for export.
	/// Certificates are otherwise stranded inside the app's container — which
	/// matters most for a paid certificate that would have to be re-issued
	/// from the developer portal if the app were ever reinstalled.
	func exportFiles(for cert: CertificatePair) -> [URL] {
		[FileRequest.certificate, .provision].compactMap { getFile($0, from: cert) }
	}
	
	enum FileRequest: String {
		case certificate = "p12"
		case provision = "mobileprovision"
	}
	
	func getFile(_ type: FileRequest, from cert: CertificatePair) -> URL? {
		guard let url = getUuidDirectory(for: cert) else {
			return nil
		}
		
		return FileManager.default.getPath(in: url, for: type.rawValue)
	}
	
	func getUuidDirectory(for cert: CertificatePair) -> URL? {
		guard let uuid = cert.uuid else {
			return nil
		}
		
		return FileManager.default.certificates(uuid)
	}
}

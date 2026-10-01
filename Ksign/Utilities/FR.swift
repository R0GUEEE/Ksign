//
//  FR.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import Foundation.NSURL
import UIKit.UIImage
import Zsign
import NimbleJSON
import AltSourceKit
import IDeviceSwift

enum FR {
	static func handlePackageFile(
		_ ipa: URL,
		download: Download? = nil,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = AppFileHandler(file: ipa, download: download)
			
			do {
				try await handler.copy()
				try await handler.extract()
				try await handler.move()
				try await handler.addToDatabase()
                
                                try? await handler.clean()
				await MainActor.run {
					completion(nil)
				}
			} catch {
				try await handler.clean()
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	static func signPackageFile(
		_ app: AppInfoPresentable,
		using options: Options,
		icon: UIImage?,
		certificate: CertificatePair?,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = SigningHandler(app: app, options: options)
			if !options.onlyModify {
				handler.appCertificate = certificate
			}
			handler.appIcon = icon
			
			do {
				try await handler.copy()
				try await handler.modify()
                try? await handler.clean()
				
				await MainActor.run {
					completion(nil)
				}
			} catch {
				try? await handler.clean()
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	static func handleCertificateFiles(
		p12URL: URL,
		provisionURL: URL,
		p12Password: String,
		certificateName: String,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = CertificateFileHandler(
				key: p12URL,
				provision: provisionURL,
				password: p12Password,
				nickname: certificateName.isEmpty ? nil : certificateName
			)
			
			do {
				try await handler.copy()
				try await handler.addToDatabase()
				await MainActor.run {
					completion(nil)
				}
			} catch {
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	
	static func checkPasswordForCertificate(
		for key: URL,
		with password: String,
		using provision: URL
	) -> Bool {
		defer {
			password_check_fix_WHAT_THE_FUCK_free(provision.path)
		}
		
		password_check_fix_WHAT_THE_FUCK(provision.path)
		
		if (!p12_password_check(key.path, password)) {
			return false
		}
		
		return true
	}
	
	static func checkPasswordForCertificateData(
		p12Data: Data,
		provisionData: Data,
		password: String
	) -> Bool {
		let tempDir = FileManager.default.temporaryDirectory
		let tempP12 = tempDir.appendingPathComponent("temp_cert.p12")
		let tempProvision = tempDir.appendingPathComponent("temp_provision.mobileprovision")
		
		defer {
			try? FileManager.default.removeItem(at: tempP12)
			try? FileManager.default.removeItem(at: tempProvision)
		}
		
		do {
			try p12Data.write(to: tempP12)
			try provisionData.write(to: tempProvision)
			
			return checkPasswordForCertificate(for: tempP12, with: password, using: tempProvision)
		} catch {
			print("Error creating temporary files for password check: \(error)")
			return false
		}
	}
	
	static func movePairing(_ url: URL) {
		let fileManager = FileManager.default
		let dest = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")

		try? fileManager.removeFileIfNeeded(at: dest)
		
		try? fileManager.copyItem(at: url, to: dest)
		
		HeartbeatManager.shared.start(true)
	}
	
	#if SERVER
	/// Generates a brand-new on-device Certificate Authority and leaf server
	/// certificate, replacing the discontinued `backloop.dev` dependency.
	///
	/// This never touches the network: the root CA and leaf certificate are
	/// generated entirely locally using `swift-certificates`. Returns the
	/// file URL of the DER-encoded root CA so callers can offer it for the
	/// user to trust/install, exactly as a self-hosted `mkcert` root would
	/// need to be.
	@discardableResult
	static func generateLocalSSLCertificates() throws -> URL {
		let pack = try LocalCertificateAuthority.generate()
		try writeSSLCertificates(cert: pack.cert, key: pack.key, commonName: pack.commonName)
		
		// Keep the CA around so Settings can offer to (re)share it without
		// having to regenerate (which would invalidate the leaf cert on disk).
		let serverDir = URL.documentsDirectory.appendingPathComponent("App").appendingPathComponent("Server")
		try FileManager.default.createDirectoryIfNeeded(at: serverDir)
		
		let caPemURL = serverDir.appendingPathComponent("ca.pem")
		try pack.ca.write(to: caPemURL, atomically: true, encoding: .utf8)
		
		let caCerURL = serverDir.appendingPathComponent("Ksign Local CA.cer")
		try pack.caDER.write(to: caCerURL, options: .atomic)
		
		return caCerURL
	}
	
	private static func writeSSLCertificates(cert: String, key: String, commonName: String) throws {
		let serverDir = URL.documentsDirectory.appendingPathComponent("App").appendingPathComponent("Server")
		let pemURL = serverDir.appendingPathComponent("server.pem")
		let crtURL = serverDir.appendingPathComponent("server.crt")
		let commonNameURL = serverDir.appendingPathComponent("commonName.txt")
		
		try FileManager.default.createDirectoryIfNeeded(at: serverDir)
		try key.write(to: pemURL, atomically: true, encoding: .utf8)
		try cert.write(to: crtURL, atomically: true, encoding: .utf8)
		try commonName.write(to: commonNameURL, atomically: true, encoding: .utf8)
	}
	#endif
	
	static func handleSource(
		_ urlString: String,
		competion: @escaping () -> Void
	) {
		guard let url = URL(string: urlString) else { return }
		
		NBFetchService().fetch<ASRepository>(from: url) { (result: Result<ASRepository, Error>) in
			switch result {
			case .success(let data):
				let id = data.id ?? url.absoluteString
				
				if !Storage.shared.sourceExists(id) {
					Storage.shared.addSource(url, repository: data, id: id) { _ in
						competion()
					}
				} else {
					DispatchQueue.main.async {
						UIAlertController.showAlertWithOk(title: "Error", message: "Repository already added.")
					}
				}
			case .failure(let error):
				DispatchQueue.main.async {
					UIAlertController.showAlertWithOk(title: "Error", message: error.localizedDescription)
				}
			}
		}
	}
}

private enum CertificateHandlerError: Error {
	case invalidCertificate
}

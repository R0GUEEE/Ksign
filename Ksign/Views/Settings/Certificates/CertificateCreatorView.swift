//
//  CertificateCreatorView.swift
//  Ksign
//
//  A form for making a signing identity on the device: private key, self-signed
//  certificate and a matching provisioning profile, registered through the same
//  import path the file picker uses so it lands in Settings > Certificates.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct CertificateCreatorView: View {
	@Environment(\.dismiss) private var dismiss

	@State private var _commonName: String = "Ksign Self-Signed"
	@State private var _organization: String = "Ksign"
	@State private var _validityDays: Int = 365
	@State private var _keyAlgorithm: SelfSignedKeyAlgorithm = .rsa2048
	@State private var _password: String = ""

	@State private var _isCreating: Bool = false
	@State private var _errorMessage: String = ""
	@State private var _isErrorPresenting: Bool = false

	private static let _validityChoices: [Int] = [30, 90, 180, 365, 730, 1825]

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Create Certificate"), displayMode: .inline) {
			Form {
				NBSection(.localized("Identity")) {
					TextField(.localized("Name"), text: $_commonName)
					TextField(.localized("Organization"), text: $_organization)
				} footer: {
					Text(.localized("The name is the certificate's common name and the profile's name, so it is what shows up in the certificate list and in the profile that gets embedded when signing."))
				}

				NBSection(.localized("Key")) {
					Picker(.localized("Key Type"), selection: $_keyAlgorithm) {
						ForEach(SelfSignedKeyAlgorithm.allCases) { algorithm in
							Text(algorithm.rawValue).tag(algorithm)
						}
					}

					Picker(.localized("Valid For"), selection: $_validityDays) {
						ForEach(Self._validityChoices, id: \.self) { days in
							Text(Self._description(forDays: days)).tag(days)
						}
					}
				} footer: {
					Text(.localized("RSA 2048 is accepted by the widest range of tools, EC P-256 generates almost instantly. Long validity does not buy anything here — only Ksign's own expiry reminder looks at it."))
				}

				NBSection(.localized("Password")) {
					SecureField(.localized("Enter Password"), text: $_password)
				} footer: {
					Text(.localized("Protects the generated .p12. Leave it blank to create one without a password."))
				}

				Section {
					if _isCreating {
						HStack(spacing: 10) {
							ProgressView()
							Text(.localized("Generating certificate…"))
								.foregroundColor(.secondary)
						}
					}
				} footer: {
					Text(.localized("A self-signed certificate chains to no Apple root, so it only works where the install path does not validate the chain — a jailbroken device with AppSync, TrollStore, or a device you control. It cannot be installed through Apple's normal installer, and no Apple service will accept it."))
				}
			}
			.toolbar {
				NBToolbarButton(role: .cancel)

				NBToolbarButton(
					.localized("Create"),
					style: .text,
					placement: .confirmationAction,
					isDisabled: _isCreating
				) {
					_create()
				}
			}
			.alert(isPresented: $_isErrorPresenting) {
				Alert(
					title: Text(.localized("Could Not Create Certificate")),
					message: Text(_errorMessage),
					dismissButton: .default(Text(.localized("OK")))
				)
			}
		}
	}
}

// MARK: - Extension: View
extension CertificateCreatorView {
	private static func _description(forDays days: Int) -> String {
		switch days {
		case 365: return String.localized("1 year")
		case 730: return String.localized("2 years")
		case 1825: return String.localized("5 years")
		default: return String.localized("%lld days", arguments: days)
		}
	}

	private func _create() {
		_isCreating = true

		let request = SelfSignedCertificateRequest(
			commonName: _commonName,
			organization: _organization,
			validityDays: _validityDays,
			keyAlgorithm: _keyAlgorithm,
			password: _password
		)
		let nickname = _commonName

		// Generating an RSA key is slow enough to be felt, and it has nothing to
		// do with the UI thread.
		Task.detached(priority: .userInitiated) {
			do {
				let product = try SelfSignedCertificateFactory.generate(request)

				let directory = FileManager.default.temporaryDirectory
					.appendingPathComponent("SelfSignedCertificate-\(UUID().uuidString)", isDirectory: true)
				try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

				let p12URL = directory.appendingPathComponent("certificate.p12")
				let provisionURL = directory.appendingPathComponent("certificate.mobileprovision")
				try product.p12.write(to: p12URL)
				try product.provision.write(to: provisionURL)

				await MainActor.run {
					// Same entry point the file importer uses, so the pair is
					// validated, copied into the certificate store and recorded
					// in exactly the same way.
					FR.handleCertificateFiles(
						p12URL: p12URL,
						provisionURL: provisionURL,
						p12Password: request.password,
						certificateName: nickname
					) { error in
						_isCreating = false
						if let error {
							_errorMessage = error.localizedDescription
							_isErrorPresenting = true
						} else {
							dismiss()
						}
					}
				}
			} catch {
				await MainActor.run {
					_isCreating = false
					_errorMessage = error.localizedDescription
					_isErrorPresenting = true
				}
			}
		}
	}
}

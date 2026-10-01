//
//  ServerView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import NimbleJSON
import NimbleViews

struct ServerView: View {
	@AppStorage("Feather.ipFix") private var _ipFix: Bool = false
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	
	private let _serverMethods: [String] = [
		.localized("Fully Local"), 
		.localized("Semi Local")
	]
	
	@State private var _isGenerating = false
	
	var body: some View {
		Group {
			Section {
				Picker(.localized("Installation Type"), systemImage: "server.rack", selection: $_serverMethod) {
					ForEach(_serverMethods.indices, id: \.self) { index in
						Text(_serverMethods[index]).tag(index)
					}
				}
				Toggle(.localized("Only use localhost address"), systemImage: "lifepreserver", isOn: $_ipFix)
					.disabled(_serverMethod != 1)
			}
			
			Section {
				Button {
					_shareCertificateAuthority()
				} label: {
					Label(.localized("Trust Local Certificate"), systemImage: "checkmark.seal")
				}
				Button {
					_regenerateCertificates()
				} label: {
					Label(.localized("Regenerate SSL Certificates"), systemImage: "arrow.triangle.2.circlepath")
				}
				.disabled(_isGenerating)
			} footer: {
				Text(.localized("\"Fully Local\" installs apps over HTTPS using a certificate authority generated on this device. Tap \"Trust Local Certificate\" once, install the profile, then enable full trust for it under Settings > General > About > Certificate Trust Settings."))
			}
		}
		.onChange(of: _serverMethod) { _ in
			UIAlertController.showAlertWithRestart(
				title: .localized("Restart Required"),
				message: .localized("These changes require a restart of the app")
			)
		}
	}
	
	private func _regenerateCertificates() {
		_isGenerating = true
		
		DispatchQueue.global(qos: .userInitiated).async {
			do {
				#if SERVER
				try FR.generateLocalSSLCertificates()
				#endif
				DispatchQueue.main.async {
					_isGenerating = false
					UINotificationFeedbackGenerator().notificationOccurred(.success)
					UIAlertController.showAlertWithOk(
						title: .localized("SSL Certificates"),
						message: .localized("New local certificates were generated. If you previously trusted the old certificate authority, tap \"Trust Local Certificate\" again to install the new one.")
					)
				}
			} catch {
				DispatchQueue.main.async {
					_isGenerating = false
					UIAlertController.showAlertWithOk(
						title: .localized("SSL Certificates"),
						message: error.localizedDescription
					)
				}
			}
		}
	}
	
	private func _shareCertificateAuthority() {
		let caURL = URL.documentsDirectory
			.appendingPathComponent("App")
			.appendingPathComponent("Server")
			.appendingPathComponent("Ksign Local CA.cer")
		
		guard FileManager.default.fileExists(atPath: caURL.path) else {
			UIAlertController.showAlertWithOk(
				title: .localized("SSL Certificates"),
				message: .localized("No local certificate authority was found yet, try regenerating the SSL certificates first.")
			)
			return
		}
		
		UIActivityViewController.show(activityItems: [caURL])
	}
}

//
//  LibraryInfoView.swift
//  Feather
//
//  Created by samara on 14.04.2025.
//

import SwiftUI
import NimbleViews
import Zsign

// MARK: - View
struct LibraryInfoView: View {
	var app: AppInfoPresentable
	
	// MARK: Body
    var body: some View {
		NBNavigationView(app.name ?? "", displayMode: .inline) {
			List {
				Section {} header: {
					FRAppIconView(app: app)
						.frame(maxWidth: .infinity, alignment: .center)
				}
				
				_infoSection(for: app)
				_certSection(for: app)
				_bundleSection(for: app)
				_executableSection(for: app)
                _diagnosticsSection(for: app)
				
				Section {
					Button(.localized("Open App Files"), systemImage: "folder") {
						UIApplication.open(Storage.shared.getUuidDirectory(for: app)!.toSharedDocumentsURL()!)
					}
				}
			}
			.toolbar {
				NBToolbarButton(role: .close)
			}
		}
    }
}

// MARK: - Extension: View
extension LibraryInfoView {
	@ViewBuilder
	private func _infoSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Info")) {
			if let name = app.name {
				_infoCell(.localized("Name"), desc: name)
			}
			
			if let ver = app.version {
				_infoCell(.localized("Version"), desc: ver)
			}
			
			if let id = app.identifier {
				_infoCell(.localized("Identifier"), desc: id)
			}
			
			if let date = app.date {
				_infoCell(.localized("Date Added"), desc: date.formatted())
			}
		}
	}
	
	@ViewBuilder
	private func _certSection(for app: AppInfoPresentable) -> some View {
		if let cert = Storage.shared.getCertificate(from: app) {
			NBSection(.localized("Certificate")) {
				CertificatesCellView(
					cert: cert
				)
			}
		}
	}
	
	@ViewBuilder
	private func _bundleSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Bundle")) {
			NavigationLink(.localized("Alternative Icons")) {
				SigningAlternativeIconView(app: app, appIcon: .constant(nil), isModifing: .constant(false))
			}
			NavigationLink(.localized("Frameworks & PlugIns")) {
				SigningFrameworksView(app: app, options: .constant(nil))
			}
		}
	}
	
	@ViewBuilder
	private func _executableSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Executable")) {
			NavigationLink(.localized("Dylibs")) {
				SigningDylibView(app: app, options: .constant(nil))
			}
		}
	}
	
    @ViewBuilder
    private func _diagnosticsSection(for app: AppInfoPresentable) -> some View {
        if let diagnostics = AppDiagnostics.inspect(app) {
            NBSection(.localized("Diagnostics")) {
                LabeledContent(.localized("Bundle Size")) {
                    Text(ByteCountFormatter.string(fromByteCount: diagnostics.bundleSize, countStyle: .file))
                }
                LabeledContent(.localized("Executable Size")) {
                    Text(ByteCountFormatter.string(fromByteCount: diagnostics.executableSize, countStyle: .file))
                }
                LabeledContent(.localized("Frameworks")) { Text(verbatim: "\(diagnostics.frameworks.count)") }
                LabeledContent(.localized("Dylibs")) { Text(verbatim: "\(diagnostics.dylibs.count)") }
                LabeledContent(.localized("Extensions")) { Text(verbatim: "\(diagnostics.extensions.count)") }
                LabeledContent(.localized("URL Schemes")) { Text(verbatim: "\(diagnostics.urlSchemes.count)") }
                LabeledContent(.localized("Privacy Manifests")) { Text(verbatim: "\(diagnostics.privacyManifestCount)") }
                LabeledContent(.localized("Provisioning Profile")) {
                    Text(diagnostics.hasProvisioningProfile ? .localized("Embedded") : .localized("None"))
                }
                if !diagnostics.warnings.isEmpty {
                    DisclosureGroup(.localized("Pre-sign Warnings")) {
                        ForEach(diagnostics.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

	@ViewBuilder
	private func _infoCell(_ title: String, desc: String) -> some View {
		LabeledContent(title) {
			Text(desc)
		}
	}
}

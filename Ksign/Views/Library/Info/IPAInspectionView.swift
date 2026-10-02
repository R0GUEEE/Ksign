import Foundation
import SwiftUI

struct IPAInspectionView: View {
    let inspection: IPAInspection
    var body: some View {
        List {
            Section(String(localized: "Application")) {
                value(String(localized: "Name"), inspection.displayName)
                value(String(localized: "Bundle ID"), inspection.bundleIdentifier)
                value(String(localized: "Version"), inspection.version.map { "\($0) (\(inspection.build ?? "?"))" })
                value(String(localized: "Minimum iOS"), inspection.minimumOS)
                value(String(localized: "Architectures"), inspection.architectureSummary)
                value(String(localized: "Bundle Size"), ByteCountFormatter.string(fromByteCount: inspection.bundleSize, countStyle: .file))
            }
            Section(String(localized: "Contents")) {
                value(String(localized: "Frameworks"), "\(inspection.frameworks.count)")
                value(String(localized: "Dylibs"), "\(inspection.dylibs.count)")
                value(String(localized: "Extensions"), "\(inspection.extensions.count)")
                value(String(localized: "URL Schemes"), inspection.urlSchemes.isEmpty ? String(localized: "None") : inspection.urlSchemes.joined(separator: ", "))
                value(String(localized: "Entitlements"), "\(inspection.entitlements.count)")
                value(String(localized: "Privacy Manifests"), "\(inspection.privacyManifestCount)")
            }
            if !inspection.warnings.isEmpty {
                Section(String(localized: "Security Warnings")) {
                    ForEach(inspection.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
            }
            if !inspection.entitlements.isEmpty {
                Section(String(localized: "Entitlements")) {
                    ForEach(inspection.entitlements.keys.sorted(), id: \.self) { key in
                        LabeledContent(key) { Text(inspection.entitlements[key] ?? "") }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "IPA Inspector"))
    }
    @ViewBuilder private func value(_ title: String, _ value: String?) -> some View {
        if let value { LabeledContent(title, value: value) }
    }
}

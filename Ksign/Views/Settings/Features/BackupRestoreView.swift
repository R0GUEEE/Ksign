import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BackupRestoreView: View {
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Button { makeBackup() } label: { Label(String(localized: "Export Backup"), systemImage: "arrow.up.doc") }
                Button { showImporter = true } label: { Label(String(localized: "Restore Backup"), systemImage: "arrow.down.doc") }
            } footer: {
                Text(String(localized: "Backups include signing options, profiles, certificates, provisioning profiles, and certificate passwords. Store exported files securely."))
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .navigationTitle(String(localized: "Backup & Restore"))
        .sheet(isPresented: $showExporter) {
            if let exportURL {
                FileExporterRepresentableView(urlsToExport: [exportURL]) { _ in }
            }
        }
        .sheet(isPresented: $showImporter) {
            FileImporterRepresentableView(allowedContentTypes: [.ksignBackup]) { urls in
                guard let url = urls.first else { return }
                BackupService.restore(from: url) { result in
                    switch result { case .success(let count): message = "\(count) " + String(localized: "certificates restored"); case .failure(let error): message = error.localizedDescription }
                }
            }
        }
    }
    private func makeBackup() {
        do { exportURL = try BackupService.makeBackup(); showExporter = true }
        catch { message = error.localizedDescription }
    }
}

extension UTType {
    static var ksignBackup: UTType { UTType(exportedAs: "nya.asami.ksignbackup", conformingTo: .data) }
}

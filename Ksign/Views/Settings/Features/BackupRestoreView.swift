import SwiftUI
import UniformTypeIdentifiers
import UIKit
import NimbleViews

struct BackupRestoreView: View {
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?
    @State private var password = ""
    @State private var encryptExport = true

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Encrypt Export"), isOn: $encryptExport)
                SecureField(String(localized: "Backup Password"), text: $password)
                Button { makeBackup() } label: {
                    Label(String(localized: "Export Backup"), systemImage: "arrow.up.doc")
                }
                Button { showImporter = true } label: {
                    Label(String(localized: "Restore Backup"), systemImage: "arrow.down.doc")
                }
            } footer: {
                Text(String(localized: "Backups include signing options, profiles, certificates, provisioning profiles, and certificate passwords. Encrypted backups require the password used during export."))
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .navigationTitle(String(localized: "Backup & Restore"))
        .sheet(isPresented: $showExporter) {
            if let exportURL { FileExporterRepresentableView(urlsToExport: [exportURL]) { _ in } }
        }
        .sheet(isPresented: $showImporter) {
            FileImporterRepresentableView(allowedContentTypes: [.ksignBackup, .ksignEncryptedBackup]) { urls in
                guard let url = urls.first else { return }
                restore(url)
            }
        }
    }

    private func makeBackup() {
        guard !encryptExport || password.count >= 4 else {
            message = String(localized: "Use a password with at least four characters.")
            return
        }
        do {
            let plainURL = try LibraryBackupService.makeArchive()
            if encryptExport {
                let encrypted = try EncryptedBackupService.encrypt(Data(contentsOf: plainURL), password: password)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ksign-backup.ksignbackup.enc")
                try encrypted.write(to: url, options: .atomic)
                exportURL = url
            } else { exportURL = plainURL }
            showExporter = true
        } catch { message = error.localizedDescription }
    }

    private func restore(_ url: URL) {
        if url.pathExtension == "enc" {
            guard !password.isEmpty else { message = String(localized: "Enter the backup password first."); return }
            do {
                let plain = try EncryptedBackupService.decrypt(Data(contentsOf: url), password: password)
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Ksign-restore.ksignbackup")
                try plain.write(to: temp, options: .atomic)
                LibraryBackupService.restoreArchive(from: temp, completion: restoreResult)
            } catch { message = error.localizedDescription }
        } else { LibraryBackupService.restoreArchive(from: url, completion: restoreResult) }
    }

    private func restoreResult(_ result: Result<Int, Swift.Error>) {
        switch result {
        case .success(let count): message = "\(count) " + String(localized: "apps restored")
        case .failure(let error): message = error.localizedDescription
        }
    }
}

extension UTType {
    static var ksignBackup: UTType { UTType(exportedAs: "nya.asami.ksignbackup", conformingTo: .data) }
    static var ksignEncryptedBackup: UTType { UTType(exportedAs: "nya.asami.ksignbackup.encrypted", conformingTo: .data) }
}

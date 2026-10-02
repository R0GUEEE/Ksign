import SwiftUI
import NimbleViews
import UIKit

struct CertificatesView: View {
    @AppStorage(CertificateSelection.uuidKey) private var _storedSelectedCertificateUUID = ""
    @State private var _isAddingPresenting = false
    @State private var _isCreatingPresenting = false
    @State private var _isSelectedInfoPresenting: CertificatePair?
    @State private var _searchText = ""
    private let _bindingSelectedCertificateUUID: Binding<String>?

    @FetchRequest(entity: CertificatePair.entity(), sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)], animation: .snappy)
    private var certificates: FetchedResults<CertificatePair>

    private var selectedUUID: Binding<String> { _bindingSelectedCertificateUUID ?? $_storedSelectedCertificateUUID }
    private var filteredCertificates: [CertificatePair] {
        guard !_searchText.isEmpty else { return Array(certificates) }
        return certificates.filter { cert in
            let decoded = Storage.shared.getProvisionFileDecoded(for: cert)
            return (cert.nickname?.localizedCaseInsensitiveContains(_searchText) ?? false) ||
                (decoded?.Name.localizedCaseInsensitiveContains(_searchText) ?? false) ||
                (decoded?.AppIDName.localizedCaseInsensitiveContains(_searchText) ?? false)
        }
    }

    init(selectedCertificateUUID: Binding<String>? = nil) {
        _bindingSelectedCertificateUUID = selectedCertificateUUID
    }

    var body: some View {
        NBGrid {
            ForEach(filteredCertificates, id: \.uuid) { cert in
                Button {
                    if let uuid = cert.uuid {
                        selectedUUID.wrappedValue = uuid
                        CertificateSelection.set(cert)
                    }
                } label: {
                    CertificatesCellView(cert: cert)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 17).fill(Color(uiColor: .quaternarySystemFill)))
                        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(selectedUUID.wrappedValue == cert.uuid ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { _isSelectedInfoPresenting = cert } label: { Label(.localized("Get Info"), systemImage: "info.circle") }
                    Button { Storage.shared.revokagedCertificate(for: cert) } label: { Label(.localized("Check Revocation"), systemImage: "checkmark.shield") }
                    Button { Storage.shared.renameCertificate(cert, to: cert.nickname) } label: { Label(.localized("Rename"), systemImage: "pencil") }
                    Button(role: .destructive) { Storage.shared.deleteCertificate(for: cert) } label: { Label(.localized("Delete"), systemImage: "trash") }
                }
            }
        }
        .navigationTitle(.localized("Certificates"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $_searchText, placement: .platform())
        .toolbar {
            if _bindingSelectedCertificateUUID == nil {
                NBToolbarMenu(systemImage: "plus", style: .icon, placement: .topBarTrailing) {
                    Button(.localized("Import Certificate"), systemImage: "square.and.arrow.down") { _isAddingPresenting = true }
                    Button(.localized("Create Certificate"), systemImage: "signature") { _isCreatingPresenting = true }
                }
            }
            if !certificates.isEmpty {
                NBToolbarButton(systemImage: "arrow.counterclockwise", style: .icon, placement: .topBarTrailing) {
                    certificates.forEach { Storage.shared.revokagedCertificate(for: $0) }
                }
            }
        }
        .sheet(item: $_isSelectedInfoPresenting) { CertificatesInfoView(cert: $0) }
        .sheet(isPresented: $_isAddingPresenting) { CertificatesAddView().presentationDetents([.medium]) }
        .sheet(isPresented: $_isCreatingPresenting) { CertificateCreatorView() }
        .onAppear {
            if selectedUUID.wrappedValue.isEmpty {
                selectedUUID.wrappedValue = CertificateSelection.migrateLegacySelection(from: Array(certificates)) ?? ""
            }
        }
    }
}

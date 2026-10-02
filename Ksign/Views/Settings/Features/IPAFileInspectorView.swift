import SwiftUI
import UniformTypeIdentifiers
import NimbleViews

struct IPAFileInspectorView: View {
    @State private var isImporting = false
    @State private var result: IPAInspection?
    @State private var error: String?
    var body: some View {
        Form {
            Button { isImporting = true } label: { Label(String(localized: "Choose IPA"), systemImage: "doc.badge.magnifyingglass") }
            if let result { NavigationLink(String(localized: "View Inspection")) { IPAInspectionView(inspection: result) } }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(String(localized: "IPA Inspector"))
        .sheet(isPresented: $isImporting) {
            FileImporterRepresentableView(allowedContentTypes: [.ipa, .tipa]) { urls in
                guard let url = urls.first else { return }
                Task.detached {
                    do { let inspection = try ArchiveIPAInspector.inspect(ipaURL: url); await MainActor.run { result = inspection } }
                    catch { await MainActor.run { self.error = error.localizedDescription } }
                }
            }
        }
    }
}

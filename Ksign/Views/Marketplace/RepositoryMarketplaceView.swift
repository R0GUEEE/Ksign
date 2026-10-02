import SwiftUI

struct RepositoryMarketplaceEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let repositoryURL: URL
    var iconURL: URL?
    var category: String?
    var compatibility: String?
    var featured: Bool?
    var verified: Bool?
}

struct RepositoryMarketplaceCatalog: Codable {
    var name: String
    var repositories: [RepositoryMarketplaceEntry]
}

@MainActor
final class RepositoryMarketplaceModel: ObservableObject {
    @Published var repositories: [RepositoryMarketplaceEntry] = []
    @Published var isLoading = false
    @Published var message: String?
    @Published var errorMessage: String?

    @AppStorage("ksign.repositoryMarketplace.catalog") var catalogURL = ""

    func refresh() async {
        guard let url = URL(string: catalogURL), !catalogURL.isEmpty else {
            repositories = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            if let catalog = try? JSONDecoder().decode(RepositoryMarketplaceCatalog.self, from: data) {
                repositories = catalog.repositories
            } else {
                repositories = try JSONDecoder().decode([RepositoryMarketplaceEntry].self, from: data)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ entry: RepositoryMarketplaceEntry) {
        FR.handleSource(entry.repositoryURL.absoluteString) {
            Task { @MainActor in
                self.message = "\(entry.name) was added to Sources."
            }
        }
    }
}

struct RepositoryMarketplaceView: View {
    @StateObject private var model = RepositoryMarketplaceModel()
    @State private var searchText = ""
    @State private var showingCatalogSettings = false

    private var filtered: [RepositoryMarketplaceEntry] {
        guard !searchText.isEmpty else { return model.repositories }
        return model.repositories.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            ($0.category?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        List {
            if !filtered.filter({ $0.featured == true }).isEmpty && searchText.isEmpty {
                Section("Featured") {
                    ForEach(filtered.filter { $0.featured == true }) { entry in row(entry) }
                }
            }
            Section("Repositories") {
                ForEach(filtered.filter { searchText.isEmpty ? $0.featured != true : true }) { entry in row(entry) }
            }
        }
        .navigationTitle("Repository Marketplace")
        .searchable(text: $searchText)
        .refreshable { await model.refresh() }
        .overlay {
            if !model.isLoading && model.repositories.isEmpty {
                ContentUnavailableView(
                    model.catalogURL.isEmpty ? "Add a Catalog" : "No Repositories",
                    systemImage: "storefront",
                    description: Text(model.catalogURL.isEmpty ? "Configure a repository catalog to discover sources." : "Pull to refresh or check the catalog URL.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCatalogSettings = true } label: { Image(systemName: "link.badge.plus") }
            }
        }
        .sheet(isPresented: $showingCatalogSettings) {
            NavigationStack {
                Form {
                    Section("Catalog") {
                        TextField("https://example.com/repositories.json", text: $model.catalogURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                    Section("Catalog Format") {
                        Text("Entries support id, name, description, repositoryURL and optional iconURL, category, compatibility, featured and verified fields.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Repository Catalog")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingCatalogSettings = false
                            Task { await model.refresh() }
                        }
                    }
                }
            }
        }
        .task { await model.refresh() }
        .alert("Repository Marketplace", isPresented: Binding(
            get: { model.message != nil || model.errorMessage != nil },
            set: { if !$0 { model.message = nil; model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.message = nil; model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? model.message ?? "")
        }
    }

    @ViewBuilder
    private func row(_ entry: RepositoryMarketplaceEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.name).font(.headline)
                if entry.verified == true {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                        .accessibilityLabel("Verified")
                }
                Spacer()
                Button("Add") { model.add(entry) }.buttonStyle(.borderedProminent)
            }
            Text(entry.description).font(.subheadline)
            HStack(spacing: 10) {
                if let category = entry.category { Label(category, systemImage: "tag") }
                if let compatibility = entry.compatibility { Label(compatibility, systemImage: "iphone") }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

import SwiftUI

struct TweakMarketplacePackage: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let author: String
    let version: String
    let description: String
    let downloadURL: URL
    var iconURL: URL?
    var category: String?
    var compatibility: String?
    var sha256: String?
}

struct TweakMarketplaceFeed: Codable {
    var name: String
    var packages: [TweakMarketplacePackage]
}

@MainActor
final class TweakMarketplaceModel: ObservableObject {
    @Published var packages: [TweakMarketplacePackage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var installedMessage: String?

    @AppStorage("ksign.tweakMarketplace.source") var source = ""

    func refresh() async {
        guard let url = URL(string: source), !source.isEmpty else {
            packages = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            if let feed = try? JSONDecoder().decode(TweakMarketplaceFeed.self, from: data) {
                packages = feed.packages
            } else {
                packages = try JSONDecoder().decode([TweakMarketplacePackage].self, from: data)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func download(_ package: TweakMarketplacePackage) async {
        do {
            let (temporary, response) = try await URLSession.shared.download(from: package.downloadURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let fm = FileManager.default
            let safeName = package.id.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
            let fileName = "\(safeName)-\(package.version).deb"
            let root = fm.tweaks
            try fm.createDirectoryIfNeeded(at: root)
            let destination = root.appendingPathComponent(fileName)
            let rootPath = root.standardizedFileURL.path
            guard destination.standardizedFileURL.path.hasPrefix(rootPath + "/") else { throw URLError(.badURL) }
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: temporary, to: destination)
            installedMessage = "\(package.name) downloaded to the Tweaks library."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TweakMarketplaceView: View {
    @StateObject private var model = TweakMarketplaceModel()
    @State private var searchText = ""
    @State private var showingSettings = false

    private var filtered: [TweakMarketplacePackage] {
        guard !searchText.isEmpty else { return model.packages }
        return model.packages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.author.localizedCaseInsensitiveContains(searchText) ||
            ($0.category?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { package in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(package.name).font(.headline)
                            Text("\(package.author) • v\(package.version)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await model.download(package) }
                        } label: {
                            Image(systemName: "arrow.down.circle.fill").font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(package.description).font(.subheadline)
                    HStack(spacing: 10) {
                        if let category = package.category { Label(category, systemImage: "tag") }
                        if let compatibility = package.compatibility { Label(compatibility, systemImage: "iphone") }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Tweak Marketplace")
            .searchable(text: $searchText)
            .refreshable { await model.refresh() }
            .overlay {
                if !model.isLoading && model.packages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox").font(.title2)
                        Text(model.source.isEmpty ? "Add a Marketplace Source" : "No Tweaks").font(.headline)
                        Text(model.source.isEmpty ? "Add a JSON feed URL from the source button." : "Pull to refresh or check the feed.").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "link.badge.plus") }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    Form {
                        Section("Marketplace Feed") {
                            TextField("https://example.com/tweaks.json", text: $model.source)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                        }
                        Section("Supported JSON") {
                            Text("A feed can be an array of packages or an object containing name + packages. Packages support id, name, author, version, description, downloadURL, iconURL, category, compatibility and sha256.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Marketplace Source")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingSettings = false
                                Task { await model.refresh() }
                            }
                        }
                    }
                }
            }
            .task { await model.refresh() }
            .alert("Marketplace", isPresented: Binding(
                get: { model.errorMessage != nil || model.installedMessage != nil },
                set: { if !$0 { model.errorMessage = nil; model.installedMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.errorMessage = nil; model.installedMessage = nil }
            } message: {
                Text(model.errorMessage ?? model.installedMessage ?? "")
            }
        }
    }
}

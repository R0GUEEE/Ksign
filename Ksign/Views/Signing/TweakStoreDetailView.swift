import SwiftUI

struct TweakStoreDetailView: View {
    let item: TweakStoreItem
    @Binding var options: Options
    @StateObject private var store = TweakStoreManager.shared
    @State private var installing = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    if let icon = item.iconURL {
                        AsyncImage(url: icon) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "puzzlepiece.extension") }
                            .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    VStack(alignment: .leading) {
                        Text(item.name).font(.title3.bold())
                        Text([item.author, item.version].compactMap { $0 }.joined(separator: " • ")).foregroundColor(.secondary)
                    }
                }
                if let description = item.description { Text(description) }
            }
            if let screenshots = item.screenshotURLs, !screenshots.isEmpty {
                Section(.localized("Screenshots")) {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(screenshots, id: \.absoluteString) { url in
                                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                                    .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            }
            Section(.localized("Package")) {
                if let category = item.category { LabeledContent(.localized("Category"), value: category) }
                if let minimum = item.minimumIOS { LabeledContent(.localized("Minimum iOS"), value: minimum) }
                LabeledContent(.localized("Integrity"), value: item.sha256 == nil ? .localized("Not provided") : "SHA-256")
                LabeledContent(.localized("Status"), value: store.hasUpdate(item) ? .localized("Update Available") : (store.isInstalled(item) ? .localized("Installed") : .localized("Not Installed")))
            }
            let dependencies = store.dependencies(for: item)
            if !dependencies.isEmpty {
                Section(.localized("Dependencies")) {
                    ForEach(dependencies) { dependency in
                        LabeledContent(dependency.name, value: dependency.version ?? "")
                    }
                }
            }
            if let ids = item.bundleIdentifiers, !ids.isEmpty {
                Section(.localized("Compatible Apps")) { ForEach(ids, id: \.self) { Text($0) } }
            }
            if let error { Section { Text(error).foregroundColor(.red) } }
            Section {
                Button {
                    Task { await install() }
                } label: {
                    HStack { Spacer(); if installing { ProgressView() } else { Text(store.hasUpdate(item) ? .localized("Update & Add") : .localized("Download & Add")) }; Spacer() }
                }.disabled(installing)
            }
        }
        .navigationTitle(item.name)
        .toolbar {
            Button { store.toggleFavorite(item) } label: { Image(systemName: store.favorites.contains(item.id) ? "heart.fill" : "heart") }
        }
    }

    private func install() async {
        installing = true; defer { installing = false }
        do {
            let urls = try await store.downloadWithDependencies(item)
            for url in urls where !options.injectionFiles.contains(url) { options.injectionFiles.append(url) }
        } catch { self.error = error.localizedDescription }
    }
}

import SwiftUI
import NimbleViews

struct TweakStoreView: View {
    @StateObject private var store = TweakStoreManager.shared
    @Binding var options: Options
    var bundleIdentifier: String?
    @State private var search = ""
    @State private var sourceText = ""
    @State private var downloading: Set<String> = []
    @State private var compatibleOnly = true
    @State private var favoritesOnly = false

    private var filtered: [TweakStoreItem] {
        store.items.filter { item in
            (!compatibleOnly || item.isCompatible(with: bundleIdentifier)) &&
            (!favoritesOnly || store.favorites.contains(item.id)) &&
            (search.isEmpty ||
             item.name.localizedCaseInsensitiveContains(search) ||
             (item.author?.localizedCaseInsensitiveContains(search) ?? false) ||
             (item.category?.localizedCaseInsensitiveContains(search) ?? false) ||
             (item.tags?.contains { $0.localizedCaseInsensitiveContains(search) } ?? false))
        }
    }

    var body: some View {
        List {
            if bundleIdentifier != nil {
                Section {
                    Toggle(.localized("Compatible with Current App"), isOn: $compatibleOnly)
                    Toggle(.localized("Favorites Only"), isOn: $favoritesOnly)
                }
            }
            Section {
                HStack {
                    TextField("https://example.com/tweaks.json", text: $sourceText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(.localized("Add")) {
                        guard let url = URL(string: sourceText), url.scheme == "https" else { return }
                        store.addSource(url); sourceText = ""
                        Task { await store.refresh() }
                    }
                }
                ForEach(store.sources, id: \.absoluteString) { source in
                    VStack(alignment: .leading) {
                        Text(source.absoluteString).font(.caption).lineLimit(1)
                        if let health = store.sourceHealth[source] { Text(health).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
                    }
                        .swipeActions {
                            Button(role: .destructive) { store.removeSource(source) } label: {
                                Label(.localized("Delete"), systemImage: "trash")
                            }
                        }
                }
            } header: { Text(.localized("Sources")) }

            if !store.items.filter({ $0.featured == true }).isEmpty && search.isEmpty && !favoritesOnly {
                Section(.localized("Featured")) {
                    ForEach(store.items.filter { $0.featured == true && (!compatibleOnly || $0.isCompatible(with: bundleIdentifier)) }) {
                        packageRow($0)
                    }
                }
            }

            Section(.localized("Tweaks")) {
                ForEach(filtered) { packageRow($0) }
            }
        }
        .navigationTitle(.localized("Tweak Store"))
        .searchable(text: $search)
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
        .overlay {
            if store.isLoading && store.items.isEmpty { ProgressView() }
        }
    }

    @ViewBuilder private func packageRow(_ item: TweakStoreItem) -> some View {
        NavigationLink {
            TweakStoreDetailView(item: item, options: $options)
        } label: {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.name).font(.headline)
                        if item.featured == true { Image(systemName: "star.fill").font(.caption) }
                    }
                    Text([item.author, item.version, item.category].compactMap { $0 }.joined(separator: " • "))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { store.toggleFavorite(item) } label: {
                    Image(systemName: store.favorites.contains(item.id) ? "heart.fill" : "heart")
                }.buttonStyle(.borderless)
                Button { Task { await download(item) } } label: {
                    if downloading.contains(item.id) { ProgressView() }
                    else if store.isInstalled(item) { Image(systemName: "checkmark.circle.fill") }
                    else { Image(systemName: "arrow.down.circle") }
                }.buttonStyle(.borderless).disabled(downloading.contains(item.id))
            }
            if let description = item.description {
                Text(description).font(.caption).foregroundColor(.secondary).lineLimit(3)
            }
            HStack(spacing: 8) {
                if item.isCompatible(with: bundleIdentifier) {
                    Label(.localized("Compatible"), systemImage: "checkmark.shield").font(.caption2)
                } else {
                    Label(.localized("Other App"), systemImage: "exclamationmark.triangle").font(.caption2)
                }
                if let minimumIOS = item.minimumIOS {
                    Text("iOS \(minimumIOS)+").font(.caption2)
                }
            }.foregroundColor(.secondary)
        }.padding(.vertical, 3)
        }
    }

    private func download(_ item: TweakStoreItem) async {
        downloading.insert(item.id)
        defer { downloading.remove(item.id) }
        do {
            let urls = try await store.downloadWithDependencies(item)
            for url in urls where !options.injectionFiles.contains(url) { options.injectionFiles.append(url) }
        } catch { store.errorMessage = error.localizedDescription }
    }
}

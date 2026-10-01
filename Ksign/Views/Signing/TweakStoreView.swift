import SwiftUI
import NimbleViews

struct TweakStoreView: View {
    @StateObject private var store = TweakStoreManager.shared
    @Binding var options: Options
    @State private var search = ""
    @State private var sourceText = ""
    @State private var downloading: Set<String> = []

    private var filtered: [TweakStoreItem] {
        guard !search.isEmpty else { return store.items }
        return store.items.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            ($0.author?.localizedCaseInsensitiveContains(search) ?? false) ||
            ($0.tags?.contains(where: { $0.localizedCaseInsensitiveContains(search) }) ?? false)
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("https://example.com/tweaks.json", text: $sourceText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(.localized("Add")) {
                        guard let url = URL(string: sourceText), url.scheme == "https" else { return }
                        store.addSource(url)
                        sourceText = ""
                        Task { await store.refresh() }
                    }
                }
                ForEach(store.sources, id: \.absoluteString) { source in
                    Text(source.absoluteString).font(.caption).lineLimit(1)
                        .swipeActions {
                            Button(role: .destructive) { store.removeSource(source) } label: {
                                Label(.localized("Delete"), systemImage: "trash")
                            }
                        }
                }
            } header: { Text(.localized("Sources")) }

            Section {
                ForEach(filtered) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text([item.author, item.version].compactMap { $0 }.joined(separator: " • "))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await download(item) }
                            } label: {
                                if downloading.contains(item.id) { ProgressView() }
                                else { Image(systemName: "arrow.down.circle") }
                            }
                            .disabled(downloading.contains(item.id))
                        }
                        if let description = item.description {
                            Text(description).font(.caption).foregroundColor(.secondary).lineLimit(3)
                        }
                        if let ids = item.bundleIdentifiers, !ids.isEmpty {
                            Text(ids.joined(separator: ", ")).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        }
                    }.padding(.vertical, 3)
                }
            } header: { Text(.localized("Tweaks")) }
        }
        .navigationTitle(.localized("Tweak Store"))
        .searchable(text: $search)
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
    }

    private func download(_ item: TweakStoreItem) async {
        downloading.insert(item.id)
        defer { downloading.remove(item.id) }
        do {
            let url = try await store.download(item)
            if !options.injectionFiles.contains(url) { options.injectionFiles.append(url) }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

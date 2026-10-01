import Foundation

struct TweakStoreCatalog: Codable {
    var name: String
    var tweaks: [TweakStoreItem]
}

struct TweakStoreItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var author: String?
    var version: String?
    var description: String?
    var downloadURL: URL
    var iconURL: URL?
    var bundleIdentifiers: [String]?
    var tags: [String]?
    var category: String?
    var featured: Bool?
    var minimumIOS: String?
    var screenshotURLs: [URL]?
    var homepageURL: URL?
    var sha256: String?

    func isCompatible(with bundleIdentifier: String?) -> Bool {
        guard let targets = bundleIdentifiers, !targets.isEmpty, let bundleIdentifier else { return true }
        return targets.contains { target in
            target == "*" || target.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }
}

@MainActor
final class TweakStoreManager: ObservableObject {
    static let shared = TweakStoreManager()

    @Published var items: [TweakStoreItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sourcesKey = "ksign.tweakStore.sources"
    private let favoritesKey = "ksign.tweakStore.favorites"

    var favorites: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []) }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: favoritesKey)
            objectWillChange.send()
        }
    }

    func toggleFavorite(_ item: TweakStoreItem) {
        var value = favorites
        if value.contains(item.id) { value.remove(item.id) } else { value.insert(item.id) }
        favorites = value
    }

    func isInstalled(_ item: TweakStoreItem) -> Bool {
        let prefix = item.name.replacingOccurrences(of: "/", with: "-") + "-"
        let files = (try? FileManager.default.contentsOfDirectory(at: FileManager.default.tweaks, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.lastPathComponent.hasPrefix(prefix) }
    }

    func installedURL(for item: TweakStoreItem) -> URL? {
        let prefix = item.name.replacingOccurrences(of: "/", with: "-") + "-"
        let files = (try? FileManager.default.contentsOfDirectory(at: FileManager.default.tweaks, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.lastPathComponent.hasPrefix(prefix) }
    }
    var sources: [URL] {
        get {
            (UserDefaults.standard.stringArray(forKey: sourcesKey) ?? []).compactMap(URL.init(string:))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.absoluteString), forKey: sourcesKey)
            objectWillChange.send()
        }
    }

    func addSource(_ url: URL) {
        guard !sources.contains(url) else { return }
        sources.append(url)
    }

    func removeSource(_ url: URL) {
        sources.removeAll { $0 == url }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        var merged: [String: TweakStoreItem] = [:]
        for source in sources {
            do {
                let (data, response) = try await URLSession.shared.data(from: source)
                guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { continue }
                let catalog = try JSONDecoder().decode(TweakStoreCatalog.self, from: data)
                for item in catalog.tweaks { merged[item.id] = item }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        items = merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isLoading = false
    }

    func download(_ item: TweakStoreItem) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: item.downloadURL)
        guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else {
            throw URLError(.badServerResponse)
        }
        let ext = item.downloadURL.pathExtension.lowercased()
        guard ["deb", "dylib", "framework", "bundle"].contains(ext) else {
            throw URLError(.unsupportedURL)
        }
        let directory = FileManager.default.tweaks
        try FileManager.default.createDirectoryIfNeeded(at: directory)
        let safeName = item.name.replacingOccurrences(of: "/", with: "-")
        let destination = directory.appendingPathComponent("\(safeName)-\(item.version ?? "latest").\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

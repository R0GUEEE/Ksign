import Foundation
import CoreData
import SwiftUI

struct LibraryDuplicateGroup: Identifiable {
    let id: String
    let identifier: String
    let apps: [AppInfoPresentable]
}

enum LibraryDuplicateDetector {
    static func groups(imported: [Imported], signed: [Signed]) -> [LibraryDuplicateGroup] {
        let all: [AppInfoPresentable] = imported.map { $0 as AppInfoPresentable } + signed.map { $0 as AppInfoPresentable }
        let grouped = Dictionary(grouping: all) { $0.identifier?.lowercased() ?? "" }
        return grouped.compactMap { key, apps in
            guard !key.isEmpty, apps.count > 1 else { return nil }
            return LibraryDuplicateGroup(id: key, identifier: key, apps: apps.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) })
        }.sorted { $0.identifier < $1.identifier }
    }
}

struct DuplicateAppsView: View {
    @FetchRequest(entity: Imported.entity(), sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)], animation: .snappy)
    private var imported: FetchedResults<Imported>
    @FetchRequest(entity: Signed.entity(), sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)], animation: .snappy)
    private var signed: FetchedResults<Signed>

    private var groups: [LibraryDuplicateGroup] {
        LibraryDuplicateDetector.groups(imported: Array(imported), signed: Array(signed))
    }

    var body: some View {
        List {
            if groups.isEmpty {
                ContentUnavailableView(String(localized: "No Duplicates"), systemImage: "checkmark.circle", description: Text(String(localized: "Every bundle identifier appears only once in the library.")))
            } else {
                ForEach(groups) { group in
                    Section(group.identifier) {
                        ForEach(Array(group.apps.enumerated()), id: \.offset) { item in
                            let app = item.element
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(app.userTitle ?? app.name ?? String(localized: "Unknown"))
                                    Text(app.version ?? String(localized: "Unknown"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.offset == 0 { Text(String(localized: "Newest")).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Duplicate Apps"))
    }
}

extension AppInfoPresentable {
    var isFavorite: Bool { (self as? NSManagedObject)?.value(forKey: "isFavorite") as? Bool ?? false }
}

extension Storage {
    func setFavorite(_ favorite: Bool, for app: AppInfoPresentable) {
        guard let object = app as? NSManagedObject else { return }
        object.setValue(favorite, forKey: "isFavorite")
        object.setValue(Date(), forKey: "lastUsedDate")
        saveContext()
    }
}

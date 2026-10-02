import SwiftUI
import CoreData
import NimbleViews

struct LibraryMaintenanceView: View {
    @AppStorage("Feather.showFavoritesOnly") private var favoritesOnly = false
    @FetchRequest(entity: Imported.entity(), sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)], animation: .snappy)
    private var imported: FetchedResults<Imported>
    @FetchRequest(entity: Signed.entity(), sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)], animation: .snappy)
    private var signed: FetchedResults<Signed>

    private var favoriteCount: Int { imported.filter { $0.isFavorite }.count + signed.filter { $0.isFavorite }.count }
    var body: some View {
        Form {
            Toggle(String(localized: "Show Favorites Only"), isOn: $favoritesOnly)
            LabeledContent(String(localized: "Favorite Apps"), value: "\(favoriteCount)")
            NavigationLink(String(localized: "Find Duplicate Apps"), destination: DuplicateAppsView())
            Section {
                Button(String(localized: "Clear All Favorites"), role: .destructive) {
                    imported.forEach { Storage.shared.setFavorite(false, for: $0) }
                    signed.forEach { Storage.shared.setFavorite(false, for: $0) }
                }.disabled(favoriteCount == 0)
            }
        }
        .navigationTitle(String(localized: "Library Maintenance"))
    }
}

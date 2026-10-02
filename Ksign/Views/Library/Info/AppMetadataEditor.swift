import Foundation
import SwiftUI

struct AppMetadataEditor: View {
    let app: AppInfoPresentable
    @State private var title: String
    @State private var notes: String
    @State private var tags: String
    @Environment(\.dismiss) private var dismiss
    init(app: AppInfoPresentable) {
        self.app = app
        _title = State(initialValue: app.userTitle ?? "")
        _notes = State(initialValue: app.userNotes ?? "")
        _tags = State(initialValue: app.userTags.joined(separator: ", "))
    }
    var body: some View {
        Form {
            TextField(String(localized: "Display Title"), text: $title)
            TextField(String(localized: "Tags (comma separated)"), text: $tags)
            Section(String(localized: "Notes")) { TextEditor(text: $notes).frame(minHeight: 120) }
            Button(String(localized: "Save")) {
                Storage.shared.updateMetadata(for: app, title: title, notes: notes, tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                dismiss()
            }
        }.navigationTitle(String(localized: "App Metadata"))
    }
}

extension AppInfoPresentable {
    var userTitle: String? { (self as? NSManagedObject)?.value(forKey: "userTitle") as? String }
    var userNotes: String? { (self as? NSManagedObject)?.value(forKey: "userNotes") as? String }
    var userTags: [String] { (self as? NSManagedObject)?.value(forKey: "userTags") as? [String] ?? [] }
}

extension Storage {
    func updateMetadata(for app: AppInfoPresentable, title: String, notes: String, tags: [String]) {
        guard let object = app as? NSManagedObject else { return }
        object.setValue(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title, forKey: "userTitle")
        object.setValue(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes, forKey: "userNotes")
        object.setValue(tags.filter { !$0.isEmpty }, forKey: "userTags")
        saveContext()
    }
}

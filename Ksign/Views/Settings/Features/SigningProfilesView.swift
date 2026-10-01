import SwiftUI
import NimbleViews

struct SigningProfilesView: View {
    @StateObject private var manager = OptionsManager.shared
    @State private var profileName = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField(.localized("Profile Name"), text: $profileName)
                    Button(.localized("Save")) {
                        manager.saveProfile(named: profileName)
                        profileName = ""
                    }
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } footer: {
                Text(.localized("Profiles save a complete snapshot of the current signing options so configurations can be reused between apps."))
            }

            Section {
                if manager.profiles.isEmpty {
                    Text(.localized("No Signing Profiles"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                Text(profile.updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(.localized("Apply")) {
                                manager.applyProfile(profile)
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                manager.deleteProfile(profile)
                            } label: {
                                Label(.localized("Delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text(.localized("Saved Profiles"))
            }
        }
        .navigationTitle(.localized("Signing Profiles"))
    }
}

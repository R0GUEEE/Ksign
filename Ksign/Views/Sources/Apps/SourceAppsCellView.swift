//
//  SourceAppsCellView.swift
//  Feather
//
//  Created by samara on 3.05.2025.
//

import SwiftUI
import AltSourceKit
import NimbleViews
import Combine
import NukeUI

// thats a whole pharaghraph of codes
struct SourceAppsCellView: View {
    @AppStorage("Feather.storeCellAppearance") private var _storeCellAppearance: Int = 0
    
    var source: ASRepository
    var app: ASRepository.App
    /// Shows which repository a result came from. Only useful in the
    /// aggregated "All Repositories" / App Store lists, where the same app
    /// can appear in several sources; it's redundant in a single-source view.
    var showsSourceName: Bool = false
    
    private var _sourceName: String? {
        guard
            showsSourceName,
            let name = source.name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else {
            return nil
        }
        return name
    }
    
    var body: some View {
        VStack {
            HStack(spacing: 2) {
                FRIconCellView(
                    title: app.currentName,
                    subtitle: Self.appDescription(app: app),
                    iconUrl: app.iconURL
                )
                .overlay(alignment: .bottomLeading) {
                    if let iconURL = source.currentIconURL {
                        LazyImage(url: iconURL) { state in
                            if let image = state.image {
                                image
                                    .appIconStyle(size: 20, isCircle: true, background: Color(uiColor: .secondarySystemBackground))
                                    .offset(x: 41, y: 4)
                            }
                        }
                    }
                }
                DownloadButtonView(app: app)
            }
            
            if let sourceName = _sourceName {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption2)
                    Text(sourceName)
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
            
            if
                _storeCellAppearance != 0,
                let desc = app.localizedDescription
            {
                Text(desc)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
    
    static func appDescription(app: ASRepository.App) -> String {
        let optionalComponents: [String?] = [
            app.currentVersion,
            app.currentDescription ?? .localized("An awesome application")
        ]
        
        let components: [String] = optionalComponents.compactMap { value in
            guard
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                !trimmed.isEmpty
            else {
                return nil
            }
            
            return trimmed
        }
        
        return components.joined(separator: " • ")
    }
}

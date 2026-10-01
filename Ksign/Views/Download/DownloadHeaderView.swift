//
//  DownloadHeaderView.swift
//  Feather
//
//  Created by samara on 16.05.2025.
//

import SwiftUI
import Combine

struct DownloadHeaderView: View {
	@ObservedObject var downloadManager: DownloadManager
	
	var body: some View {
		ZStack {
			if !downloadManager.manualDownloads.isEmpty {
				VStack {
					VStack(spacing: 12) {
						if let firstDownload = downloadManager.manualDownloads.first {
							DownloadItemView(download: firstDownload)
							
							if downloadManager.manualDownloads.count > 1 {
								HStack {
									Spacer()
									Text(verbatim: "+\(downloadManager.manualDownloads.count - 1)")
										.font(.caption)
										.foregroundColor(.secondary)
										.padding(.vertical, 4)
								}
							}
						}
					}
					.padding(.horizontal)
				}
				.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.spring(), value: downloadManager.manualDownloads.count)
	}
}

struct DownloadItemView: View {
    @ObservedObject var download: Download
    private let manager = DownloadManager.shared
	@State private var progress: Double = 0
	@State private var bytesDownloaded: Int64 = 0
	@State private var totalBytes: Int64 = 0
	@State private var unpackageProgress: Double = 0
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(download.fileName)
				.font(.subheadline)
				.lineLimit(1)
			
			ProgressView(value: overallProgress)
				.progressViewStyle(.linear)
			
            HStack {
                Text(verbatim: "\(Int(overallProgress * 100))%")
                    .contentTransition(.numericText())
                Spacer()
                if totalBytes > 0 {
                    Text(verbatim: "\(formatByteCount(bytesDownloaded)) / \(formatByteCount(totalBytes))")
                        .contentTransition(.numericText())
                }
            }
            if !download.onlyArchiving {
                HStack(spacing: 10) {
                    if download.bytesPerSecond > 0 {
                        Text(verbatim: "\(formatByteCount(Int64(download.bytesPerSecond)))/s")
                        if let eta = download.estimatedTimeRemaining {
                            Text(verbatim: "• \(formatDuration(eta)) remaining")
                        }
                    } else if download.isPaused {
                        Text(.localized("Paused"))
                    } else if download.lastError != nil {
                        Text(.localized("Download failed"))
                    }
                    Spacer()
                    if download.lastError != nil {
                        Button { manager.retryDownload(download) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    } else {
                        Button {
                            download.isPaused ? manager.resumeDownload(download) : manager.pauseDownload(download)
                        } label: {
                            Image(systemName: download.isPaused ? "play.fill" : "pause.fill")
                        }
                    }
                    Button(role: .destructive) { manager.cancelDownload(download) } label: {
                        Image(systemName: "xmark")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
		}
		.padding(.vertical, 4)
		.onReceive(download.$progress) { self.progress = $0 }
		.onReceive(download.$bytesDownloaded) { self.bytesDownloaded = $0 }
		.onReceive(download.$totalBytes) { self.totalBytes = $0 }
		.onReceive(download.$unpackageProgress) { self.unpackageProgress = $0 }
	}
	
	private var overallProgress: Double {
		download.onlyArchiving
		? unpackageProgress
		: (0.3 * unpackageProgress) + (0.7 * progress)
	}
	
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(0, seconds)) ?? "—"
    }

	private func formatByteCount(_ bytes: Int64) -> String {
		let formatter = ByteCountFormatter()
		formatter.allowedUnits = [.useAll]
		formatter.countStyle = .file
		return formatter.string(fromByteCount: bytes)
	}
}

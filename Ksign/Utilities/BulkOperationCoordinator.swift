import Foundation
import SwiftUI

struct BulkOperationItem: Identifiable {
    let id: String
    let name: String
    var state: State = .queued
    var error: String?
    enum State { case queued, running, succeeded, failed, cancelled
        var title: String { switch self { case .queued: String(localized: "Queued"); case .running: String(localized: "Working"); case .succeeded: String(localized: "Done"); case .failed: String(localized: "Failed"); case .cancelled: String(localized: "Cancelled") } }
        var icon: String { switch self { case .queued: "clock"; case .running: "arrow.triangle.2.circlepath"; case .succeeded: "checkmark.circle.fill"; case .failed: "xmark.octagon.fill"; case .cancelled: "pause.circle" } }
    }
}

@MainActor final class BulkOperationCoordinator: ObservableObject {
    @Published private(set) var items: [BulkOperationItem]
    @Published private(set) var isRunning = false
    private var cancelled = false
    init(apps: [AppInfoPresentable]) { items = apps.map { BulkOperationItem(id: $0.uuid ?? UUID().uuidString, name: $0.userTitle ?? $0.name ?? String(localized: "Unknown")) } }
    func cancel() { cancelled = true; for index in items.indices where items[index].state == .queued { items[index].state = .cancelled } }
    func run(sign: @escaping (Int, @escaping (Error?) -> Void) -> Void, completion: @escaping () -> Void) {
        guard !isRunning else { return }; isRunning = true; cancelled = false; process(index: 0, sign: sign, completion: completion)
    }
    private func process(index: Int, sign: @escaping (Int, @escaping (Error?) -> Void) -> Void, completion: @escaping () -> Void) {
        guard index < items.count, !cancelled else { isRunning = false; completion(); return }
        items[index].state = .running
        sign(index) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.items[index].state = .failed; self.items[index].error = error.localizedDescription }
                else { self.items[index].state = .succeeded }
                self.process(index: index + 1, sign: sign, completion: completion)
            }
        }
    }
}

struct BulkOperationProgressView: View {
    @ObservedObject var coordinator: BulkOperationCoordinator
    var body: some View {
        List {
            Section { ProgressView(value: Double(coordinator.items.filter { $0.state == .succeeded }.count), total: Double(max(1, coordinator.items.count))) }
            ForEach(coordinator.items) { item in
                HStack { Image(systemName: item.state.icon).foregroundStyle(item.state == .failed ? .red : .secondary); VStack(alignment: .leading) { Text(item.name); Text(item.error ?? item.state.title).font(.caption).foregroundStyle(.secondary) }; Spacer() }
            }
        }.navigationTitle(String(localized: "Operation Progress"))
    }
}

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
    private var runToken = UUID()

    init(apps: [AppInfoPresentable]) {
        items = apps.map { BulkOperationItem(id: $0.uuid ?? UUID().uuidString, name: $0.userTitle ?? $0.name ?? String(localized: "Unknown")) }
    }

    var failedCount: Int { items.filter { $0.state == .failed }.count }

    func cancel() {
        cancelled = true
        runToken = UUID()
        for index in items.indices where items[index].state == .queued { items[index].state = .cancelled }
    }

    func retryFailed(sign: @escaping (Int, @escaping (Error?) -> Void) -> Void, completion: @escaping () -> Void) {
        let indices = items.indices.filter { items[$0].state == .failed }
        run(indices: Array(indices), sign: sign, completion: completion)
    }

    func run(sign: @escaping (Int, @escaping (Error?) -> Void) -> Void, completion: @escaping () -> Void) {
        let indices = items.indices.filter { items[$0].state == .queued }
        run(indices: Array(indices), sign: sign, completion: completion)
    }

    private func run(indices: [Int], sign: @escaping (Int, @escaping (Error?) -> Void) -> Void, completion: @escaping () -> Void) {
        guard !isRunning, !indices.isEmpty else { if indices.isEmpty { completion() }; return }
        isRunning = true
        cancelled = false
        let token = UUID()
        runToken = token
        process(indices: indices, position: 0, token: token, sign: sign, completion: completion)
    }

    private func process(indices: [Int], position: Int, token: UUID, sign: @escaping (Int, @escaping (Error?) -> Void) -> Void, completion: @escaping () -> Void) {
        guard token == runToken else { return }
        guard position < indices.count, !cancelled else { isRunning = false; completion(); return }
        let index = indices[position]
        items[index].state = .running
        items[index].error = nil
        sign(index) { [weak self] error in
            Task { @MainActor in
                guard let self, self.runToken == token else { return }
                if let error { self.items[index].state = .failed; self.items[index].error = error.localizedDescription }
                else { self.items[index].state = .succeeded }
                self.process(indices: indices, position: position + 1, token: token, sign: sign, completion: completion)
            }
        }
    }
}

struct BulkOperationProgressView: View {
    @ObservedObject var coordinator: BulkOperationCoordinator
    let retry: (() -> Void)?
    var body: some View {
        List {
            Section {
                ProgressView(value: Double(coordinator.items.filter { $0.state == .succeeded }.count), total: Double(max(1, coordinator.items.count)))
                if coordinator.failedCount > 0 {
                    Button(String(localized: "Retry Failed")) { retry?() }.disabled(coordinator.isRunning)
                }
                if coordinator.isRunning { Button(String(localized: "Cancel"), role: .destructive) { coordinator.cancel() } }
            }
            ForEach(coordinator.items) { item in
                HStack { Image(systemName: item.state.icon).foregroundStyle(item.state == .failed ? .red : .secondary); VStack(alignment: .leading) { Text(item.name); Text(item.error ?? item.state.title).font(.caption).foregroundStyle(.secondary) }; Spacer() }
            }
        }.navigationTitle(String(localized: "Operation Progress"))
    }
}

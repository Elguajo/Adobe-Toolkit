import SwiftUI
import ToolkitCore

enum Module: String, CaseIterable, Identifiable {
    case overview = "Overview", backup = "Backup", restore = "Restore"
    case cleanup = "Cleanup", diagnose = "Diagnose", repair = "Repair"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .backup: return "externaldrive.badge.plus"
        case .restore: return "arrow.uturn.backward"
        case .cleanup: return "trash"
        case .diagnose: return "stethoscope"
        case .repair: return "wrench.and.screwdriver"
        }
    }

    var operation: ToolkitOperation? {
        switch self {
        case .backup: return .backupScan
        case .cleanup: return .cleanupPreview
        case .diagnose: return .diagnose
        default: return nil
        }
    }

    var detail: String {
        switch self {
        case .overview: return "Your Adobe environment, based on backend observations."
        case .backup: return "Scan locations before selecting what to preserve."
        case .restore: return "Validate a backup before restoring with Safe copy."
        case .cleanup: return "Preview the manifest scope without changing your environment."
        case .diagnose: return "Read-only observations of your Adobe environment."
        case .repair: return "Repair is unavailable in GUI v1."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var module: Module = .overview
    @Published private(set) var available: Set<ToolkitOperation> = []
    @Published private(set) var availabilityReason = "Checking managed backend capability…"
    @Published private(set) var isBusy = false
    @Published private(set) var runningOperation: ToolkitOperation?
    @Published private(set) var latestReport: OperationReport?
    @Published private(set) var reports: [ToolkitOperation: OperationReport] = [:]
    let fixtureMode: Bool
    private let adapter: ToolkitAdapter
    private var task: Task<Void, Never>?

    init(fixtureMode: Bool) {
        self.fixtureMode = fixtureMode
        adapter = fixtureMode ? .fixtures() : .managed()
    }

    func discover() {
        guard !isBusy else { return }
        isBusy = true
        task = Task {
            let availability = await adapter.discover()
            available = availability.operations
            availabilityReason = availability.reason
            isBusy = false
            task = nil
        }
    }

    func run(_ operation: ToolkitOperation) {
        guard !isBusy, available.contains(operation) else { return }
        isBusy = true
        runningOperation = operation
        task = Task {
            let report = await adapter.run(operation)
            latestReport = report
            reports[operation] = report
            runningOperation = nil
            isBusy = false
            task = nil
        }
    }

    func cancel() { task?.cancel() }
}

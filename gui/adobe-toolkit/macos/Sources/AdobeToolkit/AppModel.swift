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
    @Published private(set) var isClosing = false
    @Published private(set) var runningOperation: ToolkitOperation?
    @Published private(set) var latestReport: OperationReport?
    @Published private(set) var reports: [ToolkitOperation: OperationReport] = [:]
    @Published private(set) var selectedBackupIDs: Set<String> = []
    @Published private(set) var scanIsCurrent = false
    @Published private(set) var restoreSource: URL?
    @Published private(set) var sourceIsValidated = false
    let fixtureMode: Bool
    private let adapter: ToolkitAdapter
    private var task: Task<Void, Never>?

    init(fixtureMode: Bool, adapter: ToolkitAdapter? = nil) {
        self.fixtureMode = fixtureMode
        self.adapter = adapter ?? (fixtureMode ? .fixtures() : .managed())
    }

    var backupItems: [ResultItem] {
        guard scanIsCurrent else { return [] }
        return reports[.backupScan]?.envelope?.items ?? []
    }

    var selectedItems: [ResultItem] { backupItems.filter { selectedBackupIDs.contains($0.id) } }
    var canCreateBackup: Bool {
        !isBusy && !isClosing && available.contains(.backupCreate) && scanIsCurrent && !selectedBackupIDs.isEmpty
    }
    var canValidateSource: Bool { !isBusy && !isClosing && available.contains(.restoreValidate) && restoreSource != nil }
    var canRestore: Bool { !isBusy && !isClosing && available.contains(.restoreApply) && sourceIsValidated && restoreSource != nil }

    func selectBackup(_ id: String, selected: Bool) {
        guard !isBusy, !isClosing, backupItems.contains(where: { $0.id == id }) else { return }
        if selected { selectedBackupIDs.insert(id) } else { selectedBackupIDs.remove(id) }
    }

    func chooseRestoreSource(_ source: URL) {
        guard !isBusy, !isClosing, source.isFileURL else { return }
        restoreSource = source.standardizedFileURL.resolvingSymlinksInPath()
        sourceIsValidated = false
    }

    func createBackup() {
        guard canCreateBackup else { return }
        start(.backupCreate(ids: selectedBackupIDs.sorted()))
    }

    func validateSource() {
        guard canValidateSource, let source = restoreSource else { return }
        start(.restoreValidate(source: source))
    }

    func restore() {
        guard canRestore, let source = restoreSource else { return }
        start(.restoreApply(source: source))
    }

    func discover() {
        guard !isBusy, !isClosing else { return }
        isBusy = true
        scanIsCurrent = false
        selectedBackupIDs = []
        sourceIsValidated = false
        task = Task {
            let availability = await adapter.discover()
            available = availability.operations
            availabilityReason = availability.reason
            isBusy = false
            task = nil
        }
    }

    func run(_ operation: ToolkitOperation) {
        switch operation {
        case .backupScan: start(.backupScan)
        case .cleanupPreview: start(.cleanupPreview)
        case .diagnose: start(.diagnose)
        default: return
        }
    }

    private func start(_ request: ToolkitRequest) {
        let operation = request.operation
        guard !isBusy, !isClosing, available.contains(operation) else { return }
        isBusy = true
        runningOperation = operation
        if operation == .backupScan { scanIsCurrent = false; selectedBackupIDs = [] }
        if operation == .restoreValidate || operation == .restoreApply { sourceIsValidated = false }
        task = Task {
            let report = await adapter.run(request: request)
            latestReport = report
            reports[operation] = report
            if operation == .backupScan { scanIsCurrent = report.isSuccess }
            if operation == .backupCreate { scanIsCurrent = false; selectedBackupIDs = [] }
            if operation == .restoreValidate { sourceIsValidated = report.isSuccess }
            runningOperation = nil
            isBusy = false
            task = nil
        }
    }

    func prepareToClose() async {
        isClosing = true
        await cancelAndWait()
    }

    func cancelAndWait() async {
        let running = task
        running?.cancel()
        await running?.value
    }

    func cancel() { task?.cancel() }
}

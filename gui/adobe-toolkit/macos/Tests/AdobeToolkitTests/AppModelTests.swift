import AppKit
import XCTest
@testable import ToolkitCore
@testable import AdobeToolkit

private actor ModelBackend: BackendTransport {
    var validationStatus = "success"
    var scanStatus = "success"
    var suspendCopy = false
    private(set) var copyFile: URL?
    private(set) var calls: [ToolkitOperation] = []

    func configure(validation: String = "success", scan: String = "success", suspend: Bool = false) {
        validationStatus = validation
        scanStatus = scan
        suspendCopy = suspend
    }
    func capabilities() async throws -> BackendReply {
        reply("capabilities", summary: ["operations": ["backup.scan", "backup.create", "restore.validate", "restore.apply"]])
    }
    func execute(_ request: BackendRequest) async throws -> BackendReply {
        let operation = request.operation
        calls.append(operation)
        if case .backupCreate(let file) = request { copyFile = file }
        if operation.mutates && suspendCopy {
            do { try await Task.sleep(nanoseconds: 10_000_000_000) }
            catch { return reply(operation.rawValue, status: "cancelled", code: 2, mutates: true,
                                 summary: ["completed": 1, "currentDestination": "/fixture/partial"]) }
        }
        if operation == .backupScan {
            return reply(operation.rawValue, status: scanStatus, code: scanStatus == "success" ? 0 : 7,
                         items: [["id": String(repeating: "a", count: 64), "category": "preferences", "displayPath": "/fixture",
                                  "fileCount": 3, "bytes": 12]])
        }
        if operation == .restoreValidate {
            return reply(operation.rawValue, status: validationStatus, code: validationStatus == "success" ? 0 : 3)
        }
        return reply(operation.rawValue, status: "partial", code: 6, mutates: true,
                     summary: ["completed": 1, "failed": 1, "currentDestination": "/fixture/partial"])
    }
    private func reply(_ operation: String, status: String = "success", code: Int32 = 0, mutates: Bool = false,
                       summary: [String: Any] = [:], items: [[String: Any]] = []) -> BackendReply {
        let data = try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "operation": operation,
            "status": status, "exitCode": code, "mutates": mutates, "summary": summary, "items": items,
            "warnings": [], "errors": [], "logPath": NSNull()])
        return BackendReply(stdout: data, exitCode: code)
    }
}

final class AppModelTests: XCTestCase {
    @MainActor
    func testNavigationCannotStartSecondOperationAndCancelledReportAllowsRetry() async throws {
        let model = AppModel(fixtureMode: true)
        model.discover()
        try await waitUntilIdle(model)
        XCTAssertEqual(model.available, [.backupScan, .cleanupPreview, .diagnose])
        model.run(.backupCreate)
        XCTAssertFalse(model.isBusy)

        model.run(.diagnose)
        XCTAssertTrue(model.isBusy)
        model.module = .cleanup
        model.run(.cleanupPreview)
        XCTAssertEqual(model.runningOperation, .diagnose)
        model.cancel()
        try await waitUntilIdle(model)
        XCTAssertEqual(model.latestReport?.operation, "diagnose.run")
        XCTAssertEqual(model.latestReport?.status, .cancelled)
        XCTAssertNil(model.reports[.cleanupPreview])

        model.run(.cleanupPreview)
        try await waitUntilIdle(model)
        XCTAssertEqual(model.latestReport?.isSuccess, true)
        XCTAssertEqual(model.reports[.diagnose]?.status, .cancelled)
        XCTAssertEqual(model.reports[.cleanupPreview]?.isSuccess, true)
    }

    @MainActor
    func testBackupSelectionUsesCurrentScanAndCopyAttemptRequiresRescan() async throws {
        let backend = ModelBackend()
        let model = AppModel(fixtureMode: true, adapter: ToolkitAdapter(transport: backend))
        model.discover()
        try await waitUntilIdle(model)
        model.createBackup()
        XCTAssertFalse(model.isBusy)
        model.run(.backupScan)
        try await waitUntilIdle(model)
        let id = try XCTUnwrap(model.backupItems.first?.id)
        model.selectBackup("unknown", selected: true)
        XCTAssertTrue(model.selectedBackupIDs.isEmpty)
        model.selectBackup(id, selected: true)
        XCTAssertTrue(model.canCreateBackup)
        XCTAssertEqual(model.selectedItems.first?.fileCount, 3)
        model.createBackup()
        model.module = .restore
        model.run(.backupScan)
        XCTAssertEqual(model.runningOperation, .backupCreate)
        try await waitUntilIdle(model)
        XCTAssertEqual(model.latestReport?.status, .partial)
        XCTAssertEqual(model.latestReport?.envelope?.summary["currentDestination"], .string("/fixture/partial"))
        XCTAssertFalse(model.canCreateBackup)
        XCTAssertTrue(model.selectedBackupIDs.isEmpty)
        model.run(.backupScan)
        try await waitUntilIdle(model)
        model.selectBackup(id, selected: true)
        XCTAssertTrue(model.canCreateBackup)
        await backend.configure(scan: "failed")
        model.run(.backupScan)
        XCTAssertTrue(model.selectedBackupIDs.isEmpty)
        try await waitUntilIdle(model)
        XCTAssertFalse(model.scanIsCurrent)
        XCTAssertTrue(model.backupItems.isEmpty)
        XCTAssertEqual(model.reports[.backupCreate]?.status, .partial)
    }

    @MainActor
    func testRestoreRequiresSuccessfulValidationAndChangingSourceOrApplyingInvalidatesIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let backend = ModelBackend()
        let model = AppModel(fixtureMode: true, adapter: ToolkitAdapter(transport: backend))
        model.discover()
        try await waitUntilIdle(model)
        XCTAssertFalse(model.canValidateSource)
        model.chooseRestoreSource(root)
        XCTAssertTrue(model.canValidateSource)
        XCTAssertFalse(model.canRestore)
        await backend.configure(validation: "invalid")
        model.validateSource()
        try await waitUntilIdle(model)
        XCTAssertFalse(model.canRestore)
        XCTAssertEqual(model.latestReport?.status, .invalid)
        await backend.configure()
        model.validateSource()
        try await waitUntilIdle(model)
        XCTAssertTrue(model.canRestore)
        model.chooseRestoreSource(other)
        XCTAssertFalse(model.canRestore)
        model.validateSource()
        model.chooseRestoreSource(root)
        XCTAssertEqual(model.restoreSource, other.resolvingSymlinksInPath())
        try await waitUntilIdle(model)
        model.restore()
        try await waitUntilIdle(model)
        XCTAssertEqual(model.latestReport?.status, .partial)
        XCTAssertFalse(model.canRestore)
        XCTAssertEqual(model.restoreSource, other.resolvingSymlinksInPath())
        model.validateSource()
        try await waitUntilIdle(model)
        XCTAssertTrue(model.canRestore)
    }

    @MainActor
    func testCancelAndWaitReturnsOnlyAfterCopyReportAndSelectionCleanup() async throws {
        let backend = ModelBackend()
        let model = AppModel(fixtureMode: true, adapter: ToolkitAdapter(transport: backend))
        model.discover()
        try await waitUntilIdle(model)
        model.run(.backupScan)
        try await waitUntilIdle(model)
        model.selectBackup(try XCTUnwrap(model.backupItems.first?.id), selected: true)
        await backend.configure(suspend: true)
        model.createBackup()
        for _ in 0..<200 {
            if await backend.copyFile != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let captured = await backend.copyFile
        let file = try XCTUnwrap(captured)
        await model.cancelAndWait()
        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        XCTAssertEqual(model.latestReport?.status, .cancelled)
        XCTAssertEqual(model.latestReport?.actualExitCode, 2)
        XCTAssertEqual(model.latestReport?.envelope?.summary["completed"], .number(1))
        XCTAssertFalse(model.canCreateBackup)
        model.run(.backupScan)
        try await waitUntilIdle(model)
        XCTAssertTrue(model.scanIsCurrent)
    }

    @MainActor
    func testWindowCloseWaitsForCancellationAndCleanupAndRejectsNewOperations() async throws {
        _ = NSApplication.shared
        let backend = ModelBackend()
        let model = AppModel(fixtureMode: true, adapter: ToolkitAdapter(transport: backend))
        model.discover()
        try await waitUntilIdle(model)
        model.run(.backupScan)
        try await waitUntilIdle(model)
        model.selectBackup(try XCTUnwrap(model.backupItems.first?.id), selected: true)
        await backend.configure(suspend: true)
        model.createBackup()
        for _ in 0..<200 {
            if await backend.copyFile != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let captured = await backend.copyFile
        let file = try XCTUnwrap(captured)
        let delegate = ToolkitDelegate(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        XCTAssertFalse(delegate.windowShouldClose(window))
        try await waitUntilIdle(model)
        XCTAssertTrue(model.isClosing)
        XCTAssertEqual(model.latestReport?.status, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        model.run(.backupScan)
        model.discover()
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(delegate.windowShouldClose(window))
    }

    @MainActor
    private func waitUntilIdle(_ model: AppModel) async throws {
        for _ in 0..<500 where model.isBusy {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(model.isBusy, "Model did not release the operation lock.")
    }
}

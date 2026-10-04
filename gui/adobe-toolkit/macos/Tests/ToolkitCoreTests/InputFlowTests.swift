import Foundation
import XCTest
@testable import ToolkitCore

private let scanID = String(repeating: "a", count: 64)

private func response(_ operation: ToolkitOperation, status: String = "success", code: Int32 = 0,
                      summary: [String: Any] = [:], scan: Bool = false) -> BackendReply {
    let items: [[String: Any]] = scan ? [["id": scanID, "category": "preferences", "displayPath": "/fixture/settings",
                                         "fileCount": 1, "bytes": 7]] : []
    let data = try! JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1, "operation": operation.rawValue, "status": status, "exitCode": code,
        "mutates": operation.mutates, "summary": summary, "items": items,
        "warnings": ["fixture warning"], "errors": [], "logPath": NSNull()
    ])
    return BackendReply(stdout: data, stderr: Data("fixture stderr".utf8), exitCode: code)
}

private actor InputBackend: BackendTransport {
    enum Mode { case success, partial, malformed, cancelled, launchError, finishedOnCancel }
    var mode: Mode = .success
    var suspendCopy = false
    var failChecks = false
    private(set) var calls: [ToolkitOperation] = []
    private(set) var file: URL?
    private(set) var contents = ""
    private(set) var permissions: Int?
    private(set) var directoryPermissions: Int?
    private(set) var owner: UInt32?
    private(set) var sources: [URL] = []

    func configureCheckFailure(_ flag: Bool) { failChecks = flag }
    func configure(_ mode: Mode, suspend: Bool = false) { self.mode = mode; suspendCopy = suspend }
    func capabilities() async throws -> BackendReply {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "operation": "capabilities", "status": "success", "exitCode": 0,
            "mutates": false, "summary": ["operations": ["backup.scan", "backup.create", "restore.validate", "restore.apply"]],
            "items": [], "warnings": [], "errors": [], "logPath": NSNull()
        ])
        return BackendReply(stdout: data, exitCode: 0)
    }
    func execute(_ request: BackendRequest) async throws -> BackendReply {
        let operation = request.operation
        calls.append(operation)
        switch request {
        case .backupCreate(let url):
            file = url
            contents = try String(contentsOf: url, encoding: .utf8)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
            owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
            directoryPermissions = (try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue
        case .restoreValidate(let source), .restoreApply(let source): sources.append(source)
        default: break
        }
        if operation == .backupScan {
            return failChecks ? response(operation, status: "failed", code: 7) : response(operation, scan: true)
        }
        if operation == .restoreValidate {
            return failChecks ? response(operation, status: "invalid", code: 3) : response(operation)
        }
        if suspendCopy {
            do { try await Task.sleep(nanoseconds: 10_000_000_000) }
            catch {
                if mode == .finishedOnCancel {
                    return response(operation, summary: ["currentDestination": "/fixture/completed", "completed": 1])
                }
                return response(operation, status: "cancelled", code: 2, summary: ["currentDestination": "/fixture/partial", "completed": 1])
            }
        }
        switch mode {
        case .success, .finishedOnCancel: return response(operation)
        case .partial: return response(operation, status: "partial", code: 6, summary: ["currentDestination": "/fixture/partial", "completed": 1, "failed": 1])
        case .cancelled: return response(operation, status: "cancelled", code: 2, summary: ["currentDestination": "/fixture/partial"])
        case .malformed: return BackendReply(stdout: Data("malformed copy output".utf8), stderr: Data("copy diagnostic".utf8), exitCode: 7)
        case .launchError: throw CocoaError(.executableNotLoadable)
        }
    }
}

final class InputFlowTests: XCTestCase {
    func testSelectionRequiresLatestSuccessfulScanAndRejectsUnknownOrDuplicateIDs() async {
        let backend = InputBackend()
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        let missing = await adapter.run(request: .backupCreate(ids: [scanID]))
        XCTAssertEqual(missing.status, .invalid)
        _ = await adapter.run(.backupScan)
        for ids in [[], [scanID, scanID], ["/raw/path"], ["unknown\nID"]] {
            let invalid = await adapter.run(request: .backupCreate(ids: ids))
            XCTAssertEqual(invalid.status, .invalid)
        }
        let calls = await backend.calls
        XCTAssertEqual(calls, [.backupScan])
        let created = await adapter.run(request: .backupCreate(ids: [scanID]))
        XCTAssertTrue(created.isSuccess, created.text)
        let stale = await adapter.run(request: .backupCreate(ids: [scanID]))
        XCTAssertEqual(stale.status, .invalid)
        _ = await adapter.run(.backupScan)
        let retry = await adapter.run(request: .backupCreate(ids: [scanID]))
        XCTAssertTrue(retry.isSuccess)
    }

    func testOwnerOnlySelectionIsRemovedOnSuccessPartialCancelledMalformedAndLaunchError() async throws {
        for mode in [InputBackend.Mode.success, .partial, .cancelled, .malformed, .launchError] {
            let backend = InputBackend()
            let adapter = ToolkitAdapter(transport: backend)
            _ = await adapter.discover()
            _ = await adapter.run(.backupScan)
            await backend.configure(mode)
            let report = await adapter.run(request: .backupCreate(ids: [scanID]))
            let capturedFile = await backend.file
            let file = try XCTUnwrap(capturedFile)
            let contents = await backend.contents
            let permissions = await backend.permissions
            let directoryPermissions = await backend.directoryPermissions
            let owner = await backend.owner
            XCTAssertEqual(contents, scanID + "\n")
            XCTAssertEqual(permissions, 0o600)
            XCTAssertEqual(directoryPermissions, 0o700)
            XCTAssertEqual(owner, getuid())
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
            switch mode {
            case .success, .finishedOnCancel: XCTAssertTrue(report.isSuccess)
            case .partial:
                XCTAssertEqual(report.status, .partial)
                XCTAssertEqual(report.envelope?.summary["completed"], .number(1))
                XCTAssertEqual(report.envelope?.summary["currentDestination"], .string("/fixture/partial"))
            case .cancelled: XCTAssertEqual(report.envelope?.status, .cancelled)
            case .malformed:
                XCTAssertEqual(report.status, .failed)
                XCTAssertEqual(report.stdout, "malformed copy output")
                XCTAssertEqual(report.stderr, "copy diagnostic")
                XCTAssertEqual(report.actualExitCode, 7)
            case .launchError: XCTAssertEqual(report.status, .failed)
            }
        }
    }

    func testHostCancellationRetainsEnvelopeCleansSelectionAndUnlocksRetry() async throws {
        let backend = InputBackend()
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        _ = await adapter.run(.backupScan)
        await backend.configure(.success, suspend: true)
        let running = Task { await adapter.run(request: .backupCreate(ids: [scanID])) }
        for _ in 0..<200 {
            if await backend.file != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let capturedFile = await backend.file
        let file = try XCTUnwrap(capturedFile)
        let second = await adapter.run(.backupScan)
        XCTAssertEqual(second.status, .unavailable)
        running.cancel()
        let report = await running.value
        XCTAssertEqual(report.status, .cancelled)
        XCTAssertEqual(report.actualExitCode, 2)
        XCTAssertEqual(report.envelope?.summary["completed"], .number(1))
        XCTAssertFalse(report.isSuccess)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        await backend.configure(.success)
        _ = await adapter.run(.backupScan)
        let retried = await adapter.run(request: .backupCreate(ids: [scanID]))
        XCTAssertTrue(retried.isSuccess)
    }

    func testHostCancellationRacingCompletedCopyRetainsCountersWithoutSuccess() async throws {
        let backend = InputBackend()
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        _ = await adapter.run(.backupScan)
        await backend.configure(.finishedOnCancel, suspend: true)
        let running = Task { await adapter.run(request: .backupCreate(ids: [scanID])) }
        for _ in 0..<200 {
            if await backend.file != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let captured = await backend.file
        let file = try XCTUnwrap(captured)
        running.cancel()
        let report = await running.value
        XCTAssertEqual(report.status, .cancelled)
        XCTAssertEqual(report.actualExitCode, 0)
        XCTAssertFalse(report.isSuccess)
        XCTAssertEqual(report.envelope?.summary["completed"], .number(1))
        XCTAssertEqual(report.envelope?.summary["currentDestination"], .string("/fixture/completed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
    }

    func testRestoreCanonicalizesFolderAndRequiresValidationOfSameSourceBeforeEachApply() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("backup folder ; $literal")
        let other = root.appendingPathComponent("other")
        let link = root.appendingPathComponent("source-link")
        for folder in [source, other] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let backend = InputBackend()
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        let unvalidated = await adapter.run(request: .restoreApply(source: source))
        XCTAssertEqual(unvalidated.status, .invalid)
        let validation = await adapter.run(request: .restoreValidate(source: link))
        XCTAssertTrue(validation.isSuccess)
        let wrong = await adapter.run(request: .restoreApply(source: other))
        XCTAssertEqual(wrong.status, .invalid)
        _ = await adapter.run(request: .restoreValidate(source: source))
        await backend.configure(.partial)
        let copy = await adapter.run(request: .restoreApply(source: source))
        XCTAssertEqual(copy.status, .partial)
        let retry = await adapter.run(request: .restoreApply(source: source))
        XCTAssertEqual(retry.status, .invalid)
        _ = await adapter.run(request: .restoreValidate(source: source))
        await backend.configure(.success)
        let success = await adapter.run(request: .restoreApply(source: source))
        XCTAssertTrue(success.isSuccess)
        let sources = await backend.sources
        XCTAssertTrue(sources.allSatisfy { $0 == source.resolvingSymlinksInPath() })
        let invalid = await adapter.run(request: .restoreValidate(source: URL(string: "https://example.com")!))
        XCTAssertEqual(invalid.status, .invalid)
        let blocked = await adapter.run(request: .restoreApply(source: source))
        XCTAssertEqual(blocked.status, .invalid)
    }

    func testFailedScanAndValidationRevokePreviouslyAcceptedInputs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = InputBackend()
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        _ = await adapter.run(.backupScan)
        _ = await adapter.run(request: .restoreValidate(source: root))
        await backend.configureCheckFailure(true)
        let scan = await adapter.run(.backupScan)
        XCTAssertEqual(scan.status, .failed)
        let create = await adapter.run(request: .backupCreate(ids: [scanID]))
        XCTAssertEqual(create.status, .invalid)
        let validation = await adapter.run(request: .restoreValidate(source: root))
        XCTAssertEqual(validation.status, .invalid)
        let apply = await adapter.run(request: .restoreApply(source: root))
        XCTAssertEqual(apply.status, .invalid)
        let calls = await backend.calls
        XCTAssertFalse(calls.contains(.backupCreate))
        XCTAssertFalse(calls.contains(.restoreApply))
    }

    func testTypedInputRequestsCannotBypassCapabilityDiscovery() async {
        let backend = InputBackend()
        let adapter = ToolkitAdapter(transport: backend)
        for request in [ToolkitRequest.backupCreate(ids: [scanID]), .restoreValidate(source: URL(fileURLWithPath: "/tmp")),
                        .restoreApply(source: URL(fileURLWithPath: "/tmp"))] {
            let report = await adapter.run(request: request)
            XCTAssertEqual(report.status, .unavailable)
        }
        let calls = await backend.calls
        let file = await backend.file
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(file)
    }

    func testSelectionRejectsLineInjectionAndOversizeBeforeCreatingFiles() {
        for ids in [["a\nb"], ["nul\0ID"], [""], [String(repeating: "a", count: 1_048_576)]] {
            XCTAssertThrowsError(try SelectionFile(ids: ids))
        }
    }
}

import Foundation
import XCTest
@testable import ToolkitCore

private func envelope(operation: String, status: String = "success", code: Int32 = 0,
                      summary: [String: Any] = [:], items: [[String: Any]] = []) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1, "operation": operation, "status": status, "exitCode": code,
        "mutates": false, "summary": summary, "items": items,
        "warnings": [], "errors": [], "logPath": NSNull()
    ])
}

private actor RecordingBackend: BackendTransport {
    let capabilityReply: BackendReply
    let operationReply: BackendReply
    let delay: UInt64
    private(set) var requests: [ToolkitOperation] = []
    private(set) var probes = 0

    init(reply: BackendReply, capability: BackendReply? = nil, delay: UInt64 = 0) {
        operationReply = reply
        capabilityReply = capability ?? BackendReply(stdout: envelope(operation: "capabilities", summary: [
            "operations": ["backup.scan", "backup.create", "restore.validate", "restore.apply", "cleanup.preview", "diagnose.run"]
        ]), exitCode: 0)
        self.delay = delay
    }

    func capabilities() async throws -> BackendReply { probes += 1; return capabilityReply }
    func execute(_ operation: ToolkitOperation) async throws -> BackendReply {
        requests.append(operation)
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        return operationReply
    }
}

final class AdapterTests: XCTestCase {
    func testUnsupportedOperationsNeverProbeOrExecute() async {
        let backend = RecordingBackend(reply: BackendReply(stdout: Data(), exitCode: 0))
        let adapter = ToolkitAdapter(transport: backend)
        for operation in [ToolkitOperation.cleanupApply, .repairPreview, .repairApply] {
            let report = await adapter.run(operation)
            XCTAssertEqual(report.status, .unsupported)
            XCTAssertFalse(report.isSuccess)
            XCTAssertNil(report.actualExitCode)
        }
        let requests = await backend.requests
        let probes = await backend.probes
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(probes, 0)
    }

    func testOperationCannotExecuteBeforeCapabilityDiscovery() async {
        let backend = RecordingBackend(reply: BackendReply(stdout: envelope(operation: "cleanup.preview"), exitCode: 0))
        let adapter = ToolkitAdapter(transport: backend)
        let report = await adapter.run(.cleanupPreview)
        XCTAssertEqual(report.status, .unavailable)
        let requests = await backend.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testInputBearingOperationsRemainUnavailableEvenWhenAdvertised() async {
        let backend = RecordingBackend(reply: BackendReply(stdout: Data(), exitCode: 0))
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        for operation in [ToolkitOperation.backupCreate, .restoreValidate, .restoreApply] {
            let report = await adapter.run(operation)
            XCTAssertEqual(report.status, .unavailable)
        }
        let requests = await backend.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testInvalidCapabilitiesFailClosed() async throws {
        let valid = envelope(operation: "capabilities", summary: ["operations": ["cleanup.preview"]])
        var wrongVersion = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        wrongVersion["schemaVersion"] = 2
        let cases: [BackendReply] = [
            BackendReply(stdout: Data("Legacy menu".utf8), exitCode: 0),
            BackendReply(stdout: valid, exitCode: 7),
            BackendReply(stdout: try JSONSerialization.data(withJSONObject: wrongVersion), exitCode: 0),
            BackendReply(stdout: envelope(operation: "capabilities"), exitCode: 0),
            BackendReply(stdout: envelope(operation: "capabilities", summary: ["operations": ["cleanup.apply"]]), exitCode: 0),
            BackendReply(stdout: envelope(operation: "capabilities", summary: ["operations": ["unknown"]]), exitCode: 0),
            BackendReply(stdout: envelope(operation: "capabilities", summary: ["operations": ["cleanup.preview", "cleanup.preview"]]), exitCode: 0)
        ]
        for capability in cases {
            let backend = RecordingBackend(reply: BackendReply(stdout: valid, exitCode: 0), capability: capability)
            let adapter = ToolkitAdapter(transport: backend)
            let available = await adapter.discover()
            XCTAssertTrue(available.operations.isEmpty)
            let report = await adapter.run(.cleanupPreview)
            XCTAssertEqual(report.status, .unavailable)
            let requests = await backend.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testOnlyAdvertisedOperationsAreAvailable() async {
        let backend = RecordingBackend(reply: BackendReply(stdout: Data(), exitCode: 7), capability:
            BackendReply(stdout: envelope(operation: "capabilities", summary: ["operations": ["cleanup.preview"]]), exitCode: 0))
        let adapter = ToolkitAdapter(transport: backend)
        let availability = await adapter.discover()
        XCTAssertEqual(availability.operations, [.cleanupPreview])
        let report = await adapter.run(.diagnose)
        XCTAssertEqual(report.status, .unavailable)
        let requests = await backend.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testFixtureSuccessCancellationFailureAndPreviewImmutability() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appendingPathComponent("Adobe-fixture.plist")
        try Data("preserve".utf8).write(to: sentinel)
        let before = try Data(contentsOf: sentinel)
        let adapter = ToolkitAdapter.fixtures()
        let availability = await adapter.discover()
        XCTAssertEqual(availability.operations, [.backupScan, .cleanupPreview, .diagnose])
        let preview = await adapter.run(.cleanupPreview)
        XCTAssertTrue(preview.isSuccess)
        XCTAssertEqual(preview.envelope?.items.first?.id, "adobe-prefs")
        XCTAssertEqual(preview.envelope?.warnings, ["Fixture warning"])
        XCTAssertEqual(try Data(contentsOf: sentinel), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Adobe-fixture.plist"])
        let cancelled = await adapter.run(.backupScan)
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.actualExitCode, 2)
        XCTAssertFalse(cancelled.isSuccess)
        let failed = await adapter.run(.diagnose)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.envelope?.errors, ["Fixture backend failure"])
        XCTAssertFalse(failed.isSuccess)
    }

    func testMalformedAndInconsistentResultsRetainRawOutputAndActualExit() async throws {
        let valid = envelope(operation: "cleanup.preview")
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var mutations: [[String: Any]] = []
        for (key, value) in [
            ("schemaVersion", 2 as Any), ("operation", "diagnose.run" as Any),
            ("mutates", true as Any), ("exitCode", 7 as Any),
            ("status", "unknown" as Any), ("warnings", [1] as Any),
            ("logPath", "relative/log.txt" as Any), ("exitCode", true as Any)
        ] {
            var mutated = base
            mutated[key] = value
            mutations.append(mutated)
        }
        var missing = base
        missing.removeValue(forKey: "logPath")
        mutations.append(missing)
        var wrongItem = base
        wrongItem["items"] = [["id": "invalid", "category": "preferences"]]
        mutations.append(wrongItem)
        var duplicate = base
        duplicate["items"] = Array(repeating: ["id": "same", "category": "preferences", "state": "observed", "message": "fixture"], count: 2)
        mutations.append(duplicate)
        var concatenated = valid
        concatenated.append(valid)
        let invalidData = try mutations.map { try JSONSerialization.data(withJSONObject: $0) }
            + [Data("{invalid JSON".utf8), Data([0xff]), concatenated]
        for data in invalidData {
            let backend = RecordingBackend(reply: BackendReply(stdout: data, stderr: Data("diagnostic".utf8), exitCode: 0))
            let adapter = ToolkitAdapter(transport: backend)
            _ = await adapter.discover()
            let report = await adapter.run(.cleanupPreview)
            XCTAssertEqual(report.status, .failed)
            XCTAssertFalse(report.isSuccess)
            XCTAssertNil(report.envelope)
            XCTAssertEqual(report.actualExitCode, 0)
            XCTAssertEqual(report.stdout, String(decoding: data, as: UTF8.self))
            XCTAssertEqual(report.stderr, "diagnostic")
        }
    }

    func testActualNonzeroExitCannotProduceSuccess() async {
        let backend = RecordingBackend(reply: BackendReply(stdout: envelope(operation: "cleanup.preview"), exitCode: 7))
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        let report = await adapter.run(.cleanupPreview)
        XCTAssertFalse(report.isSuccess)
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.actualExitCode, 7)
    }

    func testSignalledTerminationCannotBeAcceptedAsNormalExit() async {
        let backend = RecordingBackend(reply: BackendReply(
            stdout: envelope(operation: "cleanup.preview", status: "cancelled", code: 2),
            exitCode: 2, wasSignalled: true))
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        let report = await adapter.run(.cleanupPreview)
        XCTAssertEqual(report.status, .failed)
        XCTAssertNil(report.envelope)
    }

    func testPartialResultIsRetainedWithoutSuccess() async {
        let backend = RecordingBackend(reply: BackendReply(stdout: envelope(operation: "cleanup.preview", status: "partial", code: 6), exitCode: 6))
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        let report = await adapter.run(.cleanupPreview)
        XCTAssertEqual(report.status, .partial)
        XCTAssertEqual(report.envelope?.status, .partial)
        XCTAssertFalse(report.isSuccess)
    }

    func testConcurrentOperationIsRejectedAndCancellationUnlocksRetry() async throws {
        let backend = RecordingBackend(reply: BackendReply(stdout: envelope(operation: "cleanup.preview"), exitCode: 0), delay: 200_000_000)
        let adapter = ToolkitAdapter(transport: backend)
        _ = await adapter.discover()
        let first = Task { await adapter.run(.cleanupPreview) }
        for _ in 0..<100 {
            if !(await backend.requests).isEmpty { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let second = await adapter.run(.cleanupPreview)
        XCTAssertEqual(second.status, .unavailable)
        first.cancel()
        let cancelled = await first.value
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertFalse(cancelled.isSuccess)
        let retried = await adapter.run(.cleanupPreview)
        XCTAssertTrue(retried.isSuccess)
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testBackupScanItemsRequireTypedCountersAndPaths() async {
        let reply = BackendReply(stdout: envelope(operation: "backup.scan", items: [
            ["id": "prefs", "category": "preferences", "displayPath": "~/fixture", "fileCount": -1, "bytes": 7]
        ]), exitCode: 0)
        let adapter = ToolkitAdapter(transport: RecordingBackend(reply: reply))
        _ = await adapter.discover()
        let report = await adapter.run(.backupScan)
        XCTAssertEqual(report.status, .failed)
    }
}

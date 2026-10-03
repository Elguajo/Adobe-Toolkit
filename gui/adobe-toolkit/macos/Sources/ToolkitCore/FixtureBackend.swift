import Foundation

struct FixtureBackend: BackendTransport {
    func capabilities() async throws -> BackendReply {
        BackendReply(stdout: Data("""
        {"schemaVersion":1,"operation":"capabilities","status":"success","exitCode":0,
        "mutates":false,"summary":{"operations":["backup.scan","cleanup.preview","diagnose.run"]},
        "items":[],"warnings":[],"errors":[],"logPath":null}
        """.utf8), exitCode: 0)
    }

    func execute(_ operation: ToolkitOperation) async throws -> BackendReply {
        let name: String
        let exitCode: Int32
        switch operation {
        case .backupScan: name = "backup-scan-cancelled"; exitCode = 2
        case .cleanupPreview: name = "cleanup-preview-success"; exitCode = 0
        case .diagnose: name = "diagnose-failed"; exitCode = 7
        default: throw ContractError.invalid("Fixture operation is unavailable.")
        }
        // A visible preparation interval makes navigation/locking/cancellation testable.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        guard let file = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw ContractError.invalid("Required fixture resource is missing.")
        }
        return BackendReply(stdout: try Data(contentsOf: file), exitCode: exitCode)
    }
}

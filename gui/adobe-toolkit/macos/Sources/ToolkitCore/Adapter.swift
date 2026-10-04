import Foundation

public struct BackendReply: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
    public let wasSignalled: Bool

    public init(stdout: Data, stderr: Data = Data(), exitCode: Int32, wasSignalled: Bool = false) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.wasSignalled = wasSignalled
    }
}

// Internal transport injection is for tests and explicit fixture mode only.
protocol BackendTransport: Sendable {
    func capabilities() async throws -> BackendReply
    func execute(_ request: BackendRequest) async throws -> BackendReply
}

extension BackendTransport {
    func execute(_ operation: ToolkitOperation) async throws -> BackendReply {
        try await execute(.observation(operation))
    }
}

public struct Availability: Sendable {
    public let operations: Set<ToolkitOperation>
    public let reason: String
}

public actor ToolkitAdapter {
    private let transport: any BackendTransport
    private var operations: Set<ToolkitOperation> = []
    private var busy = false
    private var scanIDs: Set<String> = []
    private var validatedSource: URL?

    init(transport: any BackendTransport) { self.transport = transport }

    public static func managed() -> ToolkitAdapter {
        ToolkitAdapter(transport: ManagedBackend.bundled)
    }

    public static func fixtures() -> ToolkitAdapter {
        ToolkitAdapter(transport: FixtureBackend())
    }

    public func discover() async -> Availability {
        guard !busy else { return Availability(operations: [], reason: "An operation is already running.") }
        busy = true
        operations = []
        scanIDs = []
        validatedSource = nil
        defer { busy = false }
        do {
            let reply = try await transport.capabilities()
            try Task.checkCancellation()
            let result = try ResultEnvelope.validate(reply, expected: "capabilities", mutates: false)
            guard result.status == .success,
                  case .array(let advertised)? = result.summary["operations"] else {
                throw ContractError.invalid("Backend did not advertise v1 operations.")
            }
            var supported: Set<ToolkitOperation> = []
            for entry in advertised {
                guard case .string(let name) = entry, let operation = ToolkitOperation(rawValue: name),
                      !operation.unsupported, !supported.contains(operation) else {
                    throw ContractError.invalid("Invalid or unsupported capability.")
                }
                supported.insert(operation)
            }
            operations = supported
            return Availability(operations: operations, reason: operations.isEmpty
                                ? "No operations available in this shell." : "v1 capability validated.")
        } catch {
            return Availability(operations: [], reason: error.localizedDescription)
        }
    }

    public func run(_ operation: ToolkitOperation) async -> OperationReport {
        switch operation {
        case .backupScan: return await run(request: .backupScan)
        case .cleanupPreview: return await run(request: .cleanupPreview)
        case .diagnose: return await run(request: .diagnose)
        default:
            return report(operation, operation.unsupported ? .unsupported : .invalid,
                          operation.unsupported ? "This operation is unavailable in GUI v1." : "Validated input is required.")
        }
    }

    public func run(request: ToolkitRequest) async -> OperationReport {
        let operation = request.operation
        guard operations.contains(operation) else {
            return report(operation, .unavailable, "This operation has no supported v1 capability.")
        }
        guard !busy else { return report(operation, .unavailable, "An operation is already running.") }
        busy = true
        defer { busy = false }
        var selection: SelectionFile?
        var reply: BackendReply?
        var invoking = false
        var result: ResultEnvelope?
        var outcome: OperationReport
        do {
            if operation == .backupScan { scanIDs = [] }
            if operation == .restoreValidate { validatedSource = nil }
            try Task.checkCancellation()
            let backendRequest: BackendRequest
            switch request {
            case .backupScan:
                backendRequest = .observation(.backupScan)
            case .cleanupPreview: backendRequest = .observation(.cleanupPreview)
            case .diagnose: backendRequest = .observation(.diagnose)
            case .backupCreate(let ids):
                guard !ids.isEmpty, Set(ids).count == ids.count, Set(ids).isSubset(of: scanIDs) else {
                    throw ContractError.invalid("Select unique IDs from the latest successful scan; rescan before retrying.")
                }
                // A mutation attempt consumes the scan even if preparation fails.
                scanIDs = []
                let file = try SelectionFile(ids: ids)
                selection = file
                backendRequest = .backupCreate(selectionFile: file.url)
            case .restoreValidate(let source):
                backendRequest = .restoreValidate(source: try canonicalSource(source))
            case .restoreApply(let source):
                let priorSource = validatedSource
                validatedSource = nil
                let canonical = try canonicalSource(source)
                guard priorSource == canonical else {
                    throw ContractError.invalid("Validate this source before Safe copy; validate again before retrying.")
                }
                backendRequest = .restoreApply(source: canonical)
            }
            invoking = true
            let received = try await transport.execute(backendRequest)
            reply = received
            let validated = try ResultEnvelope.validate(received, expected: operation.rawValue, mutates: operation.mutates)
            result = validated
            try Task.checkCancellation()
            if validated.status == .success {
                if operation == .backupScan { scanIDs = Set(validated.items.map(\.id)) }
                if case .restoreValidate(let source) = backendRequest { validatedSource = source }
            }
            outcome = report(operation, validated.status, "Backend result validated.", reply, validated)
        } catch is CancellationError {
            // Preserve validated interrupted counters and destination, even when the host requested cancellation.
            outcome = report(operation, .cancelled, "Cancelled; partial files may remain. No rollback is implied.", reply,
                             result)
        } catch let error as ContractError where !invoking {
            outcome = report(operation, .invalid, error.localizedDescription)
        } catch {
            outcome = report(operation, Task.isCancelled ? .cancelled : .failed,
                             Task.isCancelled ? "Cancelled; partial files may remain. No rollback is implied." : error.localizedDescription, reply)
        }
        do { try selection?.remove() }
        catch {
            outcome = report(operation, .failed, "Selection-file cleanup failed: \(error.localizedDescription)", reply, result)
        }
        return outcome
    }

    private func canonicalSource(_ source: URL) throws -> URL {
        guard source.isFileURL, !source.path.contains("\0"), source.path.hasPrefix("/") else {
            throw ContractError.invalid("Restore source must be a local folder.")
        }
        let canonical = source.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? canonical.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw ContractError.invalid("Restore source must be an existing folder.")
        }
        return canonical
    }

    private func report(_ operation: ToolkitOperation, _ status: ResultStatus, _ message: String,
                        _ reply: BackendReply? = nil, _ envelope: ResultEnvelope? = nil) -> OperationReport {
        OperationReport(timestamp: Date(), operation: operation.rawValue, status: status,
                        actualExitCode: reply?.exitCode, envelope: envelope,
                        stdout: reply.map { String(decoding: $0.stdout, as: UTF8.self) } ?? "",
                        stderr: reply.map { String(decoding: $0.stderr, as: UTF8.self) } ?? "", message: message)
    }
}

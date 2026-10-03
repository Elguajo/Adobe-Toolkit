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
    func execute(_ operation: ToolkitOperation) async throws -> BackendReply
}

public struct Availability: Sendable {
    public let operations: Set<ToolkitOperation>
    public let reason: String
}

public actor ToolkitAdapter {
    private let transport: any BackendTransport
    private var operations: Set<ToolkitOperation> = []
    private var busy = false

    init(transport: any BackendTransport) { self.transport = transport }

    public static func managed() -> ToolkitAdapter {
        ToolkitAdapter(transport: ManagedBackend(resourceRoot: Bundle.module.resourceURL))
    }

    public static func fixtures() -> ToolkitAdapter {
        ToolkitAdapter(transport: FixtureBackend())
    }

    public func discover() async -> Availability {
        guard !busy else { return Availability(operations: [], reason: "An operation is already running.") }
        busy = true
        operations = []
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
            operations = supported.filter(\.availableInShell)
            return Availability(operations: operations, reason: operations.isEmpty
                                ? "No operations available in this shell." : "v1 capability validated.")
        } catch {
            return Availability(operations: [], reason: error.localizedDescription)
        }
    }

    public func run(_ operation: ToolkitOperation) async -> OperationReport {
        if operation.unsupported {
            return report(operation, .unsupported, "This operation is unavailable in GUI v1.")
        }
        guard operation.availableInShell, operations.contains(operation) else {
            return report(operation, .unavailable, "This operation has no supported v1 capability in this shell.")
        }
        guard !busy else { return report(operation, .unavailable, "An operation is already running.") }
        busy = true
        defer { busy = false }
        var reply: BackendReply?
        do {
            try Task.checkCancellation()
            let received = try await transport.execute(operation)
            reply = received
            try Task.checkCancellation()
            let result = try ResultEnvelope.validate(received, expected: operation.rawValue, mutates: false)
            return OperationReport(timestamp: Date(), operation: operation.rawValue, status: result.status,
                                   actualExitCode: received.exitCode, envelope: result,
                                   stdout: String(decoding: received.stdout, as: UTF8.self),
                                   stderr: String(decoding: received.stderr, as: UTF8.self),
                                   message: "Backend result validated.")
        } catch is CancellationError {
            return report(operation, .cancelled, "Cancelled; no success or rollback is implied.", reply)
        } catch {
            return report(operation, .failed, error.localizedDescription, reply)
        }
    }

    private func report(_ operation: ToolkitOperation, _ status: ResultStatus, _ message: String,
                        _ reply: BackendReply? = nil) -> OperationReport {
        OperationReport(timestamp: Date(), operation: operation.rawValue, status: status,
                        actualExitCode: reply?.exitCode, envelope: nil,
                        stdout: reply.map { String(decoding: $0.stdout, as: UTF8.self) } ?? "",
                        stderr: reply.map { String(decoding: $0.stderr, as: UTF8.self) } ?? "", message: message)
    }
}

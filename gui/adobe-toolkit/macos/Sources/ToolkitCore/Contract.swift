import Foundation

public enum ToolkitOperation: String, CaseIterable, Codable, Sendable {
    case backupScan = "backup.scan"
    case backupCreate = "backup.create"
    case restoreValidate = "restore.validate"
    case restoreApply = "restore.apply"
    case cleanupPreview = "cleanup.preview"
    case diagnose = "diagnose.run"
    case cleanupApply = "cleanup.apply"
    case repairPreview = "repair.preview"
    case repairApply = "repair.apply"

    public var unsupported: Bool {
        [.cleanupApply, .repairPreview, .repairApply].contains(self)
    }

    public var availableInShell: Bool { !unsupported }

    public var mutates: Bool { [.backupCreate, .restoreApply].contains(self) }

    var arguments: [String]? {
        switch self {
        case .backupScan: return ["--ui-json", "backup-scan"]
        case .cleanupPreview: return ["--ui-json", "cleanup-preview"]
        case .diagnose: return ["--ui-json", "diagnose"]
        default: return nil
        }
    }
}

// UI callers supply data, never backend arguments or a selection-file path.
public enum ToolkitRequest: Sendable {
    case backupScan
    case backupCreate(ids: [String])
    case restoreValidate(source: URL)
    case restoreApply(source: URL)
    case cleanupPreview
    case diagnose

    public var operation: ToolkitOperation {
        switch self {
        case .backupScan: return .backupScan
        case .backupCreate: return .backupCreate
        case .restoreValidate: return .restoreValidate
        case .restoreApply: return .restoreApply
        case .cleanupPreview: return .cleanupPreview
        case .diagnose: return .diagnose
        }
    }
}

// Constructed only after adapter validation. The transport has no public executor.
enum BackendRequest: Sendable {
    case observation(ToolkitOperation)
    case backupCreate(selectionFile: URL)
    case restoreValidate(source: URL)
    case restoreApply(source: URL)

    var operation: ToolkitOperation {
        switch self {
        case .observation(let operation): return operation
        case .backupCreate: return .backupCreate
        case .restoreValidate: return .restoreValidate
        case .restoreApply: return .restoreApply
        }
    }

    var arguments: [String]? {
        switch self {
        case .observation(let operation): return operation.arguments
        case .backupCreate(let file): return ["--ui-json", "backup-create", "--selection-file", file.path]
        case .restoreValidate(let source): return ["--ui-json", "restore-validate", "--source", source.path]
        case .restoreApply(let source): return ["--ui-json", "restore-apply", "--source", source.path]
        }
    }
}

public enum ResultStatus: String, Codable, Sendable {
    case success, cancelled, invalid, unavailable, unsupported, partial, failed
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let flag = try? value.decode(Bool.self) { self = .bool(flag) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let flag): try value.encode(flag)
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .null: try value.encodeNil()
        }
    }

    public var display: String {
        switch self {
        case .string(let string): return string
        case .number(let number): return String(format: "%g", number)
        case .bool(let flag): return String(flag)
        case .null: return "—"
        case .object, .array:
            let data = try? JSONEncoder().encode(self)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "—"
        }
    }
}

public struct ResultItem: Codable, Identifiable, Sendable {
    public let id: String
    public let category: String
    public let state: String?
    public let displayPath: String?
    public let message: String?
    public let fileCount: Int?
    public let bytes: Int64?
}

public struct ResultEnvelope: Decodable, Sendable {
    public let schemaVersion: Int
    public let operation: String
    public let status: ResultStatus
    public let exitCode: Int32
    public let mutates: Bool
    public let summary: [String: JSONValue]
    public let items: [ResultItem]
    public let warnings: [String]
    public let errors: [String]
    public let logPath: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, operation, status, exitCode, mutates, summary, items, warnings, errors, logPath
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try fields.decode(Int.self, forKey: .schemaVersion)
        operation = try fields.decode(String.self, forKey: .operation)
        status = try fields.decode(ResultStatus.self, forKey: .status)
        exitCode = try fields.decode(Int32.self, forKey: .exitCode)
        mutates = try fields.decode(Bool.self, forKey: .mutates)
        summary = try fields.decode([String: JSONValue].self, forKey: .summary)
        items = try fields.decode([ResultItem].self, forKey: .items)
        warnings = try fields.decode([String].self, forKey: .warnings)
        errors = try fields.decode([String].self, forKey: .errors)
        guard fields.contains(.logPath) else { throw ContractError.invalid("Missing logPath field.") }
        logPath = try fields.decodeIfPresent(String.self, forKey: .logPath)
    }

    static func validate(_ reply: BackendReply, expected: String, mutates: Bool) throws -> ResultEnvelope {
        guard String(data: reply.stdout, encoding: .utf8) != nil else {
            throw ContractError.invalid("Backend output is not UTF-8.")
        }
        let result = try JSONDecoder().decode(Self.self, from: reply.stdout)
        guard !reply.wasSignalled, result.schemaVersion == 1, result.operation == expected,
              result.exitCode == reply.exitCode, result.mutates == mutates,
              (result.status == .success) == (reply.exitCode == 0),
              (0...7).contains(reply.exitCode), reply.exitCode != 1 else {
            throw ContractError.invalid("Incompatible schema, operation, mutation flag, or exit status.")
        }
        let codes: [ResultStatus: Set<Int32>] = [
            .success: [0], .cancelled: [2], .invalid: [3], .unavailable: [4],
            .unsupported: [4], .partial: [6], .failed: [5, 7]
        ]
        guard codes[result.status]?.contains(reply.exitCode) == true else {
            throw ContractError.invalid("Result status does not match the v1 exit mapping.")
        }
        if let path = result.logPath, !path.hasPrefix("/") || path.contains("\0") {
            throw ContractError.invalid("logPath must be an absolute display path.")
        }
        guard Set(result.items.map(\.id)).count == result.items.count else {
            throw ContractError.invalid("Duplicate item IDs.")
        }
        for item in result.items {
            guard !item.id.isEmpty, !item.id.contains(where: { $0.isNewline || $0 == "\0" }),
                  !item.category.isEmpty else {
                throw ContractError.invalid("Invalid item identity or category.")
            }
            if expected == ToolkitOperation.backupScan.rawValue {
                guard let path = item.displayPath, !path.isEmpty,
                      let count = item.fileCount, count >= 0,
                      let bytes = item.bytes, bytes >= 0 else {
                    throw ContractError.invalid("Backup item is missing paths or non-negative counters.")
                }
            } else {
                guard let state = item.state, !state.isEmpty, item.message != nil else {
                    throw ContractError.invalid("Observation item is missing state or message.")
                }
            }
        }
        return result
    }
}

enum ContractError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public struct OperationReport: Sendable {
    public let timestamp: Date
    public let operation: String
    public let status: ResultStatus
    public let actualExitCode: Int32?
    public let envelope: ResultEnvelope?
    public let stdout: String
    public let stderr: String
    public let message: String
    public var isSuccess: Bool { status == .success && actualExitCode == 0 && envelope?.status == .success }

    public var text: String {
        "\(timestamp)\n\(operation): \(status.rawValue)\nExit: \(actualExitCode.map(String.init) ?? "not started")\n\(message)\n\nSTDOUT\n\(stdout)\n\nSTDERR\n\(stderr)"
    }
}

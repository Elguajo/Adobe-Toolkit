import Foundation
import Darwin

struct ManagedBackend: BackendTransport {
    let resourceRoot: URL?

    func executable() throws -> URL {
        guard let root = resourceRoot?.resolvingSymlinksInPath(), root.isFileURL else {
            throw ContractError.invalid("Unavailable: managed backend resources are missing.")
        }
        // No CWD, PATH, environment override, ancestor search, or legacy-script fallback.
        let candidate = root.appendingPathComponent("Backend/adobe-toolkit-backend-v1").resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(root.path + "/"),
              (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw ContractError.invalid("Unavailable: the managed v1 backend is not bundled. Existing CLI tools remain independently usable.")
        }
        return candidate
    }

    func capabilities() async throws -> BackendReply {
        try await invoke(arguments: ["--ui-json", "capabilities"])
    }

    func execute(_ operation: ToolkitOperation) async throws -> BackendReply {
        guard let arguments = operation.arguments else {
            throw ContractError.invalid("Operation is not connected in this shell.")
        }
        return try await invoke(arguments: arguments)
    }

    private func invoke(arguments: [String]) async throws -> BackendReply {
        let executable = try executable()
        let job = ProcessJob(executable: executable, arguments: arguments)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try job.run()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { job.cancel() })
    }
}

private final class OutputCapture: @unchecked Sendable {
    // Written on one reader queue, read only after DispatchGroup.wait().
    var data = Data()
}

private final class ProcessJob: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.forceStop()
            }
        }
    }

    private func forceStop() {
        lock.lock()
        defer { lock.unlock() }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func run() throws -> BackendReply {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        lock.lock()
        if cancelled {
            lock.unlock()
            throw CancellationError()
        }
        do { try process.run() }
        catch { lock.unlock(); throw error }
        lock.unlock()

        let out = OutputCapture()
        let err = OutputCapture()
        let readers = DispatchGroup()
        // Drain both pipes while the process runs, including output larger than a pipe buffer.
        readers.enter()
        DispatchQueue.global().async {
            out.data = stdout.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global().async {
            err.data = stderr.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        let deadline = DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: deadline)
        process.waitUntilExit()
        deadline.cancel()
        readers.wait()
        return BackendReply(stdout: out.data, stderr: err.data, exitCode: process.terminationStatus,
                            wasSignalled: process.terminationReason == .uncaughtSignal)
    }
}

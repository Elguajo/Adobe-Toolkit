import Foundation

struct BackupEngine {
    enum EngineError: LocalizedError {
        case scriptNotFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .scriptNotFound:
                return "Cannot find macos/AdobeBackuper.command."
            case .failed(let output):
                return output.isEmpty ? "Backup engine failed." : output
            }
        }
    }

    func scan() async throws -> BackupScanSummary {
        let output = try await runEngine(arguments: ["--scan-backup-tsv"])
        let items = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .compactMap(parseScanRow)

        return BackupScanSummary(items: items)
    }

    func backup(items: [BackupScanItem]) async throws -> String {
        let selectionFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("adobe-backuper-selection-\(UUID().uuidString).txt")
        let selection = items.map(\.source).joined(separator: "\n") + "\n"

        try selection.write(to: selectionFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: selectionFile) }

        return try await runEngine(arguments: ["--backup-headless", selectionFile.path])
    }

    func restore(from folder: URL) async throws -> String {
        try await runEngine(arguments: ["--restore-headless", folder.path])
    }

    private func parseScanRow(_ row: Substring) -> BackupScanItem? {
        let columns = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count == 5,
              let files = Int(columns[3]),
              let bytes = Int64(columns[4]) else {
            return nil
        }

        return BackupScanItem(
            category: columns[0],
            source: columns[1],
            destination: columns[2],
            files: files,
            bytes: bytes
        )
    }

    private func runEngine(arguments: [String]) async throws -> String {
        let script = try resolveScriptPath()
        let process = Process()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.standardOutput = output
        process.standardError = error

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    continuation.resume(throwing: EngineError.failed(stdout + stderr))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func resolveScriptPath() throws -> URL {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["ADOBE_BACKUPER_SCRIPT"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            guard fileManager.isExecutableFile(atPath: url.path) else {
                throw EngineError.scriptNotFound
            }
            return url
        }

        if let bundled = Bundle.main.url(forResource: "AdobeBackuper", withExtension: "command"),
           fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        // SwiftPM development builds place the executable below the repository.
        // Resolve from the executable itself so launching from Finder, Xcode, or an
        // arbitrary working directory cannot change the backend that runs.
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .standardizedFileURL
            .deletingLastPathComponent()
        var candidates: [URL] = [
            executableDirectory.appendingPathComponent("AdobeBackuper.command"),
            executableDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("AdobeBackuper.command")
        ]
        var ancestor = executableDirectory
        for _ in 0..<6 {
            candidates.append(ancestor.appendingPathComponent("macos/AdobeBackuper.command"))
            ancestor.deleteLastPathComponent()
        }

        guard let script = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw EngineError.scriptNotFound
        }

        return script
    }
}

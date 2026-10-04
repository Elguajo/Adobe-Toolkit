import Foundation
import Darwin

// Each operation owns a new private directory and an exclusively created file.
// Neither a caller nor a backend supplies its path.
final class SelectionFile {
    let url: URL
    private let directory: URL

    init(ids: [String]) throws {
        guard ids.allSatisfy({ !$0.isEmpty && !$0.contains(where: { $0.isNewline || $0 == "\0" }) }) else {
            throw ContractError.invalid("Invalid selection identity.")
        }
        let data = Data((ids.joined(separator: "\n") + "\n").utf8)
        guard data.count <= 1_048_576 else { throw ContractError.invalid("Selection exceeds 1 MiB.") }
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("adobe-toolkit-selection-" + UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("ids.txt")
        guard mkdir(directory.path, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
        } catch {
            let preparationError = error
            do { try FileManager.default.removeItem(at: directory) }
            catch {
                throw NSError(domain: "AdobeToolkit.SelectionFile", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Selection preparation failed: \(preparationError.localizedDescription). Cleanup failed for \(directory.path): \(error.localizedDescription)"
                ])
            }
            throw preparationError
        }
    }

    func remove() throws { try FileManager.default.removeItem(at: directory) }
}

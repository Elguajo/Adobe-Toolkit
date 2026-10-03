import Foundation
import XCTest
@testable import ToolkitCore

final class ManagedBackendTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func script(root: URL, content: String) throws -> URL {
        let folder = root.appendingPathComponent("Backend")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("adobe-toolkit-backend-v1")
        try ("#!/bin/bash\n" + content).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    func testMissingBundledBackendDoesNotExecuteLegacyScripts() async throws {
        let root = try temporaryRoot()
        let sentinel = root.appendingPathComponent("invoked")
        let legacy = root.appendingPathComponent("AdobeBackuper.command")
        try "#!/bin/bash\ntouch '\(sentinel.path)'\n".write(to: legacy, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: legacy.path)
        let adapter = ToolkitAdapter(transport: ManagedBackend(resourceRoot: root))
        let availability = await adapter.discover()
        XCTAssertTrue(availability.operations.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
        let report = await adapter.run(.cleanupPreview)
        XCTAssertEqual(report.status, .unavailable)
    }

    func testCWDAndEnvironmentCannotSelectBackend() throws {
        let root = try temporaryRoot()
        let other = try temporaryRoot()
        let expected = try script(root: root, content: "exit 0")
        _ = try script(root: other, content: "exit 7")
        let oldDirectory = FileManager.default.currentDirectoryPath
        let oldOverride = ProcessInfo.processInfo.environment["ADOBE_BACKUPER_SCRIPT"]
        defer {
            _ = FileManager.default.changeCurrentDirectoryPath(oldDirectory)
            if let oldOverride { setenv("ADOBE_BACKUPER_SCRIPT", oldOverride, 1) }
            else { unsetenv("ADOBE_BACKUPER_SCRIPT") }
        }
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(other.path))
        setenv("ADOBE_BACKUPER_SCRIPT", other.appendingPathComponent("Backend/adobe-toolkit-backend-v1").path, 1)
        XCTAssertEqual(try ManagedBackend(resourceRoot: root).executable(), expected.resolvingSymlinksInPath())
        XCTAssertThrowsError(try ManagedBackend(resourceRoot: nil).executable())
    }

    func testEscapingSymlinkAndNonExecutableResourceAreRejected() throws {
        let root = try temporaryRoot()
        let other = try temporaryRoot()
        let external = try script(root: other, content: "exit 0")
        let folder = root.appendingPathComponent("Backend")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("adobe-toolkit-backend-v1")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertThrowsError(try ManagedBackend(resourceRoot: root).executable())
        try FileManager.default.removeItem(at: link)
        let file = try script(root: root, content: "exit 0")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        XCTAssertThrowsError(try ManagedBackend(resourceRoot: root).executable())
    }

    func testProcessUsesExactArgumentArrayAndRetainsStderrAndExit() async throws {
        let root = try temporaryRoot()
        _ = try script(root: root, content: """
        [ "$#" = 2 ] && [ "$1" = '--ui-json' ] && [ "$2" = 'diagnose' ] || exit 3
        printf '%s' 'fixture stdout'
        printf '%s' 'fixture stderr' >&2
        exit 7
        """)
        let reply = try await ManagedBackend(resourceRoot: root).execute(.diagnose)
        XCTAssertEqual(String(decoding: reply.stdout, as: UTF8.self), "fixture stdout")
        XCTAssertEqual(String(decoding: reply.stderr, as: UTF8.self), "fixture stderr")
        XCTAssertEqual(reply.exitCode, 7)
    }

    func testLargeStdoutAndStderrDoNotDeadlock() async throws {
        let root = try temporaryRoot()
        _ = try script(root: root, content: """
        /usr/bin/head -c 131072 /dev/zero
        /usr/bin/head -c 131072 /dev/zero >&2
        exit 0
        """)
        let reply = try await ManagedBackend(resourceRoot: root).execute(.cleanupPreview)
        XCTAssertEqual(reply.stdout.count, 131072)
        XCTAssertEqual(reply.stderr.count, 131072)
    }

    func testTransportRejectsAllUnsupportedAndInputBearingOperations() async throws {
        let root = try temporaryRoot()
        let backend = ManagedBackend(resourceRoot: root)
        for operation in ToolkitOperation.allCases where !operation.availableInShell {
            do {
                _ = try await backend.execute(operation)
                XCTFail("Unexpected invocation of \(operation)")
            } catch { XCTAssertTrue(error.localizedDescription.contains("not connected")) }
        }
    }

    func testCancellationTerminatesManagedFixtureProcessAndUnlocksAdapter() async throws {
        let root = try temporaryRoot()
        let started = root.appendingPathComponent("started")
        _ = try script(root: root, content: """
        if [ "$2" = 'capabilities' ]; then
            printf '%s' '{"schemaVersion":1,"operation":"capabilities","status":"success","exitCode":0,"mutates":false,"summary":{"operations":["cleanup.preview"]},"items":[],"warnings":[],"errors":[],"logPath":null}'
        else
            /usr/bin/touch '\(started.path)'
            printf '%s' 'before cancellation'
            exec /bin/sleep 10
        fi
        """)
        let adapter = ToolkitAdapter(transport: ManagedBackend(resourceRoot: root))
        _ = await adapter.discover()
        let running = Task { await adapter.run(.cleanupPreview) }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: started.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: started.path))
        running.cancel()
        let report = await running.value
        XCTAssertEqual(report.status, .cancelled)
        XCTAssertFalse(report.isSuccess)
        XCTAssertNotEqual(report.actualExitCode, 0)
        XCTAssertEqual(report.stdout, "before cancellation")
        let availability = await adapter.discover()
        XCTAssertEqual(availability.operations, [.cleanupPreview])
    }
}

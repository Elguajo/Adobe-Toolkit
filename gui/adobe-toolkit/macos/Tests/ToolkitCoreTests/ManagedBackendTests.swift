import Foundation
import XCTest
@testable import ToolkitCore

final class ManagedBackendTests: XCTestCase {
    private func stagedFixture() throws -> (root: URL, home: URL, diagnostics: URL) {
        let root = try temporaryRoot().resolvingSymlinksInPath()
        let bundled = try XCTUnwrap(ManagedBackend.bundled.resourceRoot)
        try FileManager.default.copyItem(at: bundled.appendingPathComponent("Backend"),
                                        to: root.appendingPathComponent("Backend"))
        let home = root.appendingPathComponent("home")
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let source = home.appendingPathComponent("Library/Application Support/Adobe")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: source.appendingPathComponent("settings.txt"))
        let diagnostics = root.appendingPathComponent("lsregister-fixture")
        try "#!/bin/bash\nexit 0\n".write(to: diagnostics, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: diagnostics.path)
        let pgrep = root.appendingPathComponent("pgrep-fixture")
        try "#!/bin/bash\nexit 1\n".write(to: pgrep, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pgrep.path)
        let backend = root.appendingPathComponent("Backend/macos/ui-json/backend.py")
        var code = try String(contentsOf: backend, encoding: .utf8)
        code = code.replacingOccurrences(of: "Path.home().resolve()", with: "Path('\(home.path)').resolve()")
            .replacingOccurrences(of: "Path('/usr/bin/pgrep')", with: "Path('\(pgrep.path)')")
            .replacingOccurrences(of: "Path('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister')", with: "Path('\(diagnostics.path)')")
        try code.write(to: backend, atomically: true, encoding: .utf8)
        let legacy = root.appendingPathComponent("Backend/macos/AdobeBackuper.command")
        let shell = try String(contentsOf: legacy, encoding: .utf8)
            .replacingOccurrences(of: "/Applications", with: apps.path)
        try shell.write(to: legacy, atomically: true, encoding: .utf8)
        let manifest = root.appendingPathComponent("Backend/shared/cleaner-manifest.json")
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        data["macos"] = ["paths_remove": [source.path], "kill_patterns": ["fixture process"]]
        try JSONSerialization.data(withJSONObject: data).write(to: manifest)
        return (root, home, diagnostics)
    }

    func testStagedBackendCapabilitiesAndItemsMatchSwiftContractFromArbitraryCWD() async throws {
        let fixture = try stagedFixture()
        let backend = ManagedBackend(resourceRoot: fixture.root)
        let oldCWD = FileManager.default.currentDirectoryPath
        defer { _ = FileManager.default.changeCurrentDirectoryPath(oldCWD) }
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath("/tmp"))
        let capabilityReply = try await backend.capabilities()
        let capabilities = try ResultEnvelope.validate(capabilityReply, expected: "capabilities", mutates: false)
        XCTAssertEqual(capabilities.summary["operations"], .array([
            .string("backup.scan"), .string("backup.create"), .string("restore.validate"),
            .string("restore.apply"), .string("cleanup.preview"), .string("diagnose.run")
        ]))
        let adapter = ToolkitAdapter(transport: backend)
        let available = await adapter.discover()
        XCTAssertEqual(available.operations, [.backupScan, .backupCreate, .restoreValidate, .restoreApply, .cleanupPreview, .diagnose])
        let scan = await adapter.run(.backupScan)
        XCTAssertTrue(scan.isSuccess, scan.text)
        XCTAssertEqual(scan.envelope?.items.first?.fileCount, 1)
        XCTAssertEqual(scan.envelope?.items.first?.bytes, 7)
        XCTAssertEqual(scan.envelope?.items.first?.displayPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() },
                       fixture.home.appendingPathComponent("Library/Application Support/Adobe").resolvingSymlinksInPath())
        for operation in [ToolkitOperation.cleanupPreview, .diagnose] {
            let report = await adapter.run(operation)
            XCTAssertTrue(report.isSuccess, report.text)
            XCTAssertNil(report.envelope?.logPath)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("Library/Logs").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("Desktop").path))
    }

    func testManagedCancellationStopsBackendWorkerAndResistantGrandchildBeforeRetry() async throws {
        let fixture = try stagedFixture()
        let marker = fixture.root.appendingPathComponent("writing")
        let writer = fixture.root.appendingPathComponent("writer.py")
        try """
        import signal,time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        while True:
            with open('\(marker.path)', 'a') as stream: stream.write('x')
            time.sleep(.01)
        """.write(to: writer, atomically: true, encoding: .utf8)
        try "#!/bin/bash\n/usr/bin/python3 '\(writer.path)' &\nwait\n"
            .write(to: fixture.diagnostics, atomically: true, encoding: .utf8)
        let adapter = ToolkitAdapter(transport: ManagedBackend(resourceRoot: fixture.root))
        _ = await adapter.discover()
        let running = Task { await adapter.run(.diagnose) }
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: marker.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        running.cancel()
        let report = await running.value
        XCTAssertEqual(report.status, .cancelled, report.text)
        XCTAssertFalse(report.isSuccess)
        XCTAssertEqual(report.actualExitCode, 2, report.text)
        XCTAssertTrue(report.stdout.contains("cancelled"))
        let size = try Data(contentsOf: marker).count
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(try Data(contentsOf: marker).count, size)
        try "#!/bin/bash\nexit 0\n".write(to: fixture.diagnostics, atomically: true, encoding: .utf8)
        let retried = await adapter.run(.diagnose)
        XCTAssertTrue(retried.isSuccess, retried.text)
    }

    func testNativeInputRequestsCreateValidateAndSafeCopyOnlyTemporaryData() async throws {
        let fixture = try stagedFixture()
        let adapter = ToolkitAdapter(transport: ManagedBackend(resourceRoot: fixture.root))
        _ = await adapter.discover()
        let scan = await adapter.run(.backupScan)
        let id = try XCTUnwrap(scan.envelope?.items.first?.id)
        let created = await adapter.run(request: .backupCreate(ids: [id]))
        XCTAssertTrue(created.isSuccess, created.text)
        guard case .string(let path)? = created.envelope?.summary["backupPath"] else {
            return XCTFail("Missing created folder: \(created.text)")
        }
        let source = URL(fileURLWithPath: path)
        let destination = fixture.home.appendingPathComponent("Library/Application Support/Adobe")
        try Data("changed".utf8).write(to: destination.appendingPathComponent("settings.txt"))
        let savedSettings = source.appendingPathComponent("User_Library/Application Support/Adobe/settings.txt")
        let savedAttributes = try FileManager.default.attributesOfItem(atPath: savedSettings.path)
        try FileManager.default.setAttributes([.modificationDate: try XCTUnwrap(savedAttributes[.modificationDate])],
                                              ofItemAtPath: destination.appendingPathComponent("settings.txt").path)
        let sentinel = destination.appendingPathComponent("unrelated.txt")
        try Data("preserve".utf8).write(to: sentinel)
        let blocked = await adapter.run(request: .restoreApply(source: source))
        XCTAssertEqual(blocked.status, .invalid)
        let validated = await adapter.run(request: .restoreValidate(source: source))
        XCTAssertTrue(validated.isSuccess, validated.text)
        let restored = await adapter.run(request: .restoreApply(source: source))
        XCTAssertTrue(restored.isSuccess, restored.text)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("settings.txt")), "fixture")
        XCTAssertEqual(try String(contentsOf: sentinel), "preserve")
        let retry = await adapter.run(request: .restoreApply(source: source))
        XCTAssertEqual(retry.status, .invalid)
        // The backend still owns freshness even after the adapter accepts the scan ID.
        let nextScan = await adapter.run(.backupScan)
        let staleID = try XCTUnwrap(nextScan.envelope?.items.first?.id)
        try Data("changed scope".utf8).write(to: destination.appendingPathComponent("settings.txt"))
        let stale = await adapter.run(request: .backupCreate(ids: [staleID]))
        XCTAssertEqual(stale.status, .invalid, stale.text)
        XCTAssertFalse(stale.isSuccess)
        _ = await adapter.run(request: .restoreValidate(source: source))
        try Data("bad manifest".utf8).write(to: source.appendingPathComponent("manifest.tsv"))
        let changedSource = await adapter.run(request: .restoreApply(source: source))
        XCTAssertEqual(changedSource.status, .invalid, changedSource.text)
        XCTAssertEqual(try String(contentsOf: sentinel), "preserve")
    }

    func testInputPathsArePassedAsSingleLiteralArguments() async throws {
        let root = try temporaryRoot()
        _ = try script(root: root, content: """
        /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"
        """)
        let source = root.appendingPathComponent("space ; ' $literal\nfolder")
        let backend = ManagedBackend(resourceRoot: root)
        for request in [BackendRequest.restoreValidate(source: source), .restoreApply(source: source), .backupCreate(selectionFile: source)] {
            let reply = try await backend.execute(request)
            let arguments = try JSONDecoder().decode([String].self, from: reply.stdout)
            XCTAssertEqual(arguments, request.arguments)
            XCTAssertEqual(arguments.count, 4)
            XCTAssertEqual(arguments.last, source.path)
        }
    }

    func testBackupCancellationRetainsDestinationAndStopsResistantCopyGrandchild() async throws {
        let fixture = try stagedFixture()
        let marker = fixture.root.appendingPathComponent("copy-writing")
        let writer = fixture.root.appendingPathComponent("copy-writer.py")
        try """
        import signal,time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        while True:
            with open('\(marker.path)', 'a') as stream: stream.write('x')
            time.sleep(.01)
        """.write(to: writer, atomically: true, encoding: .utf8)
        let copier = fixture.root.appendingPathComponent("rsync-fixture")
        try "#!/bin/bash\nprintf '%s' 'copy started' >&2\n/usr/bin/python3 '\(writer.path)' &\nwait\n"
            .write(to: copier, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: copier.path)
        let backendFile = fixture.root.appendingPathComponent("Backend/macos/ui-json/backend.py")
        let original = try String(contentsOf: backendFile, encoding: .utf8)
        try original.replacingOccurrences(of: "/usr/bin/rsync", with: copier.path)
            .write(to: backendFile, atomically: true, encoding: .utf8)
        let adapter = ToolkitAdapter(transport: ManagedBackend(resourceRoot: fixture.root))
        _ = await adapter.discover()
        let scan = await adapter.run(.backupScan)
        let id = try XCTUnwrap(scan.envelope?.items.first?.id)
        let running = Task { await adapter.run(request: .backupCreate(ids: [id])) }
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: marker.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        running.cancel()
        let report = await running.value
        XCTAssertEqual(report.status, .cancelled, report.text)
        XCTAssertEqual(report.actualExitCode, 2)
        XCTAssertEqual(report.envelope?.summary["completed"], .number(0))
        XCTAssertNotNil(report.envelope?.summary["currentDestination"])
        XCTAssertTrue(report.stderr.contains("copy started"), report.text)
        let size = try Data(contentsOf: marker).count
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(try Data(contentsOf: marker).count, size)
        try original.write(to: backendFile, atomically: true, encoding: .utf8)
        let fresh = await adapter.run(.backupScan)
        let freshID = try XCTUnwrap(fresh.envelope?.items.first?.id)
        let retry = await adapter.run(request: .backupCreate(ids: [freshID]))
        XCTAssertTrue(retry.isSuccess, retry.text)
    }

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

    func testManagedLaunchDoesNotLoadEnvironmentInjectedShellCode() async throws {
        let root = try temporaryRoot()
        let sentinel = root.appendingPathComponent("environment-invoked")
        let injection = root.appendingPathComponent("inject.sh")
        try "/usr/bin/touch '\(sentinel.path)'\n".write(to: injection, atomically: true, encoding: .utf8)
        let old = ProcessInfo.processInfo.environment["BASH_ENV"]
        defer {
            if let old { setenv("BASH_ENV", old, 1) }
            else { unsetenv("BASH_ENV") }
        }
        setenv("BASH_ENV", injection.path, 1)
        _ = try script(root: root, content: "printf '%s' 'managed fixture'\n")
        let reply = try await ManagedBackend(resourceRoot: root).capabilities()
        XCTAssertEqual(String(decoding: reply.stdout, as: UTF8.self), "managed fixture")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
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
        for operation in ToolkitOperation.allCases where operation.arguments == nil {
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

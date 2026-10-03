# Adobe Toolkit for macOS

Phase 02 task 1: a native SwiftUI shell, hosted in one AppKit window, and a typed v1 adapter. Requires macOS 12+ and Swift 5.9+ for development. No third-party package dependencies.

From the repository root:

```sh
swift build --package-path gui/adobe-toolkit/macos
swift test --package-path gui/adobe-toolkit/macos
swift run --package-path gui/adobe-toolkit/macos AdobeToolkit
```

The normal launch displays **Unavailable** because no managed v1 backend is bundled yet. It never starts the legacy scripts to discover capabilities, reads incidental Terminal output, searches CWD/PATH, or accepts a backend path from an environment variable. Existing CLI workflows remain independently usable.

For safe interface checks:

```sh
swift run --package-path gui/adobe-toolkit/macos AdobeToolkit --fixtures
```

Fixture mode is explicitly labelled throughout the window. Cleanup Preview returns a simulated success and warning; Backup Scan returns cancellation; Diagnose returns failure. The responses are copies of the Phase 00 fixtures in `tests/fixtures/macos_gui_v1/`. No real Adobe locations, processes, registrations, databases, or cleaner logs are accessed. Full Cleanup, Repair, backup creation, and restore remain disabled. The three-second fixture preparation interval allows testing navigation and cancellation.

Manual checks:

1. In normal mode, visit Overview, Backup, Restore, Cleanup, Diagnose, and Repair. Check that missing resources explain Unavailable and no operation can start.
2. In fixture mode, run Cleanup Preview. Check the simulated target, counters, warning, timestamp, and retained raw report. Full Cleanup stays disabled.
3. Run Backup Scan and Diagnose; check Cancelled/Failed reports without a completion notification. Navigate between sections and verify prior observations remain available.
4. During a fixture operation, navigate to another module and check that its operation button is disabled. Cancel and retry. Close the window during a fixture operation; the app exits without applying any action.
5. After building, launch the absolute executable path returned by `swift build --package-path gui/adobe-toolkit/macos --show-bin-path` from `/tmp`. Check that availability does not change with CWD.

The adapter resolves only `Backend/adobe-toolkit-backend-v1` below its managed resource bundle, rejects symlinks escaping that bundle, and invokes the executable with fixed `Process` argument arrays. That resource is deliberately absent in task 1; backend modes and packaging are task 2. The transport is internal; tests inject temporary fake executable resources rather than real toolkit scripts.

Capabilities use the standard result envelope with `operation: "capabilities"`, `mutates: false`, and a `summary.operations` array of v1 operation names. This is the scaffold's additive capability payload convention; confirm and test it when implementing task 2. Only Backup Scan, Cleanup Preview, and Diagnose are connected in this shell. Input-bearing operations remain unavailable even when advertised until selection/source validation is implemented.

Results must match schema v1, requested operation, mutation flag, actual process exit, and v1 status/exit mapping. Unknown capabilities, malformed JSON, invalid item fields, signalled termination, and inconsistent success fail closed. Raw stdout/stderr and actual exit remain in operation reports, including invalid responses. Processes drain both output pipes concurrently; cancellation terminates the managed process, with forced termination after a grace period. Future backend integration must also define cancellation of any child processes before connecting mutation.

Backup scan item decoding currently uses `id`, `category`, `displayPath`, `fileCount`, and `bytes`; this field convention must be aligned with the backend in task 2. Other observations use the Phase 00 fixture fields `id`, `category`, `state`, optional `displayPath`, and `message`. These display fields never become executable commands.

The deployment target is macOS 12; runtime checks on a newer host do not establish execution on Monterey. Signing, notarization, production packaging, privilege elevation, real-data restore, and Windows GUI work are outside this task.

The single-window host uses Apple's [NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview) to keep SwiftUI content compatible with the accepted minimum OS.

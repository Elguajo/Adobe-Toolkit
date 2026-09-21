# ADR-002 — Native macOS-first GUI, followed by Windows parity

Status: Accepted
Date: 2026-09-21

## Context

The product needs a GUI for macOS first and Windows next, while existing platform-specific Terminal workflows must remain unchanged. The product benefits more from native platform behavior and authorization surfaces than from a shared UI implementation.

## Decision

Build two native applications in sequence under `gui/adobe-toolkit/`: a SwiftUI macOS 12+ application in `gui/adobe-toolkit/macos/` first, followed by a WinUI Windows application in `gui/adobe-toolkit/windows/`. The applications do not share UI code. They share versioned backend-contract schemas and fixture tests; each invokes only its own platform's managed backend operations. GUI v1 contains no privileged operation; Full Cleanup/Repair remain CLI-only until the user explicitly authorizes a later phase.

## Consequences

- Positive: macOS receives a native SwiftUI experience first, with a direct path to supported macOS authorization APIs; Windows can later use native WinUI/UAC behavior.
- Positive: current CLI workflows remain independent, and UI/platform-specific privilege code is not forced through a cross-platform abstraction.
- Cost/risk: two UI implementations must maintain visual and contract parity; Phase 01 Windows work starts only after the macOS path has acceptance evidence.
- Revisit when: a web/mobile target becomes a product requirement or shared UI maintenance becomes demonstrably more costly than a cross-platform host.

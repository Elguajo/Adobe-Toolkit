import AppKit
import SwiftUI
import ToolkitCore

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adobe Toolkit").font(.headline)
                    Text("Environment tools").font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                VStack(spacing: 4) {
                    ForEach(Module.allCases) { module in
                        Button { model.module = module } label: {
                            Label(module.rawValue, systemImage: module.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(model.module == module ? Color.accentColor.opacity(0.16) : Color.clear)
                                .cornerRadius(7)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.module == module ? .isSelected : [])
                    }
                }
                Spacer()
                Text(model.fixtureMode ? "Fixture mode\nSimulated data only" : "macOS · GUI v1")
                    .font(.caption).foregroundColor(.secondary).padding(.horizontal, 12)
            }
            .padding(16).frame(width: 200)
            .background(Color(NSColor.windowBackgroundColor))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(model.module.rawValue).font(.largeTitle).bold()
                    Text(model.module.detail).foregroundColor(.secondary)
                    if model.fixtureMode {
                        Label("Fixture mode — all observations and results are simulated.", systemImage: "testtube.2")
                            .font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.08)).cornerRadius(8)
                    }
                    if model.isBusy {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(model.runningOperation.map { "Running \($0.rawValue)…" } ?? "Checking capability…")
                            Spacer()
                            Button("Cancel") { model.cancel() }.keyboardShortcut(.cancelAction)
                        }
                    }
                    if model.module == .overview { overview }
                    else { moduleContent }
                    if let report = model.latestReport {
                        Divider()
                        reportView(report)
                    }
                }
                .padding(32).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach([Module.backup, .cleanup, .diagnose]) { module in
                HStack(alignment: .top) {
                    Image(systemName: module.icon).frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(module.rawValue).font(.headline)
                        if let operation = module.operation, let report = model.reports[operation] {
                            Text(report.isSuccess ? "Backend observations available" : report.status.rawValue.capitalized)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Not scanned").foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("View") { model.module = module }
                }
            }
            if model.available.isEmpty && !model.isBusy { unavailable(model.availabilityReason) }
        }
    }

    @ViewBuilder private var moduleContent: some View {
        if let operation = model.module.operation {
            let supported = model.available.contains(operation)
            Button(actionTitle(operation)) { model.run(operation) }
                .disabled(model.isBusy || !supported)
            if !supported && !model.isBusy { unavailable(model.availabilityReason) }
            if let report = model.reports[operation], report.isSuccess, let envelope = report.envelope {
                observations(envelope)
            } else if model.reports[operation] == nil {
                Text("Not scanned").foregroundColor(.secondary)
            }
            if model.module == .backup {
                Button("Create backup") {}.disabled(true)
                Text("Backup creation is unavailable in this version.")
                    .font(.callout).foregroundColor(.secondary)
            }
            if model.module == .cleanup {
                Button("Full Cleanup") {}.disabled(true)
                Text("Full Cleanup is unavailable in GUI v1.").font(.callout).foregroundColor(.secondary)
            }
        } else if model.module == .restore {
            unavailable("Safe-copy restore is unavailable in this version.")
            Button("Restore with Safe copy") {}.disabled(true)
        } else {
            unavailable("Repair is unavailable in GUI v1. No authorization is requested.")
        }
    }

    private func unavailable(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Unavailable", systemImage: "exclamationmark.circle").font(.headline)
            Text(reason).font(.callout).foregroundColor(.secondary).textSelection(.enabled)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor)).cornerRadius(8)
    }

    private func actionTitle(_ operation: ToolkitOperation) -> String {
        switch operation {
        case .backupScan: return "Scan locations"
        case .cleanupPreview: return "Run fresh preview"
        default: return "Run diagnose"
        }
    }

    private func observations(_ result: ResultEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(result.summary.keys.sorted(), id: \.self) { key in
                HStack { Text(key).foregroundColor(.secondary); Spacer(); Text(result.summary[key]?.display ?? "—") }
            }
            ForEach(result.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.id).font(.headline)
                    Text("\(item.category) · \(item.state ?? "observed")").font(.caption).foregroundColor(.secondary)
                    if let path = item.displayPath { Text(path).font(.callout).textSelection(.enabled) }
                    if let message = item.message { Text(message).font(.callout) }
                }
            }
            ForEach(Array(result.warnings.enumerated()), id: \.offset) { warning in
                Label(warning.element, systemImage: "exclamationmark.triangle").foregroundColor(.orange)
            }
        }
    }

    private func reportView(_ report: OperationReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest result").font(.headline)
                Spacer()
                Text(report.status.rawValue.capitalized)
                    .foregroundColor(report.isSuccess ? .green : .secondary)
                Button("Copy report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.text, forType: .string)
                }
                Button("Show log in Finder") {
                    if let path = report.envelope?.logPath {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                .disabled(report.envelope?.logPath == nil)
            }
            Text(report.timestamp, style: .date).font(.caption).foregroundColor(.secondary)
            Text(report.timestamp, style: .time).font(.caption).foregroundColor(.secondary)
            Text(report.operation).font(.system(.caption, design: .monospaced))
            Text(report.message).font(.callout)
            if let result = report.envelope {
                ForEach(Array(result.errors.enumerated()), id: \.offset) { error in
                    Text(error.element).foregroundColor(.red)
                }
            }
            DisclosureGroup("Raw output and exit status") {
                Text(report.text).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
        }
    }
}

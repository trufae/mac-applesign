import SwiftUI
import UniformTypeIdentifiers

/// Live output of applesign and ideviceinstaller.
struct ConsoleView: View {
    @Environment(Workbench.self) private var bench

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(bench.log) { line in
                            LogLineView(line: line).id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay {
                    if bench.log.isEmpty {
                        Text("applesign output will appear here")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                .onChange(of: bench.log.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.92))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Output", systemImage: "terminal")
                .font(.headline)
            status
            Spacer()
            Group {
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bench.logText, forType: .string)
                }
                Button("Save…", systemImage: "square.and.arrow.down") { save() }
                Button("Clear", systemImage: "trash") { bench.clearLog() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(bench.log.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder private var status: some View {
        if bench.isSigning {
            Text("Running").pill(.blue)
        } else if let code = bench.lastExitStatus {
            Text(code == 0 ? "Exit 0" : "Exit \(code)").pill(code == 0 ? .green : .red)
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "applesign.log"
        panel.allowedContentTypes = [.log, .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? bench.logText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct LogLineView: View {
    let line: LogLine

    var body: some View {
        Text(line.text)
            .font(.system(.callout, design: .monospaced).weight(weight))
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, line.kind == .command ? 6 : 0)
    }

    private var color: Color {
        switch line.kind {
        case .stdout: .primary
        case .stderr: .orange
        case .command: .accentColor
        case .info: .secondary
        case .success: .green
        case .failure: .red
        }
    }

    private var weight: Font.Weight {
        switch line.kind {
        case .command, .success, .failure: .semibold
        default: .regular
        }
    }
}

private extension View {
    func pill(_ color: Color) -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
    }
}

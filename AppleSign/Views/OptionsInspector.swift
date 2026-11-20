import SwiftUI

/// Every applesign command line option, grouped like `applesign --help`.
struct OptionsInspector: View {
    @Environment(Workbench.self) private var bench
    @State private var query = ""

    var body: some View {
        @Bindable var bench = bench
        Form {
            Section {
                PathField(placeholder: "Next to the input app", text: $bench.options.outputDirectory,
                          directory: true, extensions: [])
            } header: {
                Label("Output folder", systemImage: "folder")
            } footer: {
                Text(verbatim: "Passed as -o <folder>/<name>-resigned.ipa").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(OptionSpec.groups(matching: query), id: \.0) { group, specs in
                Section {
                    ForEach(specs) { OptionRow(spec: $0, options: $bench.options) }
                } header: {
                    Label(group.rawValue, systemImage: group.symbol)
                }
            }

            Section {
                Text(bench.commandLine)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Copy Command", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bench.commandLine, forType: .string)
                    }
                    Spacer()
                    Button("Reset Options", role: .destructive) { bench.options = .defaults }
                        .disabled(bench.options == .defaults)
                }
            } header: {
                Label("Command line", systemImage: "terminal")
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            TextField("Filter options", text: $query, prompt: Text("Filter options"))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }
}

private struct OptionRow: View {
    let spec: OptionSpec
    @Binding var options: SigningOptions

    var body: some View {
        Group {
            switch spec.kind {
            case .flag:
                Toggle(isOn: $options[flag: spec.id]) { label }
            case .text(let placeholder):
                LabeledContent {
                    TextField(spec.title, text: $options[value: spec.id], prompt: Text(placeholder))
                        .labelsHidden()
                        .frame(maxWidth: 170)
                } label: { label }
            case .file(let extensions):
                VStack(alignment: .leading, spacing: 6) {
                    label
                    PathField(placeholder: "None", text: $options[value: spec.id], directory: false, extensions: extensions)
                }
            case .directory:
                VStack(alignment: .leading, spacing: 6) {
                    label
                    PathField(placeholder: "Default", text: $options[value: spec.id], directory: true, extensions: [])
                }
            case .choice(let values):
                Picker(selection: $options[value: spec.id]) {
                    ForEach(values, id: \.self) { Text($0.isEmpty ? "Keep all" : $0).tag($0) }
                } label: { label }
            }
        }
        .help(spec.help)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(spec.title)
                if spec.experimental {
                    Text("EXPERIMENTAL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.15), in: .capsule)
                }
            }
            Text(spec.usage)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

/// A path text field with a Choose… button.
struct PathField: View {
    var placeholder: String
    @Binding var text: String
    var directory: Bool
    var extensions: [String]

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text, prompt: Text(placeholder))
                .labelsHidden()
                .truncationMode(.head)
            Button("Choose…") {
                if let url = Panels.open(types: extensions, message: "Choose a \(directory ? "folder" : "file")",
                                         directories: directory) {
                    text = url.path
                }
            }
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @Environment(Workbench.self) private var bench
    @AppStorage(SettingsKey.autoSign) private var autoSign = false
    @AppStorage(SettingsKey.revealAfterSign) private var reveal = false
    @AppStorage(SettingsKey.applesignPath) private var applesignPath = ""
    @State private var version = ""
    @State private var p12Password = ""

    var body: some View {
        Form {
            Section("Workflow") {
                Toggle("Sign as soon as an app is dropped", isOn: $autoSign)
                Toggle("Reveal signed apps in Finder", isOn: $reveal)
            }

            Section {
                LabeledContent("In use") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Tools.applesign?.path ?? "Not found")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .truncationMode(.head)
                            .lineLimit(1)
                        if !version.isEmpty {
                            Text("v\(version)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                PathField(placeholder: "Bundled binary", text: $applesignPath, directory: false, extensions: [])
            } header: {
                Text("applesign")
            } footer: {
                Text("Leave empty to use the node-applesign binary bundled with the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if bench.identityIsP12 {
                Section {
                    SecureField("Password", text: $p12Password)
                        .onSubmit { Keychain.setPassword(p12Password, for: bench.identity) }
                    Button("Save to Keychain") { Keychain.setPassword(p12Password, for: bench.identity) }
                } header: {
                    Text(".p12 identity")
                } footer: {
                    Text("Passed to applesign as APPLESIGN_P12_PASSWORD when signing with \((bench.identity as NSString).lastPathComponent).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Devices") {
                LabeledContent("ideviceinstaller") {
                    Text(Tools.find("ideviceinstaller")?.path ?? "brew install ideviceinstaller")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("About") {
                LabeledContent("mac-applesign") {
                    Link(Tools.appVersion, destination: URL(string: "https://github.com/trufae/mac-applesign")!)
                }
                LabeledContent("node-applesign") {
                    Link(version.isEmpty ? "Unknown" : version, destination: URL(string: "https://github.com/nowsecure/node-applesign")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: applesignPath) {
            version = ""
            version = await Tools.applesignVersion() ?? ""
        }
        .onAppear {
            if bench.identityIsP12 { p12Password = Keychain.password(for: bench.identity) ?? "" }
        }
    }
}

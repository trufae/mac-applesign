import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct AppleSignApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("AppleSign", id: "main") {
            ContentView()
                .environment(delegate.bench)
                .environment(delegate.devices)
        }
        .defaultSize(width: 1040, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About AppleSign") {
                    Task {
                        let v = await Tools.applesignVersion() ?? "not found"
                        NSApp.orderFrontStandardAboutPanel(options: [
                            .credits: NSAttributedString(string: "node-applesign \(v)", attributes: [
                                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                .foregroundColor: NSColor.secondaryLabelColor,
                            ]),
                        ])
                    }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open App…") { Panels.chooseApp().map(delegate.bench.setInput) }
                    .keyboardShortcut("o")
                Button("Open Provisioning Profile…") { Panels.chooseProfile().map(delegate.bench.setProfile) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Sign") {
                Button("Sign") { delegate.bench.sign() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!delegate.bench.canSign)
                Button("Stop") { delegate.bench.cancel() }
                    .keyboardShortcut(".")
                    .disabled(!delegate.bench.isSigning)
                Divider()
                Button("Reveal Signed App in Finder") {
                    delegate.bench.output.map { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(delegate.bench.output == nil)
                Button("Refresh Identities and Profiles") {
                    Task { await delegate.bench.reloadKeychainItems() }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(delegate.bench)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let bench = Workbench()
    let devices = DeviceMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [SettingsKey.revealAfterSign: false, SettingsKey.autoSign: false])
        devices.start()
        #if DEBUG
        debugAutomation()
        #endif
    }

    #if DEBUG
    /// APPLESIGN_INPUT=x.ipa preloads an app, APPLESIGN_SIGN=1 signs it and
    /// APPLESIGN_SNAPSHOT=out.png writes the window to a PNG and quits.
    private func debugAutomation() {
        let env = ProcessInfo.processInfo.environment
        if let input = env["APPLESIGN_INPUT"] { bench.setInput(URL(filePath: input)) }
        if env["APPLESIGN_SIGN"] == "1" {
            Task {
                try? await Task.sleep(for: .seconds(2))
                bench.sign()
            }
        }
        guard let out = env["APPLESIGN_SNAPSHOT"] else { return }
        let delay = Double(env["APPLESIGN_SNAPSHOT_DELAY"] ?? "") ?? 4
        Task {
            try? await Task.sleep(for: .seconds(delay))
            if let view = NSApp.windows.first(where: \.isVisible)?.contentView?.superview,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: out))
            }
            print(bench.logText)
            NSApp.terminate(nil)
        }
    }
    #endif

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.pathExtension == "mobileprovision" { bench.setProfile(url) } else { bench.setInput(url) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Open panels shared by the menu bar and the crafting slots.
enum Panels {
    static func chooseApp() -> URL? {
        open(types: ["ipa", "app"], message: "Choose an iOS app to re-sign")
    }

    static func chooseProfile() -> URL? {
        open(types: ["mobileprovision"], message: "Choose a provisioning profile")
    }

    static func open(types: [String], message: String, directories: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.canChooseDirectories = directories
        panel.canChooseFiles = !directories
        panel.canCreateDirectories = directories
        panel.treatsFilePackagesAsDirectories = false
        if !types.isEmpty {
            panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

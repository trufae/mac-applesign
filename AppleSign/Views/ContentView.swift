import SwiftUI

struct ContentView: View {
    @Environment(Workbench.self) private var bench
    @AppStorage("showInspector") private var showInspector = false
    @AppStorage("showConsole") private var showConsole = true
    @AppStorage("consoleHeight") private var consoleHeight = 200.0
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            CraftingTableView()
                .frame(minHeight: 340, maxHeight: .infinity)
                .background { CraftingBackdrop() }
            if showConsole {
                ConsoleView()
                    .frame(height: consoleHeight)
                    .overlay(alignment: .top) { resizeHandle }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .navigationTitle("AppleSign")
        .navigationSubtitle(subtitle)
        .dropDestination(for: URL.self) { urls, _ in route(urls) }
        .inspector(isPresented: $showInspector) {
            OptionsInspector()
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bench.isSigning ? bench.cancel() : bench.sign()
                } label: {
                    Label(bench.isSigning ? "Stop" : "Sign",
                          systemImage: bench.isSigning ? "stop.fill" : "signature")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .disabled(!bench.canSign && !bench.isSigning)
                .help(bench.missingIngredient ?? "Sign the app")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showConsole.animation(.smooth)) {
                    Label("Output", systemImage: "terminal")
                }
                .help("Show the applesign output")
                Toggle(isOn: $showInspector) {
                    Label("Options", systemImage: "slider.horizontal.3")
                }
                .help("Show all signing options")
            }
        }
    }

    /// Drag the top edge of the console to resize it.
    private var resizeHandle: some View {
        Color.clear
            .frame(height: 8)
            .contentShape(.rect)
            .pointerStyle(.frameResize(position: .top))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStart ?? consoleHeight
                    dragStart = start
                    consoleHeight = min(max(start - value.translation.height, 100), 600)
                }
                .onEnded { _ in dragStart = nil })
            .offset(y: -4)
    }

    private var subtitle: String {
        switch bench.phase {
        case .signing: "Signing \(bench.input?.lastPathComponent ?? "")…"
        case .signed: "Signed \(bench.output?.lastPathComponent ?? "")"
        case .failed: "Signing failed"
        case .idle: bench.missingIngredient ?? "Ready to sign \(bench.input?.lastPathComponent ?? "")"
        }
    }

    /// Drops anywhere on the window are routed by file type.
    @discardableResult
    private func route(_ urls: [URL]) -> Bool {
        var handled = false
        for url in urls {
            switch url.pathExtension.lowercased() {
            case "mobileprovision": bench.setProfile(url)
            case "p12": bench.identity = url.path
            default:
                guard !handled else { continue }
                bench.setInput(url)
            }
            handled = true
        }
        return handled
    }
}

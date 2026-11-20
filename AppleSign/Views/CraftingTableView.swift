import SwiftUI
import UniformTypeIdentifiers

/// App + profile + identity → signed app → device.
struct CraftingTableView: View {
    @Environment(Workbench.self) private var bench

    static let big: CGFloat = 168
    static let small: CGFloat = 76
    static let gap: CGFloat = 26
    private static let naturalWidth: CGFloat = big + 16 + small + gap * 2 + 76 + big + gap * 2 + 36 + 148

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, (geo.size.width - 48) / Self.naturalWidth, (geo.size.height - 24) / 420)
            VStack(spacing: 30) {
                header
                table
                RecipeStrip()
            }
            .scaleEffect(max(scale, 0.55))
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Re-sign an iOS app")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Drop an app, pick a profile, then craft it. Drag the result to Finder or onto a device.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var table: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(alignment: .top, spacing: Self.gap) {
                HStack(alignment: .top, spacing: 16) {
                    InputSlot()
                    VStack(spacing: 16) {
                        ProfileSlot()
                        IdentitySlot()
                    }
                }
                CraftButton()
                    .padding(.top, Self.big / 2 - 38)
                OutputSlot()
                Connector()
                    .padding(.top, Self.big / 2 - 8)
                DeviceSlot()
                    .padding(.top, 10)
            }
        }
    }
}

// MARK: - Ingredients

private struct InputSlot: View {
    @Environment(Workbench.self) private var bench
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            Button { Panels.chooseApp().map(bench.setInput) } label: {
                Slot(size: CraftingTableView.big, isTargeted: targeted) {
                    if bench.input != nil {
                        AppIconView(preview: bench.inputPreview, size: 96)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        EmptySlotLabel(symbol: "arrow.down.app", text: "Drop .ipa here")
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(bench.isSigning)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                bench.setInput(url)
                return true
            } isTargeted: { targeted = $0 }
            .contextMenu {
                if let input = bench.input {
                    Button("Reveal in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([input])
                    }
                    Button("Remove", systemImage: "xmark", role: .destructive) { bench.clearInput() }
                }
            }
            .help(bench.input?.path ?? "Click to choose an .ipa, or drop one here")

            SlotCaption(step: 1, title: bench.inputPreview?.name ?? "App",
                        detail: detail, width: CraftingTableView.big + 20)
        }
        .animation(.smooth, value: bench.input)
    }

    private var detail: String? {
        guard let input = bench.input else { return ".ipa or .app" }
        guard let p = bench.inputPreview else { return input.lastPathComponent }
        return [p.version, p.fileSize > 0 ? p.fileSize.formatted(.byteCount(style: .file)) : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct ProfileSlot: View {
    @Environment(Workbench.self) private var bench
    @State private var targeted = false

    var body: some View {
        Menu {
            if !bench.recentProfiles.isEmpty {
                Section("Recent") {
                    ForEach(bench.recentProfiles) { profileButton($0) }
                }
            }
            let others = bench.installedProfiles.filter { p in !bench.recentProfiles.contains { $0.url == p.url } }
            if !others.isEmpty {
                Menu("Installed Profiles") {
                    ForEach(others) { profileButton($0) }
                }
            }
            Divider()
            Button("Choose File…", systemImage: "folder") { Panels.chooseProfile().map(bench.setProfile) }
            if let profile = bench.profile {
                Button("Reveal in Finder", systemImage: "magnifyingglass") {
                    NSWorkspace.shared.activateFileViewerSelecting([profile.url])
                }
                Button("Clear", systemImage: "xmark") { bench.clearProfile() }
            }
        } label: {
            Slot(size: CraftingTableView.small, isTargeted: targeted,
                 tint: bench.profile?.isExpired == true ? .red : nil) {
                if let profile = bench.profile {
                    Image(systemName: profile.isExpired ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(profile.isExpired ? Color.red : Color.green)
                        .symbolRenderingMode(.hierarchical)
                } else {
                    EmptySlotLabel(symbol: "doc.badge.gearshape", size: 24)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension == "mobileprovision" }) else { return false }
            bench.setProfile(url)
            return true
        } isTargeted: { targeted = $0 }
        .help(bench.profile.map { "\($0.name)\n\($0.url.path)" } ?? "Provisioning profile: click to choose, or drop a .mobileprovision")
        .overlay(alignment: .topLeading) { stepBadge(2) }
    }

    private func profileButton(_ p: ProvisioningProfile) -> some View {
        Button {
            bench.setProfile(p.url)
        } label: {
            Text(p.name)
            Text("\(p.kind) · \(p.teamName) · \(p.appID)")
        }
    }
}

private struct IdentitySlot: View {
    @Environment(Workbench.self) private var bench
    @State private var targeted = false

    var body: some View {
        Menu {
            Button {
                bench.identity = ""
            } label: {
                Text("Automatic")
                Text("Derived from the provisioning profile")
            }
            if !bench.identities.isEmpty {
                Section("Keychain") {
                    ForEach(bench.identities) { id in
                        Button {
                            bench.identity = id.hash
                        } label: {
                            let inProfile = bench.profile?.certificateHashes.contains(id.hash.uppercased()) == true
                            Label(id.name, systemImage: inProfile ? "checkmark.seal" : "person.badge.key")
                            Text(inProfile ? "Matches profile · \(id.hash.prefix(10))…" : "\(id.hash.prefix(10))…")
                        }
                    }
                }
            }
            Divider()
            Button("Use .p12 File…", systemImage: "key") {
                Panels.open(types: ["p12"], message: "Choose a .p12 signing identity").map { bench.identity = $0.path }
            }
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await bench.reloadKeychainItems() }
            }
        } label: {
            Slot(size: CraftingTableView.small, isTargeted: targeted,
                 tint: bench.identityMismatch ? .orange : nil) {
                if bench.identity.isEmpty {
                    EmptySlotLabel(symbol: "person.badge.key", size: 24)
                } else {
                    Image(systemName: bench.identityMismatch ? "exclamationmark.triangle.fill"
                        : bench.identityIsP12 ? "key.fill" : "person.badge.key.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(bench.identityMismatch ? Color.orange : Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "p12" }) else { return false }
            bench.identity = url.path
            return true
        } isTargeted: { targeted = $0 }
        .help(bench.identityMismatch
            ? "This identity's certificate is not in the provisioning profile"
            : "Signing identity: \(bench.identityTitle)")
        .overlay(alignment: .topLeading) { stepBadge(3) }
    }
}

private func stepBadge(_ n: Int) -> some View {
    Text("\(n)")
        .font(.caption2.weight(.bold).monospacedDigit())
        .foregroundStyle(.white)
        .frame(width: 16, height: 16)
        .background(.tint, in: .circle)
        .offset(x: -4, y: -4)
        .allowsHitTesting(false)
}

// MARK: - Craft

private struct CraftButton: View {
    @Environment(Workbench.self) private var bench
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                bench.isSigning ? bench.cancel() : bench.sign()
            } label: {
                ZStack {
                    if bench.isSigning {
                        if hovering {
                            Image(systemName: "stop.fill").font(.system(size: 22, weight: .semibold))
                        } else {
                            ProgressView().controlSize(.regular)
                        }
                    } else {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .symbolEffect(.bounce, value: bench.phase == .signed)
                    }
                }
                .frame(width: 60, height: 60)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(!bench.canSign && !bench.isSigning)
            .onHover { hovering = $0 }
            .keyboardShortcut(.return, modifiers: .command)
            .help(bench.isSigning ? "Stop signing" : bench.missingIngredient ?? "Sign (⌘↩)")

            Group {
                if bench.isSigning, let start = bench.startedAt {
                    Text(start, style: .timer).monospacedDigit()
                } else {
                    Text(bench.isSigning ? "" : bench.missingIngredient == nil ? "Craft" : "")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 76)
        }
    }
}

// MARK: - Result

private struct OutputSlot: View {
    @Environment(Workbench.self) private var bench

    var body: some View {
        VStack(spacing: 10) {
            Slot(size: CraftingTableView.big, tint: tint) {
                content
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            .onDrag {
                guard let url = bench.output else { return NSItemProvider() }
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            } preview: {
                AppIconView(preview: bench.outputPreview ?? bench.inputPreview, size: 64)
            }
            .onTapGesture(count: 2) {
                bench.output.map { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
            }
            .contextMenu {
                if let output = bench.output {
                    Button("Reveal in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                    Button("Copy Path", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output.path, forType: .string)
                    }
                }
            }
            .help(bench.output.map { "\($0.path)\nDrag to Finder or onto a device. Double-click to reveal." }
                ?? "The signed app appears here")

            SlotCaption(step: 4, title: title, detail: detail, width: CraftingTableView.big + 20)
        }
        .animation(.bouncy, value: bench.phase)
    }

    @ViewBuilder private var content: some View {
        switch bench.phase {
        case .idle:
            EmptySlotLabel(symbol: "seal", text: "Signed app\nappears here")
        case .signing:
            AppIconView(preview: bench.inputPreview, size: 96)
                .opacity(0.35)
                .saturation(0)
                .overlay { ProgressView().controlSize(.large) }
        case .signed:
            AppIconView(preview: bench.outputPreview ?? bench.inputPreview, size: 96)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white, .green)
                        .offset(x: 10, y: 10)
                }
        case .failed:
            EmptySlotLabel(symbol: "xmark.octagon", text: "Signing failed")
                .foregroundStyle(.red)
        }
    }

    private var tint: Color? {
        switch bench.phase {
        case .signed: .green
        case .failed: .red
        default: nil
        }
    }

    private var title: String {
        switch bench.phase {
        case .signed: "Signed"
        case .failed: "Failed"
        case .signing: "Signing…"
        case .idle: "Result"
        }
    }

    private var detail: String? {
        switch bench.phase {
        case .signed: bench.output?.lastPathComponent
        case .failed(let reason): reason
        default: "-resigned.ipa"
        }
    }
}

private struct Connector: View {
    var body: some View {
        HStack(spacing: 0) {
            Line()
                .stroke(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
                .frame(width: 26, height: 2)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .frame(width: 36, height: 16)
        .accessibilityHidden(true)
    }

    nonisolated private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

// MARK: - Device

private struct DeviceSlot: View {
    @Environment(Workbench.self) private var bench
    @Environment(DeviceMonitor.self) private var monitor
    @State private var targeted = false
    @State private var selected: String?

    private let size: CGFloat = 148

    private var device: IOSDevice? {
        monitor.devices.first { $0.udid == selected } ?? monitor.devices.first
    }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                if let device, let output = bench.output { bench.install(output, on: device) }
            } label: {
                Slot(size: size, isTargeted: targeted, tint: tint) { content }
            }
            .buttonStyle(.plain)
            .disabled(device == nil || bench.output == nil)
            .dropDestination(for: URL.self) { urls, _ in
                guard let device, let ipa = urls.first(where: { $0.pathExtension.lowercased() == "ipa" }) else { return false }
                bench.install(ipa, on: device)
                return true
            } isTargeted: { targeted = $0 && device != nil }
            .help(help)

            if monitor.devices.count > 1 {
                Picker("Device", selection: $selected) {
                    ForEach(monitor.devices) { Text($0.name).tag(Optional($0.udid)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: size)
            } else {
                SlotCaption(step: 5, title: device?.name ?? "Device", detail: detail, width: size + 20)
            }
        }
        .animation(.smooth, value: monitor.devices)
    }

    @ViewBuilder private var content: some View {
        if let device {
            ZStack {
                Image(systemName: device.symbol)
                    .font(.system(size: 54, weight: .thin))
                    .foregroundStyle(.primary.opacity(0.8))
                switch bench.installState {
                case .installing(device.udid):
                    ProgressView().controlSize(.small)
                case .installed(device.udid):
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.white, .green)
                case .failed(device.udid):
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white, .red)
                default:
                    if bench.output != nil {
                        Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.white, .tint)
                    }
                }
            }
        } else {
            EmptySlotLabel(symbol: monitor.toolsInstalled ? "iphone.slash" : "cable.connector.slash",
                           text: monitor.toolsInstalled ? "Connect a\ndevice" : "libimobiledevice\nnot installed",
                           size: 30)
        }
    }

    private var tint: Color? {
        guard let device else { return nil }
        switch bench.installState {
        case .installed(device.udid): return .green
        case .failed(device.udid): return .red
        default: return nil
        }
    }

    private var detail: String {
        if let device { return [device.osVersion.isEmpty ? nil : "iOS \(device.osVersion)", "click or drop to install"]
            .compactMap { $0 }.joined(separator: " · ") }
        return monitor.toolsInstalled ? "optional" : "brew install ideviceinstaller"
    }

    private var help: String {
        guard monitor.toolsInstalled else {
            return "Install libimobiledevice to deploy straight to a device:\nbrew install ideviceinstaller"
        }
        guard let device else { return "Connect an iPhone or iPad over USB" }
        return "\(device.name) (\(device.productType), \(device.udid))\nClick to install the signed app, or drop any .ipa here"
    }
}

// MARK: - Recipe

/// One-line summary of what will be crafted, under the table.
private struct RecipeStrip: View {
    @Environment(Workbench.self) private var bench

    var body: some View {
        HStack(spacing: 14) {
            if let p = bench.profile {
                Label {
                    Text(p.name).fontWeight(.medium)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260, alignment: .leading)
                        .fixedSize(horizontal: p.name.count < 32, vertical: false)
                    Text("\(p.kind) · \(p.teamID.isEmpty ? p.teamName : p.teamID)")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "doc.badge.gearshape")
                }
                if let exp = p.expiration {
                    Text(p.isExpired ? "expired" : "expires \(exp, format: .relative(presentation: .named))")
                        .foregroundStyle(p.isExpired ? .red : .secondary)
                }
            } else {
                Label("No provisioning profile", systemImage: "doc.badge.gearshape")
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 14)
            Label(bench.identityTitle, systemImage: "person.badge.key")
                .foregroundStyle(bench.identityMismatch ? .orange : .primary)
            if bench.options.changedCount > 0 {
                Divider().frame(height: 14)
                Label("^[\(bench.options.changedCount) option](inflect: true)", systemImage: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 820)
    }
}

import AppKit
import Foundation
import Observation

nonisolated struct LogLine: Identifiable, Sendable {
    enum Kind: Sendable { case stdout, stderr, command, info, success, failure }
    let id: Int
    let date: Date
    let kind: Kind
    let text: String
}

/// The crafting table: input app + profile + identity → signed app → device.
@Observable
final class Workbench {
    enum Phase: Equatable {
        case idle, signing, signed, failed(String)
    }

    enum InstallState: Equatable {
        case idle, installing(String), installed(String), failed(String)
    }

    // MARK: Ingredients

    private(set) var input: URL?
    private(set) var inputPreview: AppPreview?
    private(set) var output: URL?
    private(set) var outputPreview: AppPreview?
    private(set) var phase: Phase = .idle
    private(set) var installState: InstallState = .idle
    private(set) var startedAt: Date?

    var options: SigningOptions {
        didSet { save(options, SettingsKey.options) }
    }

    /// Identity hash, a .p12 path, or empty to let applesign pick it from the profile.
    var identity: String {
        didSet { UserDefaults.standard.set(identity, forKey: SettingsKey.identity) }
    }

    private(set) var profile: ProvisioningProfile?
    private(set) var profileError: String?
    private(set) var recentProfiles: [ProvisioningProfile] = []
    private(set) var installedProfiles: [ProvisioningProfile] = []
    private(set) var identities: [SigningIdentity] = []

    // MARK: Console

    private(set) var log: [LogLine] = []
    private(set) var lastExitStatus: Int32?
    private var nextLogID = 0
    private var signTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        options = defaults.data(forKey: SettingsKey.options)
            .flatMap { try? JSONDecoder().decode(SigningOptions.self, from: $0) } ?? .defaults
        identity = defaults.string(forKey: SettingsKey.identity) ?? ""
        let recents = defaults.stringArray(forKey: SettingsKey.recentProfiles) ?? []
        recentProfiles = recents.compactMap { try? ProvisioningProfile.load(URL(filePath: $0)) }
        if let last = defaults.string(forKey: SettingsKey.profile) {
            profile = try? ProvisioningProfile.load(URL(filePath: last))
        }
        Task { await reloadKeychainItems() }
    }

    // MARK: Derived state

    var identityIsP12: Bool { identity.lowercased().hasSuffix(".p12") }

    var selectedIdentity: SigningIdentity? { identities.first { $0.hash == identity } }

    var identityTitle: String {
        if identity.isEmpty { return "Automatic" }
        if identityIsP12 { return (identity as NSString).lastPathComponent }
        return selectedIdentity?.name ?? String(identity.prefix(10)) + "…"
    }

    /// The profile does not embed the certificate of the chosen identity.
    var identityMismatch: Bool {
        guard let profile, !identity.isEmpty, !identityIsP12, !profile.certificateHashes.isEmpty else { return false }
        return !profile.certificateHashes.contains(identity.uppercased())
    }

    var isSigning: Bool { phase == .signing }

    var missingIngredient: String? {
        if Tools.applesign == nil { return "applesign binary not found" }
        if input == nil { return "Drop an .ipa to sign" }
        if profile == nil && !options[flag: "device-provision"] && !options[flag: "pseudo-sign"]
            && identity.isEmpty {
            return "Choose a provisioning profile"
        }
        return nil
    }

    var canSign: Bool { missingIngredient == nil && !isSigning }

    func outputURL(for input: URL) -> URL {
        if options[flag: "replace"] { return input }
        let dir = options.outputDirectory.isEmpty
            ? input.deletingLastPathComponent()
            : URL(filePath: options.outputDirectory, directoryHint: .isDirectory)
        return dir.appending(path: input.deletingPathExtension().lastPathComponent + "-resigned.ipa")
    }

    /// Full argument vector passed to applesign, minus the binary itself.
    func arguments(for input: URL?) -> [String] {
        var args: [String] = []
        if let profile { args += ["-m", profile.url.path] }
        if !identity.isEmpty { args += ["-i", identity] }
        args += options.arguments
        if let input {
            if !options[flag: "replace"] { args += ["-o", outputURL(for: input).path] }
            args.append(input.path)
        }
        return args
    }

    var commandLine: String {
        (["applesign"] + arguments(for: input ?? URL(filePath: "target.ipa"))).map(Self.shellQuote).joined(separator: " ")
    }

    // MARK: Ingredients

    func setInput(_ url: URL) {
        guard !isSigning else { return }
        input = url
        inputPreview = nil
        output = nil
        outputPreview = nil
        phase = .idle
        installState = .idle
        Task {
            let preview = await AppPreview.inspect(url)
            if input == url { inputPreview = preview }
        }
        if UserDefaults.standard.bool(forKey: SettingsKey.autoSign), canSign {
            sign()
        }
    }

    func clearInput() {
        guard !isSigning else { return }
        input = nil
        inputPreview = nil
        output = nil
        outputPreview = nil
        phase = .idle
    }

    func setProfile(_ url: URL) {
        do {
            let loaded = try ProvisioningProfile.load(url)
            profile = loaded
            profileError = nil
            UserDefaults.standard.set(url.path, forKey: SettingsKey.profile)
            recentProfiles.removeAll { $0.url == url }
            recentProfiles.insert(loaded, at: 0)
            recentProfiles = Array(recentProfiles.prefix(8))
            UserDefaults.standard.set(recentProfiles.map(\.url.path), forKey: SettingsKey.recentProfiles)
            if identityMismatch || identity.isEmpty { matchIdentityToProfile() }
            if loaded.isExpired { append(.failure, "Provisioning profile \(loaded.name) expired") }
        } catch {
            profileError = error.localizedDescription
            append(.failure, error.localizedDescription)
        }
    }

    func clearProfile() {
        profile = nil
        UserDefaults.standard.removeObject(forKey: SettingsKey.profile)
    }

    /// Picks the keychain identity whose certificate is embedded in the profile.
    func matchIdentityToProfile() {
        guard let profile else { return }
        if let match = identities.first(where: { profile.certificateHashes.contains($0.hash.uppercased()) }) {
            identity = match.hash
        }
    }

    func reloadKeychainItems() async {
        async let profiles = ProvisioningProfile.discover()
        if let tool = Tools.applesign,
           let result = try? await ProcessRunner.run(tool, arguments: ["-L"]), result.status == 0 {
            identities = SigningIdentity.parse(result.output)
        }
        installedProfiles = await profiles
        if identityMismatch { matchIdentityToProfile() }
    }

    // MARK: Signing

    func sign() {
        guard canSign, let input, let tool = Tools.applesign else { return }
        signTask = Task { await run(tool, input: input) }
    }

    func cancel() {
        signTask?.cancel()
    }

    private func run(_ tool: URL, input: URL) async {
        let args = arguments(for: input)
        var target = outputURL(for: input)
        var env = Tools.environment
        if identityIsP12, let password = Keychain.password(for: identity) {
            env["APPLESIGN_P12_PASSWORD"] = password
        }
        phase = .signing
        output = nil
        outputPreview = nil
        installState = .idle
        lastExitStatus = nil
        startedAt = .now
        append(.command, "$ " + ([tool.lastPathComponent] + args).map(Self.shellQuote).joined(separator: " "))

        var status: Int32 = -1
        do {
            for try await event in ProcessRunner.stream(tool, arguments: args, environment: env,
                                                        currentDirectory: input.deletingLastPathComponent()) {
                switch event {
                case .stdout(let line):
                    if let range = line.range(of: "Target is now signed: ") {
                        target = URL(filePath: String(line[range.upperBound...]))
                    }
                    append(.stdout, line)
                case .stderr(let line):
                    append(.stderr, line)
                case .exit(let code):
                    status = code
                }
            }
        } catch {
            append(.failure, error.localizedDescription)
        }

        lastExitStatus = status
        let elapsed = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        if Task.isCancelled {
            phase = .idle
            append(.failure, "Cancelled")
        } else if status == 0, FileManager.default.fileExists(atPath: target.path) {
            output = target
            phase = .signed
            append(.success, "Signed \(target.lastPathComponent) in \(elapsed.formatted(.number.precision(.fractionLength(1))))s")
            outputPreview = await AppPreview.inspect(target)
            if UserDefaults.standard.bool(forKey: SettingsKey.revealAfterSign) {
                NSWorkspace.shared.activateFileViewerSelecting([target])
            }
        } else {
            let reason = log.last { $0.kind == .stderr }?.text ?? "applesign exited with status \(status)"
            phase = .failed(reason)
            append(.failure, "Signing failed (exit \(status))")
        }
        signTask = nil
    }

    // MARK: Device install

    func install(_ ipa: URL, on device: IOSDevice) {
        guard let tool = Tools.find("ideviceinstaller") else {
            append(.failure, "ideviceinstaller not found. Install it with: brew install ideviceinstaller")
            return
        }
        if case .installing = installState { return }
        installState = .installing(device.udid)
        Task {
            let args = ["-u", device.udid, "install", ipa.path]
            append(.command, "$ ideviceinstaller " + args.map(Self.shellQuote).joined(separator: " "))
            var status: Int32 = -1
            do {
                for try await event in ProcessRunner.stream(tool, arguments: args) {
                    switch event {
                    case .stdout(let line): append(.stdout, line)
                    case .stderr(let line): append(.stderr, line)
                    case .exit(let code): status = code
                    }
                }
            } catch {
                append(.failure, error.localizedDescription)
            }
            if status == 0 {
                installState = .installed(device.udid)
                append(.success, "Installed \(ipa.lastPathComponent) on \(device.name)")
            } else {
                installState = .failed(device.udid)
                append(.failure, "Install on \(device.name) failed (exit \(status))")
            }
        }
    }

    // MARK: Console

    func append(_ kind: LogLine.Kind, _ text: String) {
        log.append(LogLine(id: nextLogID, date: .now, kind: kind, text: text))
        nextLogID += 1
        if log.count > 5000 { log.removeFirst(log.count - 5000) }
    }

    func clearLog() {
        log.removeAll()
        lastExitStatus = nil
    }

    var logText: String { log.map(\.text).joined(separator: "\n") }

    // MARK: Helpers

    private func save(_ value: some Encodable, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    nonisolated static func shellQuote(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:,+@%".contains($0) }) { return s }
        return "'" + s.replacing("'", with: "'\\''") + "'"
    }
}

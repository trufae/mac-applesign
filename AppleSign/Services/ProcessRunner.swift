import Foundation
import Synchronization

/// One event emitted by a running child process.
nonisolated enum ProcessEvent: Sendable {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

nonisolated struct ProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var output: String { String(decoding: stdout, as: UTF8.self) }
}

/// Thin async wrapper around `Process`, streaming output line by line.
nonisolated enum ProcessRunner {
    /// Streams stdout/stderr lines and finishes with `.exit`. Cancelling the
    /// consuming task terminates the child process.
    static func stream(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = Tools.environment,
        currentDirectory: URL? = nil
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = environment
            if let currentDirectory { process.currentDirectoryURL = currentDirectory }
            process.standardInput = FileHandle.nullDevice

            let group = DispatchGroup()
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            pump(out, group: group) { continuation.yield(.stdout($0)) }
            pump(err, group: group) { continuation.yield(.stderr($0)) }

            group.enter()
            process.terminationHandler = { _ in group.leave() }
            continuation.onTermination = { reason in
                if case .cancelled = reason, process.isRunning { process.terminate() }
            }
            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
                return
            }
            group.notify(queue: .global()) {
                continuation.yield(.exit(process.terminationStatus))
                continuation.finish()
            }
        }
    }

    /// Runs a process to completion and collects its output.
    @concurrent
    static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = Tools.environment
    ) async throws -> ProcessResult {
        var stdout = Data(), stderr = Data(), status: Int32 = -1
        for try await event in stream(executable, arguments: arguments, environment: environment) {
            switch event {
            case .stdout(let line): stdout.append(contentsOf: Data((line + "\n").utf8))
            case .stderr(let line): stderr.append(contentsOf: Data((line + "\n").utf8))
            case .exit(let code): status = code
            }
        }
        return ProcessResult(status: status, stdout: stdout, stderr: stderr)
    }

    /// Runs a process and returns raw stdout bytes (for binary output like `unzip -p`).
    @concurrent
    static func data(_ executable: URL, arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = Tools.environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = try out.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        return data
    }

    /// Splits a pipe into lines, leaving `group` once EOF is reached.
    private static func pump(_ pipe: Pipe, group: DispatchGroup, emit: @escaping @Sendable (String) -> Void) {
        let buffer = Mutex(Data())
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            let lines: [String] = buffer.withLock { data in
                if chunk.isEmpty {
                    defer { data.removeAll() }
                    return data.isEmpty ? [] : [decode(data)]
                }
                data.append(chunk)
                var lines: [String] = []
                while let nl = data.firstIndex(of: 0x0A) {
                    lines.append(decode(data[data.startIndex..<nl]))
                    data.removeSubrange(data.startIndex...nl)
                }
                return lines
            }
            lines.forEach(emit)
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            }
        }
    }

    private static func decode(_ data: Data) -> String {
        stripANSI(String(decoding: data, as: UTF8.self))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
    }

    static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        return s.replacing(#/\x{1B}\[[0-9;?]*[ -\/]*[@-~]/#, with: "")
    }
}

/// Locates helper tools. GUI apps get a minimal PATH, so Homebrew prefixes
/// are appended for insert_dylib, 7z, ideviceinstaller and friends.
nonisolated enum Tools {
    static let searchPaths: [String] = {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return (inherited + extra).filter { seen.insert($0).inserted }
    }()

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":")
        env["NO_COLOR"] = "1"
        env["FORCE_COLOR"] = "0"
        return env
    }

    static func find(_ name: String) -> URL? {
        for dir in searchPaths {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(filePath: path)
            }
        }
        return nil
    }

    static let unzip = URL(filePath: "/usr/bin/unzip")

    /// The applesign binary: user override, then the bundled SEA, then PATH.
    static var applesign: URL? {
        if let custom = UserDefaults.standard.string(forKey: SettingsKey.applesignPath), !custom.isEmpty,
           FileManager.default.isExecutableFile(atPath: custom) {
            return URL(filePath: custom)
        }
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/Helpers/applesign")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return find("applesign")
    }

    /// `applesign --version` of the binary in use, or nil if it cannot run.
    @concurrent
    static func applesignVersion() async -> String? {
        guard let tool = applesign, let r = try? await ProcessRunner.run(tool, arguments: ["--version"]), r.status == 0 else {
            return nil
        }
        let v = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// AppleSign's own version, as "1.0.1 (2)".
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

nonisolated enum SettingsKey {
    static let applesignPath = "applesignPath"
    static let autoSign = "autoSignOnDrop"
    static let revealAfterSign = "revealAfterSign"
    static let options = "signingOptions"
    static let identity = "identity"
    static let profile = "mobileprovision"
    static let recentProfiles = "recentProfiles"
}

import CryptoKit
import Foundation
import Security

/// A decoded `.mobileprovision`.
nonisolated struct ProvisioningProfile: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let teamName: String
    let teamID: String
    let appID: String
    let expiration: Date?
    let deviceCount: Int
    let allDevices: Bool
    let getTaskAllow: Bool
    /// Uppercase SHA-1 of each certificate, matching `security find-identity` hashes.
    let certificateHashes: [String]

    var id: URL { url }
    var isExpired: Bool { expiration.map { $0 < .now } ?? false }

    var kind: String {
        if allDevices { return "Enterprise" }
        if deviceCount == 0 { return "App Store" }
        return getTaskAllow ? "Development" : "Ad Hoc"
    }

    enum LoadError: LocalizedError {
        case unreadable(URL)
        var errorDescription: String? {
            if case .unreadable(let url) = self { return "\(url.lastPathComponent) is not a valid provisioning profile" }
            return nil
        }
    }

    static func load(_ url: URL) throws -> ProvisioningProfile {
        let data = try Data(contentsOf: url)
        guard let plist = decodeCMS(data),
              let dict = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        else { throw LoadError.unreadable(url) }
        let ents = dict["Entitlements"] as? [String: Any] ?? [:]
        let certs = dict["DeveloperCertificates"] as? [Data] ?? []
        return ProvisioningProfile(
            url: url,
            name: dict["Name"] as? String ?? url.deletingPathExtension().lastPathComponent,
            teamName: dict["TeamName"] as? String ?? "",
            teamID: (dict["TeamIdentifier"] as? [String])?.first ?? "",
            appID: ents["application-identifier"] as? String ?? "",
            expiration: dict["ExpirationDate"] as? Date,
            deviceCount: (dict["ProvisionedDevices"] as? [String])?.count ?? 0,
            allDevices: dict["ProvisionsAllDevices"] as? Bool ?? false,
            getTaskAllow: ents["get-task-allow"] as? Bool ?? false,
            certificateHashes: certs.map { Insecure.SHA1.hash(data: $0).map { String(format: "%02X", $0) }.joined() }
        )
    }

    private static func decodeCMS(_ data: Data) -> Data? {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return nil }
        let ok = data.withUnsafeBytes { buf in
            CMSDecoderUpdateMessage(decoder, buf.baseAddress!, buf.count) == errSecSuccess
        }
        guard ok, CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return nil }
        var content: CFData?
        guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess else { return nil }
        return content as Data?
    }

    /// Profiles installed by Xcode and the device support tools.
    @concurrent
    static func discover() async -> [ProvisioningProfile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs = [
            "Library/MobileDevice/Provisioning Profiles",
            "Library/Developer/Xcode/UserData/Provisioning Profiles",
        ].map { home.appending(path: $0) }
        let files = dirs.flatMap { dir in
            (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }.filter { $0.pathExtension == "mobileprovision" }
        return files.compactMap { try? load($0) }
            .filter { !$0.isExpired }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// A codesigning identity as listed by `applesign -L`.
nonisolated struct SigningIdentity: Identifiable, Hashable, Sendable {
    let hash: String
    let name: String
    var id: String { hash }

    /// "Apple Development: Jane (ABCDE12345)" → "Apple Development"
    var kind: String { name.split(separator: ":").first.map(String.init) ?? name }
    var owner: String {
        guard let colon = name.firstIndex(of: ":") else { return name }
        return name[name.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ output: String) -> [SigningIdentity] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, parts[0].count == 40 else { return nil }
            return SigningIdentity(hash: String(parts[0]), name: String(parts[1]).trimmingCharacters(in: .init(charactersIn: "\"")))
        }
    }
}

import Foundation

/// What we can learn about an IPA (or .app bundle) without unpacking it.
nonisolated struct AppPreview: Sendable, Equatable {
    var name: String
    var bundleID: String
    var version: String
    var minimumOS: String
    var iconData: Data?
    var fileSize: Int64

    static func inspect(_ url: URL) async -> AppPreview {
        let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))
            .flatMap { $0.fileSize.map(Int64.init) } ?? 0
        var preview = AppPreview(name: url.deletingPathExtension().lastPathComponent,
                                 bundleID: "", version: "", minimumOS: "", fileSize: size)
        if url.pathExtension.lowercased() == "app" {
            await preview.fill(bundle: url)
        } else if url.pathExtension.lowercased() == "ipa" {
            await preview.fill(ipa: url)
        }
        return preview
    }

    private mutating func apply(_ info: [String: Any]) {
        name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? name
        bundleID = info["CFBundleIdentifier"] as? String ?? ""
        let short = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        version = build.isEmpty || build == short ? short : "\(short) (\(build))"
        minimumOS = info["MinimumOSVersion"] as? String ?? ""
    }

    private mutating func fill(ipa: URL) async {
        guard let listing = try? await ProcessRunner.run(Tools.unzip, arguments: ["-Z1", ipa.path]) else { return }
        let entries = listing.output.split(separator: "\n").map(String.init)
        // Payload/Foo.app/Info.plist
        guard let plistEntry = entries.first(where: {
            $0.hasPrefix("Payload/") && $0.hasSuffix(".app/Info.plist") && $0.split(separator: "/").count == 3
        }) else { return }
        let appDir = String(plistEntry.dropLast("Info.plist".count))
        guard let data = try? await ProcessRunner.data(Tools.unzip, arguments: ["-p", ipa.path, plistEntry]),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        apply(info)
        let names = entries.filter { $0.hasPrefix(appDir) && !$0.dropFirst(appDir.count).contains("/") }
            .map { String($0.dropFirst(appDir.count)) }
        if let icon = Self.bestIcon(names, info: info) {
            iconData = try? await ProcessRunner.data(Tools.unzip, arguments: ["-p", ipa.path, appDir + icon])
        }
    }

    private mutating func fill(bundle: URL) async {
        guard let data = try? Data(contentsOf: bundle.appending(path: "Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        apply(info)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: bundle.path)) ?? []
        if let icon = Self.bestIcon(names, info: info) {
            iconData = try? Data(contentsOf: bundle.appending(path: icon))
        }
    }

    /// Picks the largest app icon PNG shipped at the bundle root.
    private static func bestIcon(_ files: [String], info: [String: Any]) -> String? {
        let primary = (info["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        var prefixes = primary?["CFBundleIconFiles"] as? [String] ?? []
        if let name = primary?["CFBundleIconName"] as? String { prefixes.append(name) }
        prefixes += info["CFBundleIconFiles"] as? [String] ?? []
        prefixes.append("AppIcon")
        let pngs = files.filter { name in
            name.lowercased().hasSuffix(".png") && prefixes.contains { name.hasPrefix($0) }
        }
        let rank = ["60x60@3x", "76x76@2x~ipad", "60x60@2x", "@3x", "@2x"]
        return pngs.max { score($0, rank) < score($1, rank) }
    }

    private static func score(_ name: String, _ rank: [String]) -> Int {
        for (i, token) in rank.enumerated() where name.contains(token) { return rank.count - i }
        return 0
    }
}

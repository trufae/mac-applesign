import Foundation

/// Describes one node-applesign command line option. The inspector renders
/// straight from `OptionSpec.all`, and the argument list is built from it,
/// so adding an option here is all it takes to expose it.
nonisolated struct OptionSpec: Identifiable, Sendable {
    enum Kind: Sendable {
        case flag
        case text(placeholder: String)
        case file(extensions: [String])
        case directory
        case choice([String])
    }

    enum Group: String, CaseIterable, Sendable {
        case signing = "Signing"
        case entitlements = "Entitlements"
        case infoPlist = "Info.plist"
        case stripping = "Stripping"
        case packaging = "Packaging"
        case debugging = "Debugging"

        var symbol: String {
            switch self {
            case .signing: "signature"
            case .entitlements: "checkmark.seal"
            case .infoPlist: "list.bullet.rectangle"
            case .stripping: "scissors"
            case .packaging: "shippingbox"
            case .debugging: "ladybug"
            }
        }
    }

    let id: String
    let short: Character?
    let title: String
    let help: String
    let kind: Kind
    let group: Group
    var experimental = false

    var flag: String { "--\(id)" }
    var usage: String { short.map { "-\($0), \(flag)" } ?? flag }
    var isFlag: Bool { if case .flag = kind { true } else { false } }
}

nonisolated extension OptionSpec {
    // Identity (-i), mobileprovision (-m) and output (-o) live in the crafting
    // table itself; -h, -L and --version are actions rather than options.
    static let all: [OptionSpec] = [
        // Signing
        .init(id: "clone-entitlements", short: "c", title: "Clone entitlements",
              help: "Use the entitlements embedded in the provisioning profile to sign every binary.",
              kind: .flag, group: .entitlements),
        .init(id: "all", short: "a", title: "Sign all binaries",
              help: "Re-sign every Mach-O, even those unrelated to the app.", kind: .flag, group: .signing),
        .init(id: "verify", short: "v", title: "Verify at the end",
              help: "Verify all the signed files once signing finishes.", kind: .flag, group: .signing),
        .init(id: "verify-twice", short: "V", title: "Verify twice",
              help: "Verify after signing every file and again at the end.", kind: .flag, group: .signing),
        .init(id: "parallel", short: "P", title: "Parallel signing",
              help: "Sign independent layers of the dependency graph in parallel.",
              kind: .flag, group: .signing, experimental: true),
        .init(id: "device-provision", short: "D", title: "Device provisioning",
              help: "Automatically find the mobileprovision for the connected device.",
              kind: .flag, group: .signing),
        .init(id: "self-sign-provision", short: "S", title: "Self-sign provisioning",
              help: "Create a custom, unsigned mobileprovision.", kind: .flag, group: .signing, experimental: true),
        .init(id: "pseudo-sign", short: "Z", title: "Pseudo sign",
              help: "Pseudo sign the binaries instead of using a real identity.",
              kind: .flag, group: .signing, experimental: true),
        .init(id: "use-openssl", short: nil, title: "Use OpenSSL",
              help: "Decode the provisioning with OpenSSL cms instead of Apple's security tool.",
              kind: .flag, group: .signing),
        .init(id: "unfair", short: "u", title: "Sign encrypted apps",
              help: "Re-sign FairPlay encrypted applications.", kind: .flag, group: .signing),
        .init(id: "keychain", short: "k", title: "Keychain",
              help: "Alternative keychain file holding the signing identity.",
              kind: .file(extensions: ["keychain", "keychain-db"]), group: .signing),
        .init(id: "run", short: "R", title: "Pre-sign hook",
              help: "Script to run before signing starts. Receives APPLESIGN_* environment variables.",
              kind: .file(extensions: []), group: .signing),

        // Entitlements
        .init(id: "massage-entitlements", short: "M", title: "Massage entitlements",
              help: "Remove privileged entitlements that would break installation.",
              kind: .flag, group: .entitlements),
        .init(id: "without-get-task-allow", short: "t", title: "No get-task-allow",
              help: "Do not set the get-task-allow entitlement.",
              kind: .flag, group: .entitlements, experimental: true),
        .init(id: "entry-entitlement", short: "E", title: "Generic entitlements",
              help: "Use the generic default entitlements. Useful when troubleshooting.",
              kind: .flag, group: .entitlements, experimental: true),
        .init(id: "no-entitlements-file", short: "C", title: "No .entitlements file",
              help: "Do not create the .entitlements file inside the IPA.", kind: .flag, group: .entitlements),
        .init(id: "bundleid-access-group", short: "B", title: "Bundle ID access group",
              help: "Add $(TeamIdentifier).bundleid to keychain-access-groups.", kind: .flag, group: .entitlements),
        .init(id: "add-access-group", short: "K", title: "Add access group",
              help: "Add $(TeamIdentifier).NAME to keychain-access-groups.",
              kind: .text(placeholder: "NAME"), group: .entitlements),
        .init(id: "entitlements", short: "e", title: "Entitlements file",
              help: "Sign with this entitlements plist.",
              kind: .file(extensions: ["plist", "entitlements", "xml"]), group: .entitlements, experimental: true),
        .init(id: "add-entitlements", short: "N", title: "Append entitlements",
              help: "Merge the entitlements from this plist.",
              kind: .file(extensions: ["plist", "entitlements", "xml"]), group: .entitlements, experimental: true),
        .init(id: "json", short: "j", title: "Custom signing JSON",
              help: "Alternative JSON describing per-file entitlements.",
              kind: .text(placeholder: "{}"), group: .entitlements),

        // Info.plist
        .init(id: "bundleid", short: "b", title: "Bundle ID",
              help: "Change the bundle identifier when repackaging.",
              kind: .text(placeholder: "com.example.app"), group: .infoPlist),
        .init(id: "osversion", short: "O", title: "Minimum OS version",
              help: "Force a specific MinimumOSVersion in Info.plist.",
              kind: .text(placeholder: "9.0"), group: .infoPlist),
        .init(id: "force-family", short: "f", title: "Force iPhone family",
              help: "Force UIDeviceFamily to iPhone and drop UISupportedDevices.", kind: .flag, group: .infoPlist),
        .init(id: "allow-http", short: "H", title: "Allow HTTP",
              help: "Add NSAppTransportSecurity.NSAllowsArbitraryLoads.", kind: .flag, group: .infoPlist),

        // Stripping
        .init(id: "without-watchapp", short: "w", title: "Remove Watch app",
              help: "Remove the WatchApp before re-signing.", kind: .flag, group: .stripping),
        .init(id: "without-plugins", short: "p", title: "Remove plugins",
              help: "Remove app extensions (excluding XCTests).", kind: .flag, group: .stripping),
        .init(id: "without-xctests", short: "x", title: "Remove XCTests",
              help: "Remove the XCTest bundles.", kind: .flag, group: .stripping),
        .init(id: "without-signing-files", short: "F", title: "Remove signing files",
              help: "Remove signing related files.", kind: .flag, group: .stripping),
        .init(id: "lipo", short: "l", title: "Thin architecture",
              help: "lipo -thin every binary to the given architecture.",
              kind: .choice(["", "arm64", "arm64e", "armv7"]), group: .stripping),

        // Packaging
        .init(id: "insert", short: "I", title: "Insert dylib",
              help: "Insert a dynamic library (e.g. frida-gadget) into the main executable. Needs insert_dylib.",
              kind: .file(extensions: ["dylib"]), group: .packaging),
        .init(id: "replace", short: "r", title: "Replace input",
              help: "Overwrite the input IPA with the re-signed one.", kind: .flag, group: .packaging),
        .init(id: "use-7zip", short: "7", title: "Use 7-Zip",
              help: "Decompress with 7z instead of unzip.", kind: .flag, group: .packaging),
        .init(id: "all-dirs", short: "A", title: "Archive all directories",
              help: "Archive every directory, not just Payload/.", kind: .flag, group: .packaging),
        .init(id: "ignore-zip-errors", short: "z", title: "Ignore unzip errors",
              help: "Ignore unzip/7z decompression errors.", kind: .flag, group: .packaging),
        .init(id: "single", short: "s", title: "Single file",
              help: "Sign a single Mach-O file instead of an IPA.", kind: .flag, group: .packaging),
        .init(id: "tempdir", short: "T", title: "Temporary directory",
              help: "Where to unpack the IPA while signing.", kind: .directory, group: .packaging),

        // Debugging
        .init(id: "noclean", short: "n", title: "Keep temporary files",
              help: "Keep temporary files when a signing error happens.", kind: .flag, group: .debugging),
        .init(id: "debug", short: "d", title: "Debug JSON",
              help: "Write a JSON file describing the whole signing process.",
              kind: .text(placeholder: "/tmp/applesign.json"), group: .debugging),
    ]

    static func groups(matching query: String) -> [(Group, [OptionSpec])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return Group.allCases.compactMap { group in
            let specs = all.filter { spec in
                spec.group == group && (q.isEmpty
                    || spec.title.lowercased().contains(q)
                    || spec.usage.lowercased().contains(q)
                    || spec.help.lowercased().contains(q))
            }
            return specs.isEmpty ? nil : (group, specs)
        }
    }
}

/// The values of every option in `OptionSpec.all`, keyed by long name so new
/// options never break decoding of saved settings.
nonisolated struct SigningOptions: Codable, Equatable, Sendable {
    var flags: Set<String> = []
    var values: [String: String] = [:]
    /// Folder where re-signed IPAs are written. Empty means next to the input.
    var outputDirectory = ""

    static let defaults = SigningOptions(flags: ["clone-entitlements"])

    subscript(flag id: String) -> Bool {
        get { flags.contains(id) }
        set { if newValue { flags.insert(id) } else { flags.remove(id) } }
    }

    subscript(value id: String) -> String {
        get { values[id] ?? "" }
        set { values[id] = newValue.isEmpty ? nil : newValue }
    }

    var changedCount: Int {
        flags.count + values.count + (outputDirectory.isEmpty ? 0 : 1)
    }

    var arguments: [String] {
        OptionSpec.all.flatMap { spec -> [String] in
            if spec.isFlag { return flags.contains(spec.id) ? [spec.flag] : [] }
            let v = self[value: spec.id].trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? [] : [spec.flag, v]
        }
    }
}

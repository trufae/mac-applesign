import Foundation
import Observation

nonisolated struct IOSDevice: Identifiable, Hashable, Sendable {
    let udid: String
    var name: String
    var productType: String
    var osVersion: String

    var id: String { udid }
    var symbol: String {
        productType.hasPrefix("iPad") ? "ipad" : productType.hasPrefix("iPod") ? "ipodtouch" : "iphone"
    }
}

/// Polls libimobiledevice for USB-connected iOS devices.
@Observable
final class DeviceMonitor {
    private(set) var devices: [IOSDevice] = []
    private(set) var toolsInstalled = Tools.find("idevice_id") != nil && Tools.find("ideviceinstaller") != nil
    private var cache: [String: IOSDevice] = [:]
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh() async {
        guard let idevice = Tools.find("idevice_id") else {
            toolsInstalled = false
            devices = []
            return
        }
        toolsInstalled = Tools.find("ideviceinstaller") != nil
        guard let result = try? await ProcessRunner.run(idevice, arguments: ["-l"]), result.status == 0 else {
            devices = []
            return
        }
        let udids = Array(Set(result.output.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty })).sorted()
        var found: [IOSDevice] = []
        for udid in udids {
            if let known = cache[udid] {
                found.append(known)
            } else {
                let device = await Self.describe(udid)
                cache[udid] = device
                found.append(device)
            }
        }
        if found != devices { devices = found }
    }

    @concurrent
    private static func describe(_ udid: String) async -> IOSDevice {
        var device = IOSDevice(udid: udid, name: "iOS Device", productType: "", osVersion: "")
        guard let info = Tools.find("ideviceinfo"),
              let result = try? await ProcessRunner.run(info, arguments: ["-u", udid]), result.status == 0
        else { return device }
        for line in result.output.split(separator: "\n") {
            let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "DeviceName": device.name = kv[1]
            case "ProductType": device.productType = kv[1]
            case "ProductVersion": device.osVersion = kv[1]
            default: break
            }
        }
        return device
    }
}

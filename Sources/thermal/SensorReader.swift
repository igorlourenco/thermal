import CoreFoundation
import Foundation
import CPrivateHID

/// A single temperature reading.
struct TemperatureReading: Identifiable {
    let name: String       // e.g. "pACC MTR Temp Sensor4", "GPU MTR Temp Sensor1"
    let celsius: Double
    var id: String { name }
}

/// Reads Apple Silicon temperature sensors via the private
/// IOHIDEventSystemClient API. No sudo / root required.
final class SensorReader {

    private let client: IOHIDEventSystemClientRef

    init?() {
        // Create rule -> we own this; released in deinit via the C helper.
        guard let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            return nil
        }
        client = c

        // Match only Apple vendor temperature sensors.
        let matching: [String: Int] = [
            "PrimaryUsagePage": Int(kHIDPage_AppleVendor),
            "PrimaryUsage": Int(kHIDUsage_AppleVendor_TemperatureSensor),
        ]
        IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
    }

    deinit {
        // Swift sees the client as an OpaquePointer, so release from C.
        CPHIDReleaseClient(client)
    }

    /// Snapshot of all temperature sensors right now.
    func readAll() -> [TemperatureReading] {
        // "Copy" naming convention => Swift/ARC owns and releases this array.
        guard let services = IOHIDEventSystemClientCopyServices(client) else {
            return []
        }

        let count = CFArrayGetCount(services)
        var readings: [TemperatureReading] = []
        readings.reserveCapacity(count)

        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let service = unsafeBitCast(raw, to: IOHIDServiceClientRef.self)

            // Sensor name lives in the "Product" property (ARC-managed).
            guard let nameCF = IOHIDServiceClientCopyProperty(service, "Product" as CFString),
                  CFGetTypeID(nameCF) == CFStringGetTypeID()
            else { continue }
            let name = (nameCF as! CFString) as String

            // Latest temperature event (opaque pointer -> manual release).
            guard let event = IOHIDServiceClientCopyEvent(
                service,
                Int64(kIOHIDEventTypeTemperature),
                0,
                0
            ) else { continue }
            defer { CPHIDReleaseEvent(event) }

            let celsius = IOHIDEventGetFloatValue(event, CPHIDTemperatureField())

            // Some services report 0.0 when idle/unavailable.
            guard celsius > 0, celsius < 150 else { continue }

            readings.append(TemperatureReading(name: name, celsius: celsius))
        }

        return readings.sorted { $0.name < $1.name }
    }

    // MARK: - Convenience aggregates (useful for a menu bar number)

    /// Average of the CPU performance-core sensors ("pACC…").
    func cpuPerformanceCoreTemp() -> Double? {
        average(prefix: "pACC")
    }

    /// Average of the CPU efficiency-core sensors ("eACC…").
    func cpuEfficiencyCoreTemp() -> Double? {
        average(prefix: "eACC")
    }

    /// Average of the GPU sensors.
    func gpuTemp() -> Double? {
        average(prefix: "GPU")
    }

    /// Hottest sensor overall — a good single "headline" number.
    func hottest() -> TemperatureReading? {
        readAll().max { $0.celsius < $1.celsius }
    }

    private func average(prefix: String) -> Double? {
        let matching = readAll().filter { $0.name.hasPrefix(prefix) }
        guard !matching.isEmpty else { return nil }
        return matching.map(\.celsius).reduce(0, +) / Double(matching.count)
    }
}

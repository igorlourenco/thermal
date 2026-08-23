import Foundation
import IOKit
import CPrivateHID

// =============================================================================
// SMCReader.swift
// Second data source: the AppleSMC service. Complements the HID sensor hub
// with GPU, CPU-cluster, chassis/skin and airflow temperatures.
//
// Strategy: enumerate ALL keys the SMC exposes (once, at init), keep the
// ones that look like temperatures ("T…" with a float-ish type), and poll
// only those. No hardcoded key lists => works across chip generations.
// =============================================================================

final class SMCReader {

    private var conn: io_connect_t = 0

    /// Temperature keys discovered at init: (fourcc, dataType, dataSize).
    private var tempKeys: [(key: UInt32, name: String, type: UInt32, size: UInt32)] = []

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            return nil
        }

        discoverTemperatureKeys()
    }

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    // MARK: - Public

    /// Current values for all discovered temperature keys.
    /// Names are the raw 4-char SMC keys (e.g. "Tg0G") — SensorLabeler
    /// classifies them by prefix.
    func temperatures() -> [TemperatureReading] {
        var readings: [TemperatureReading] = []
        readings.reserveCapacity(tempKeys.count)

        for entry in tempKeys {
            guard let celsius = readValue(key: entry.key, type: entry.type, size: entry.size),
                  celsius > 1, celsius < 150
            else { continue }
            readings.append(TemperatureReading(name: entry.name, celsius: celsius))
        }
        return readings
    }

    // MARK: - Generic key access

    /// Read any SMC key by name, decoded to Double if the type is supported.
    func readKey(_ name: String) -> Double? {
        let code = Self.stringToFourcc(name)
        guard let info = keyInfo(code) else { return nil }
        return readValue(key: code, type: info.dataType, size: info.dataSize)
    }

    // MARK: - Fans

    struct Fan {
        let index: Int
        let rpm: Double
        let minRPM: Double?
        let maxRPM: Double?

        /// 0…1 of the fan's range, when min/max are known.
        var load: Double? {
            guard let minRPM, let maxRPM, maxRPM > minRPM else { return nil }
            return ((rpm - minRPM) / (maxRPM - minRPM)).clamped01()
        }
    }

    /// Current fan readings. Empty on fanless Macs (MacBook Air).
    func fans() -> [Fan] {
        guard let count = readKey("FNum"), count > 0 else { return [] }
        return (0..<Int(count)).compactMap { i in
            guard let rpm = readKey("F\(i)Ac") else { return nil }
            return Fan(
                index: i,
                rpm: rpm,
                minRPM: readKey("F\(i)Mn"),
                maxRPM: readKey("F\(i)Mx")
            )
        }
    }

    // MARK: - Key discovery (runs once)

    private func discoverTemperatureKeys() {
        guard let count = keyCount() else { return }

        for index in 0..<count {
            guard let key = key(at: index) else { continue }
            let name = Self.fourccToString(key)

            // Temperature keys start with 'T'.
            guard name.hasPrefix("T") else { continue }

            guard let info = keyInfo(key) else { continue }
            let typeName = Self.fourccToString(info.dataType)

            // Keep float-ish temperature types only.
            guard ["flt ", "ioft", "sp78"].contains(typeName) else { continue }

            tempKeys.append((key: key, name: name, type: info.dataType, size: info.dataSize))
        }
    }

    /// Total number of SMC keys, from the special "#KEY" key.
    private func keyCount() -> UInt32? {
        let keyCode = Self.stringToFourcc("#KEY")
        guard let info = keyInfo(keyCode),
              let value = readRaw(key: keyCode, size: info.dataSize)
        else { return nil }
        // ui32, big-endian payload.
        guard value.count >= 4 else { return nil }
        var count: UInt32 = 0
        count |= UInt32(value[0]) << 24
        count |= UInt32(value[1]) << 16
        count |= UInt32(value[2]) << 8
        count |= UInt32(value[3])
        return count
    }

    private func key(at index: UInt32) -> UInt32? {
        var input = SMCParamStruct()
        input.data8 = UInt8(kSMCGetKeyFromIndex)
        input.data32 = index
        guard let output = call(input) else { return nil }
        return output.key
    }

    private func keyInfo(_ key: UInt32) -> SMCKeyInfoData? {
        var input = SMCParamStruct()
        input.key = key
        input.data8 = UInt8(kSMCGetKeyInfo)
        guard let output = call(input) else { return nil }
        return output.keyInfo
    }

    // MARK: - Value reading

    private func readRaw(key: UInt32, size: UInt32) -> [UInt8]? {
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = size
        input.data8 = UInt8(kSMCReadKey)
        guard let output = call(input) else { return nil }

        return withUnsafeBytes(of: output.bytes) { raw in
            Array(raw.prefix(Int(size)))
        }
    }

    private func readValue(key: UInt32, type: UInt32, size: UInt32) -> Double? {
        guard let bytes = readRaw(key: key, size: size) else { return nil }
        let typeName = Self.fourccToString(type)

        switch typeName {
        case "flt ":
            // 4-byte IEEE float, little-endian (standard on Apple Silicon).
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                     | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))

        case "ioft":
            // 64-bit unsigned fixed point, 16 fractional bits, little-endian.
            guard bytes.count >= 8 else { return nil }
            var value: UInt64 = 0
            for i in (0..<8).reversed() {
                value = (value << 8) | UInt64(bytes[i])
            }
            return Double(value) / 65536.0

        case "sp78":
            // Signed 7.8 fixed point, big-endian (Intel-era, kept for safety).
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256.0

        case "fpe2":
            // Unsigned fixed point, 2 fractional bits, big-endian.
            // Used for fan RPM on some machines.
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0

        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])

        case "ui16":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw)

        case "ui32":
            guard bytes.count >= 4 else { return nil }
            var raw: UInt32 = 0
            raw |= UInt32(bytes[0]) << 24
            raw |= UInt32(bytes[1]) << 16
            raw |= UInt32(bytes[2]) << 8
            raw |= UInt32(bytes[3])
            return Double(raw)

        default:
            return nil
        }
    }

    // MARK: - Plumbing

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            conn,
            UInt32(kSMCHandleYPCEvent),
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )

        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    // MARK: - FourCC helpers

    private static func stringToFourcc(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for scalar in s.unicodeScalars.prefix(4) {
            result = (result << 8) | (scalar.value & 0xff)
        }
        return result
    }

    private static func fourccToString(_ value: UInt32) -> String {
        let chars: [Character] = (0..<4).reversed().map { shift in
            let byte = UInt8((value >> (shift * 8)) & 0xff)
            return Character(UnicodeScalar(byte))
        }
        return String(chars)
    }
}

private extension Double {
    func clamped01() -> Double { Swift.min(1, Swift.max(0, self)) }
}

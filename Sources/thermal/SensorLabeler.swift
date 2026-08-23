import Foundation

// =============================================================================
// SensorLabeler.swift  (v3)
// Turns raw sensor names into user-friendly grouped readings.
//
// Handles three naming schemes:
//   M1/M2-era HID:  "pACC…", "eACC…", "GPU…", "ANE…"
//   M3/M4-era HID:  "PMU tdie1…N"  (generic die sensors)
//   SMC keys:       4-char codes like "Tg0G", "Te05", "Ts0P"
// =============================================================================

/// High-level component groups a normal user understands.
enum SensorGroup: String, CaseIterable, Identifiable {
    case cpuPerformance
    case cpuEfficiency
    case soc            // generic die sensors (CPU+GPU blocks combined)
    case gpu
    case neuralEngine
    case memory
    case storage
    case battery
    case power
    case display
    case enclosure      // chassis skin / airflow
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpuPerformance: return "CPU – Performance"
        case .cpuEfficiency:  return "CPU – Efficiency"
        case .soc:            return "Chip (CPU & GPU)"
        case .gpu:            return "Graphics (GPU)"
        case .neuralEngine:   return "Neural Engine"
        case .memory:         return "Memory"
        case .storage:        return "Storage (SSD)"
        case .battery:        return "Battery"
        case .power:          return "Power Delivery"
        case .display:        return "Display"
        case .enclosure:      return "Chassis & Airflow"
        case .other:          return "Other Sensors"
        }
    }

    var explanation: String {
        switch self {
        case .cpuPerformance: return "The fast cores that handle demanding work like compiling, gaming, and exporting."
        case .cpuEfficiency:  return "The low-power cores that handle background and light tasks."
        case .soc:            return "Temperature sensors across the main chip, covering CPU and GPU areas."
        case .gpu:            return "Renders graphics — heats up in games, video work, and some ML tasks."
        case .neuralEngine:   return "Dedicated hardware for machine-learning tasks."
        case .memory:         return "Unified memory shared by CPU and GPU."
        case .storage:        return "Your built-in SSD."
        case .battery:        return "Battery cells — should stay cool most of the time."
        case .power:          return "Chips that manage power to the rest of the system."
        case .display:        return "Display and related electronics."
        case .enclosure:      return "The surface of your Mac and the air moving through it."
        case .other:          return "Sensors that don't fit a common category on this Mac."
        }
    }

    var symbolName: String {
        switch self {
        case .cpuPerformance, .cpuEfficiency, .soc: return "cpu"
        case .gpu:          return "cube.transparent"
        case .neuralEngine: return "brain"
        case .memory:       return "memorychip"
        case .storage:      return "internaldrive"
        case .battery:      return "battery.75"
        case .power:        return "bolt"
        case .display:      return "display"
        case .enclosure:    return "macbook"
        case .other:        return "sensor"
        }
    }

    var sortOrder: Int {
        switch self {
        case .soc:            return 0
        case .cpuPerformance: return 1
        case .cpuEfficiency:  return 2
        case .gpu:            return 3
        case .neuralEngine:   return 4
        case .memory:         return 5
        case .storage:        return 6
        case .battery:        return 7
        case .power:          return 8
        case .display:        return 9
        case .enclosure:      return 10
        case .other:          return 11
        }
    }
}

/// Plain-language thermal status with per-component thresholds.
enum ThermalStatus: String {
    case cool   = "Cool"
    case normal = "Normal"
    case warm   = "Warm"
    case hot    = "Hot"

    /// (warm, hot) thresholds per group, in °C. Below warm-10 => "Cool".
    static func thresholds(for group: SensorGroup) -> (warm: Double, hot: Double) {
        switch group {
        case .cpuPerformance, .cpuEfficiency, .soc, .gpu, .neuralEngine:
            return (75, 95)   // dies routinely run hot; throttling ~100+
        case .memory, .power, .display, .other:
            return (65, 85)
        case .storage:
            return (55, 70)   // SSDs prefer staying cooler
        case .battery:
            return (40, 47)   // batteries should stay near ambient
        case .enclosure:
            // Apple Silicon "skin" (Ts…) sensors are internal chassis
            // measurement points, not the outer surface — they idle in the
            // low 50s. Thresholds reflect that, not touch-surface comfort.
            return (62, 70)
        }
    }

    init(celsius: Double, group: SensorGroup) {
        let t = Self.thresholds(for: group)
        switch celsius {
        case ..<(t.warm - 10): self = .cool
        case ..<t.warm:        self = .normal
        case ..<t.hot:         self = .warm
        default:               self = .hot
        }
    }
}

/// One row of the user-facing UI.
struct GroupedReading: Identifiable {
    let group: SensorGroup
    let celsius: Double            // hottest sensor in the group
    let status: ThermalStatus
    let sensors: [TemperatureReading]   // deduplicated

    var id: String { group.id }

    /// e.g. "Graphics (GPU) · 52° · Normal"
    var summaryLine: String {
        "\(group.displayName) · \(Int(celsius.rounded()))° · \(status.rawValue)"
    }
}

/// Learns which channels are placeholders by watching them over time.
/// Real thermal sensors jitter between polls; limit/config channels
/// ("placeholder walls") never move at all.
final class PlaceholderTracker {

    private struct Entry {
        var value: Double
        var samples: Int
        var changed: Bool
    }

    private var entries: [String: Entry] = [:]
    private(set) var polls = 0

    /// Enough observations to trust time-based detection.
    var warmedUp: Bool { polls >= 5 }

    func observe(_ readings: [TemperatureReading]) {
        polls += 1
        for r in readings {
            // Placeholder walls flicker to garbage (2–5 °C) between reads of
            // their frozen value. Garbage doesn't count as movement — a wall
            // is a channel that never moves when it reads something plausible.
            guard r.celsius >= 15 else { continue }
            if var entry = entries[r.name] {
                if entry.value != r.celsius {
                    entry.changed = true
                    entry.value = r.celsius
                }
                entry.samples += 1
                entries[r.name] = entry
            } else {
                entries[r.name] = Entry(value: r.celsius, samples: 1, changed: false)
            }
        }
    }

    /// True when the channel has never moved across its plausible samples.
    /// 3 samples is enough — the >=4-sibling family rule in dropStaticWalls
    /// guards against real sensors that idle still for a few polls.
    func isStatic(_ name: String) -> Bool {
        guard let entry = entries[name] else { return false }
        return !entry.changed && entry.samples >= 3
    }
}

enum SensorLabeler {

    /// Maps a raw sensor name to a group.
    static func classify(_ rawName: String) -> SensorGroup {
        // 4-char names starting with "T" are SMC keys — different scheme.
        if rawName.count == 4, rawName.hasPrefix("T") {
            return classifySMCKey(rawName)
        }

        let n = rawName.lowercased()

        // --- M1/M2-era per-block HID names ---
        if n.hasPrefix("pacc")                       { return .cpuPerformance }
        if n.hasPrefix("eacc")                       { return .cpuEfficiency }
        if n.hasPrefix("gpu")                        { return .gpu }
        if n.hasPrefix("ane") || n.contains("ane ")  { return .neuralEngine }

        // --- M3/M4-era generic die sensors ---
        if n.contains("tdie")                        { return .soc }

        // --- Everything else ---
        if n.hasPrefix("soc") || n.contains("dram") || n.contains("ddr") {
            return .memory
        }
        if n.contains("nand") || n.contains("ssd")   { return .storage }
        if n.contains("batt") || n.contains("gas gauge") {
            return .battery
        }
        if n.hasPrefix("pmu") || n.hasPrefix("pmgr") || n.contains("tdev") {
            return .power
        }
        if n.contains("disp") || n.contains("backlight") {
            return .display
        }
        return .other
    }

    /// SMC temperature keys, classified by their (mostly stable) prefixes.
    /// Verify against your machine with --raw; unknowns land in Other, where
    /// they're visible and easy to promote into a proper group later.
    static func classifySMCKey(_ key: String) -> SensorGroup {
        switch key.prefix(2) {
        case "Te":                                  // efficiency cores (M3/M4)
            return .cpuEfficiency
        case "Tp":                                  // performance cores
            return .cpuPerformance
        case "Tf":
            // M3-family quirk: Tf0x/Tf4x are P-cores, Tf1x/Tf2x are GPU.
            let third = key.dropFirst(2).first
            return (third == "1" || third == "2") ? .gpu : .cpuPerformance
        case "Tg", "TG":                            // GPU die / GPU-adjacent
            return .gpu
        case "TC":
            // CPU cluster aggregates: on M4, TCMz matches the hottest
            // P-core reading exactly (verified empirically).
            return .soc
        case "Tm", "TM":                            // memory
            return .memory
        case "TH":                                  // drive bays / NAND
            return .storage
        case "TB", "Tb":                            // battery
            return .battery
        case "Ts":                                  // skin (chassis surface)
            return .enclosure
        case "Ta", "TA":                            // airflow / ambient
            return .enclosure
        case "TV", "TL":
            // "TVM…" tracks CPU load, not the screen — it's a voltage
            // regulator (verified empirically on M4 Pro).
            if key.hasPrefix("TVM") || key.hasPrefix("TVm") {
                return .power
            }
            return .display
        default:
            return .other
        }
    }

    /// Names not worth showing at all (calibration/reference channels).
    static func isNoise(_ rawName: String) -> Bool {
        let n = rawName.lowercased()
        return n.contains("tcal") || n.contains("reference")
    }

    /// Drops placeholder channels. Real thermal sensors always jitter, so
    /// bit-identical values across many *sibling* keys (e.g. a wall of
    /// "Tp0…" keys all reading exactly 40.0°, or "Ta0…" keys stuck at 9.1°)
    /// are limit/config channels, not measurements.
    ///
    /// Grouped by name prefix so that unrelated sensors that legitimately
    /// agree (e.g. four battery sensors settling to the same coarse value
    /// at idle) are NOT dropped.
    static func dropPlaceholders(_ readings: [TemperatureReading]) -> [TemperatureReading] {
        struct FamilyValue: Hashable {
            let prefix: String
            let celsius: Double
        }

        var countByFamilyValue: [FamilyValue: Int] = [:]
        for r in readings {
            let key = FamilyValue(prefix: String(r.name.prefix(3)), celsius: r.celsius)
            countByFamilyValue[key, default: 0] += 1
        }

        return readings.filter {
            let key = FamilyValue(prefix: String($0.name.prefix(3)), celsius: $0.celsius)
            return (countByFamilyValue[key] ?? 0) < 4
        }
    }

    /// Same sensor can be reported by multiple instances — collapse
    /// duplicates, keeping the max reading per name.
    static func deduplicate(_ readings: [TemperatureReading]) -> [TemperatureReading] {
        var byName: [String: Double] = [:]
        for r in readings {
            byName[r.name] = max(byName[r.name] ?? -Double.infinity, r.celsius)
        }
        return byName.map { TemperatureReading(name: $0.key, celsius: $0.value) }
    }

    /// Drops placeholder walls using observed history: a channel counts as a
    /// placeholder only if it has NEVER moved across the tracker's polls AND
    /// at least 4 same-prefix siblings sit static at the same value. Immune
    /// to the two failure modes of the snapshot heuristic: walls that jitter
    /// microscopically under load (kept by mistake), and real sensors whose
    /// coarse quantization makes them collide at idle (dropped by mistake).
    static func dropStaticWalls(
        _ readings: [TemperatureReading], tracker: PlaceholderTracker
    ) -> [TemperatureReading] {
        struct FamilyValue: Hashable {
            let prefix: String
            let celsius: Double
        }

        var staticCount: [FamilyValue: Int] = [:]
        for r in readings where tracker.isStatic(r.name) {
            let key = FamilyValue(prefix: String(r.name.prefix(3)), celsius: r.celsius)
            staticCount[key, default: 0] += 1
        }

        // A "wall": >= 4 same-prefix channels frozen at the same value.
        let wallPairs = Set(staticCount.filter { $0.value >= 4 }.map(\.key))
        let wallFamilies = Set(wallPairs.map(\.prefix))

        return readings.filter { r in
            let key = FamilyValue(prefix: String(r.name.prefix(3)), celsius: r.celsius)
            // The wall value itself, static or momentarily matching.
            if wallPairs.contains(key) { return false }
            // Wall families also flicker to garbage (2–5 °C on this M4 Pro).
            // No internal Mac part runs below ~15° in operation, so inside a
            // wall family such readings are noise, not measurements.
            if wallFamilies.contains(key.prefix), r.celsius < 15 { return false }
            return true
        }
    }

    /// Main entry point: raw readings -> deduplicated, grouped, labeled rows.
    /// Pass a `PlaceholderTracker` wherever polling repeats (the app, --watch):
    /// once warmed up it replaces the single-snapshot placeholder heuristic
    /// with time-based detection.
    static func group(
        _ readings: [TemperatureReading], tracker: PlaceholderTracker? = nil
    ) -> [GroupedReading] {
        let deduped = deduplicate(readings.filter { !isNoise($0.name) })
        tracker?.observe(deduped)

        let clean: [TemperatureReading]
        if let tracker, tracker.warmedUp {
            clean = dropStaticWalls(deduped, tracker: tracker)
        } else {
            clean = dropPlaceholders(deduped)
        }
        var buckets = Dictionary(grouping: clean) { classify($0.name) }

        // On machines with proper per-cluster CPU and GPU sensors (via SMC),
        // the generic "Chip" row is redundant — its aggregate keys mirror the
        // CPU rows. Hide it there; on machines with only tdie sensors, keep it.
        if buckets[.soc] != nil,
           buckets[.cpuPerformance] != nil || buckets[.cpuEfficiency] != nil,
           buckets[.gpu] != nil {
            buckets[.soc] = nil
        }

        return buckets.compactMap { group, sensors -> GroupedReading? in
            guard let hottest = sensors.map(\.celsius).max() else { return nil }
            return GroupedReading(
                group: group,
                celsius: hottest,
                status: ThermalStatus(celsius: hottest, group: group),
                sensors: sensors.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted { $0.group.sortOrder < $1.group.sortOrder }
    }

    /// One sentence for the whole machine — menu bar tooltip / notification.
    static func overallSummary(_ grouped: [GroupedReading]) -> String {
        let hotOnes = grouped.filter { $0.status == .hot }
        let warmOnes = grouped.filter { $0.status == .warm }

        if let worst = hotOnes.max(by: { $0.celsius < $1.celsius }) {
            return "\(worst.group.displayName) is running hot (\(Int(worst.celsius.rounded()))°)."
        }

        // Battery-only warmth usually means charging / heat soak, not load.
        if let worst = warmOnes.max(by: { $0.celsius < $1.celsius }) {
            if warmOnes.allSatisfy({ $0.group == .battery }) {
                return "Battery is a bit warm — common while charging."
            }
            return "\(worst.group.displayName) is warm — expected under load."
        }
        return "Everything looks normal."
    }
}
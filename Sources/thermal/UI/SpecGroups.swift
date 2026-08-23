import Foundation

// =============================================================================
// SpecGroups.swift
// DESIGN.md §4 labels and hand-written copy, mapped onto the data layer's
// SensorGroup. The copy is the product — reproduce verbatim.
// =============================================================================

extension SensorGroup {

    /// Display label per DESIGN.md (em dashes, sentence case).
    var specLabel: String {
        switch self {
        case .cpuPerformance: return "CPU — Performance"
        case .cpuEfficiency:  return "CPU — Efficiency"
        case .gpu:            return "Graphics (GPU)"
        case .memory:         return "Memory"
        case .power:          return "Power delivery"
        case .display:        return "Display"
        case .enclosure:      return "Chassis & airflow"
        case .storage:        return "Storage (SSD)"
        case .soc:            return "Chip (CPU & GPU)"
        case .neuralEngine:   return "Neural Engine"
        case .battery:        return "Battery"
        case .other:          return "Other sensors"
        }
    }

    /// Explanation paragraph per DESIGN.md §4; data-layer copy for groups the
    /// spec doesn't cover.
    var specExplanation: String {
        switch self {
        case .cpuPerformance:
            return "The performance cores handle demanding work — compiles, exports, rendering. Sustained highs are normal; macOS manages them."
        case .cpuEfficiency:
            return "The efficiency cores run background work — indexing, sync, notifications. They stay cool almost all the time."
        case .gpu:
            return "Graphics work: displays, video decode, rendering. It warms in bursts rather than staying hot."
        case .memory:
            return "Unified memory sits beside the chip on the same package, so it tracks the die but stays much cooler."
        case .power:
            return "The regulators feeding the chip. They run hot by design — normal even when the CPU is close to idle."
        case .display:
            return "Backlight and panel driver. Brightness matters more here than workload."
        case .enclosure:
            return "Skin and airflow sensors — the closest thing to how warm the Mac feels in your hands."
        case .storage:
            return "The SSD controller. It spikes during big copies and settles within seconds."
        default:
            return explanation
        }
    }

    /// Order groups appear on the Now screen (§4.1). Chassis and storage are
    /// deliberately behind "All sensors".
    static let nowOrder: [SensorGroup] = [
        .cpuPerformance, .cpuEfficiency, .gpu, .memory, .power, .display,
    ]

    /// Fill-in order when a machine lacks some of the six Now groups.
    static let nowFallback: [SensorGroup] = [
        .soc, .neuralEngine, .battery, .enclosure, .storage, .other,
    ]
}

/// Plain-language rendering of macOS's thermal pressure levels. The OS
/// vocabulary (Nominal/Fair/Serious/Critical) stays in the data layer and
/// persisted events; the UI translates for people who aren't engineers.
extension ThermalPressure.State {
    var plainLabel: String {
        switch label {
        case "Nominal":  return "All clear"
        case "Fair":     return "Warming up"
        case "Serious":  return "Slowed by heat"
        case "Critical": return "Overheating"
        default:         return label
        }
    }
}

/// Spell out small counts ("Four apps", "five times").
func spelledOut(_ n: Int) -> String {
    let words = [
        "zero", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve",
    ]
    return n < words.count ? words[n] : String(n)
}

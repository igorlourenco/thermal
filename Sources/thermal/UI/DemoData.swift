import Foundation

// =============================================================================
// DemoData.swift
// Seed data from the prototype, QUARANTINED behind the --demo launch flag.
// Exists so screenshots and rare states (Hot, throttling) can be produced on
// demand. Must never leak into the default experience: the model only touches
// this type when ThermalModel.demoLevel != nil.
// =============================================================================

enum DemoLevel: String {
    case cool, warm, hot
}

struct DemoData {
    let level: DemoLevel

    // MARK: Groups (prototype base(), shifted per level)

    struct Group {
        let group: SensorGroup
        let celsius: Double
        let peak: Double
        let sensors: [(String, Double)]
    }

    var groups: [Group] {
        let base: [(SensorGroup, Double, Double, [(String, Double)])] = [
            (.cpuPerformance, 83, 91, [("Tp01 · P-core 0", 83.4), ("Tp05 · P-core 1", 81.9), ("Tp09 · P-core 2", 84.1), ("Tp0D · P-core 3", 80.2)]),
            (.cpuEfficiency, 67, 74, [("Te01 · E-core 0", 66.8), ("Te05 · E-core 1", 67.4)]),
            (.gpu, 61, 74, [("Tg05 · GPU cluster 0", 60.4), ("Tg0D · GPU cluster 1", 61.8)]),
            (.memory, 51, 58, [("Tm02 · DRAM 0", 50.6), ("Tm06 · DRAM 1", 51.4)]),
            (.power, 83, 90, [("Ts01 · VRM A", 82.7), ("Ts05 · VRM B", 83.6)]),
            (.display, 71, 76, [("Td01 · Panel", 70.8)]),
            (.enclosure, 57, 61, [("Ta01 · Airflow in", 42.1), ("Tc0A · Top case", 57.3)]),
            (.storage, 42, 47, [("Tn01 · NAND", 41.8)]),
        ]

        let levelTemps: [SensorGroup: Double]? = {
            switch level {
            case .warm: return nil
            case .cool: return [
                .cpuPerformance: 41, .cpuEfficiency: 36, .gpu: 34, .memory: 35,
                .power: 47, .display: 39, .enclosure: 30, .storage: 32,
            ]
            case .hot: return [
                .cpuPerformance: 97, .cpuEfficiency: 81, .gpu: 88, .memory: 64,
                .power: 95, .display: 74, .enclosure: 72, .storage: 45,
            ]
            }
        }()

        return base.map { group, c, peak, sensors in
            guard let target = levelTemps?[group] else {
                return Group(group: group, celsius: c, peak: peak, sensors: sensors)
            }
            let delta = target - c
            return Group(
                group: group,
                celsius: target,
                peak: level == .hot ? max(peak, target) : target + 6,
                sensors: sensors.map { ($0.0, ($0.1 + delta * 10).rounded() / 10) }
            )
        }
    }

    func grouped() -> [GroupedReading] {
        groups.map { g in
            GroupedReading(
                group: g.group,
                celsius: g.celsius,
                status: ThermalStatus(celsius: g.celsius, group: g.group),
                sensors: g.sensors.map { TemperatureReading(name: $0.0, celsius: $0.1) }
            )
        }
    }

    func peak(for group: SensorGroup) -> Double? {
        groups.first { $0.group == group }?.peak
    }

    // MARK: Processes (notes dropped — we can't know them for real either)

    func processes() -> [HeatProcess] {
        guard level != .cool else { return [] }
        let hot = level == .hot
        return [
            HeatProcess(pid: -1, name: "Google Chrome", cpuPercent: hot ? 214 : 96),
            HeatProcess(pid: -2, name: "Xcode", cpuPercent: hot ? 186 : 74),
            HeatProcess(pid: -3, name: "Docker Desktop", cpuPercent: 94),
            HeatProcess(pid: -4, name: "Final Cut Pro", cpuPercent: 61),
        ]
    }

    // MARK: Fans

    func fans() -> [SMCReader.Fan] {
        let rpm: Double = level == .hot ? 4720 : (level == .cool ? 1210 : 2480)
        return [
            SMCReader.Fan(index: 0, rpm: rpm, minRPM: 1200, maxRPM: 5400),
            SMCReader.Fan(index: 1, rpm: rpm + 30, minRPM: 1200, maxRPM: 5400),
        ]
    }

    // MARK: History — prototype shapes stretched over the requested window

    private static let shapes: [SensorGroup: [Double]] = [
        .cpuPerformance: [0.20, 0.25, 0.30, 0.22, 0.55, 0.68, 0.45, 0.35, 0.40, 0.85, 1.00, 0.60, 0.45, 0.35],
        .cpuEfficiency: [0.30, 0.34, 0.28, 0.40, 0.44, 0.38, 0.50, 0.55, 0.62, 0.58, 0.72, 0.85, 1.00, 0.80],
        .gpu: [0.20, 0.25, 0.75, 0.85, 0.50, 0.35, 0.30, 0.40, 0.35, 0.55, 0.60, 0.45, 0.35, 0.30],
        .memory: [0.35, 0.38, 0.42, 0.40, 0.50, 0.55, 0.52, 0.60, 0.65, 0.70, 0.80, 0.90, 1.00, 0.85],
        .power: [0.40, 0.42, 0.48, 0.45, 0.58, 0.62, 0.70, 0.66, 0.78, 0.85, 0.92, 0.96, 1.00, 0.90],
        .display: [0.50, 0.52, 0.55, 0.58, 0.60, 0.62, 0.65, 0.68, 0.70, 0.75, 0.80, 0.90, 1.00, 0.92],
        .enclosure: [0.30, 0.32, 0.40, 0.45, 0.38, 0.42, 0.40, 0.44, 0.45, 0.70, 0.80, 0.60, 0.45, 0.40],
        .storage: [0.30, 0.35, 0.80, 0.45, 0.38, 0.35, 0.42, 0.40, 0.55, 0.48, 0.60, 0.70, 0.75, 0.60],
    ]

    func samples(for group: SensorGroup, hoursBack: Double) -> [(date: Date, celsius: Double)] {
        guard let shape = Self.shapes[group],
              let current = groups.first(where: { $0.group == group })
        else { return [] }
        let now = Date()
        let span = hoursBack * 3600
        let count = shape.count
        return shape.enumerated().map { i, v in
            let fraction = Double(i) / Double(count - 1)
            return (
                date: now.addingTimeInterval(-span + fraction * span),
                celsius: current.celsius - (1 - v) * 24
            )
        }
    }

    func fanSamples() -> [(date: Date, rpm: Double)] {
        let base = [0.18, 0.20, 0.24, 0.20, 0.42, 0.55, 0.35, 0.28, 0.32, 0.72, 0.88, 0.55, 0.40, 0.30]
        let shaped: [Double]
        switch level {
        case .cool: shaped = base.map { $0 * 0.35 }
        case .hot: shaped = base.map { min(1, $0 * 1.15 + 0.1) }
        case .warm: shaped = base
        }
        let now = Date()
        return shaped.enumerated().map { i, v in
            (
                date: now.addingTimeInterval(-24 * 3600 + Double(i) / Double(shaped.count - 1) * 24 * 3600),
                rpm: 1200 + v * 4200
            )
        }
    }

    // MARK: Throttle events (prototype table, as began/ended pairs)

    func events() -> [ThermalEventLog.Event] {
        // (days ago, hour, minute, duration min, peak °C, cause)
        let table: [(Double, Int, Int, Double, Double, String)] = [
            (0, 14, 14, 6, 97, "Xcode build · Chrome"),
            (0, 9, 41, 2, 92, "Final Cut export"),
            (2, 16, 8, 18, 99, "Docker build"),
            (3, 11, 20, 3, 93, "macOS update"),
            (4, 20, 52, 4, 91, "Photos analysis"),
        ]
        let calendar = Calendar.current
        var events: [ThermalEventLog.Event] = []
        for (daysAgo, hour, minute, duration, peak, cause) in table {
            guard let day = calendar.date(byAdding: .day, value: -Int(daysAgo), to: Date()),
                  let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            else { continue }
            events.append(ThermalEventLog.Event(
                id: UUID(), date: start, kind: .throttleBegan,
                subject: "Serious", celsius: peak, probableCause: cause
            ))
            events.append(ThermalEventLog.Event(
                id: UUID(), date: start.addingTimeInterval(duration * 60), kind: .throttleEnded,
                subject: "Nominal", celsius: nil, probableCause: nil
            ))
        }
        return events.sorted { $0.date < $1.date }
    }
}

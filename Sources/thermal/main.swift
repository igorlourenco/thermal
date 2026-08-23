import Foundation

// Usage:
//   swift run thermal            -> launches the MENU BAR APP
//   swift run thermal --demo hot -> app with prototype seed data (cool|warm|hot)
//   swift run thermal --cli      -> terminal dashboard snapshot
//   swift run thermal --watch    -> live terminal dashboard, 2s refresh
//   swift run thermal --raw      -> raw sensor list (debugging)
//   swift run thermal --watch --raw

let cliFlags = ["--cli", "--watch", "--raw"]
let isCLIMode = CommandLine.arguments.contains(where: cliFlags.contains)

if !isCLIMode {
    // No flags -> run as a menu bar app.
    TempBarApp.main()
    exit(0)
}

guard let hidReader = SensorReader() else {
    fputs("Failed to create IOHIDEventSystemClient. Are you on Apple Silicon macOS?\n", stderr)
    exit(1)
}

let smcReader = SMCReader()
if smcReader == nil {
    fputs("Note: could not open AppleSMC — continuing with HID sensors only.\n", stderr)
}

let history = HistoryStore()
let showRaw = CommandLine.arguments.contains("--raw")
let watchMode = CommandLine.arguments.contains("--watch")
// Warms up across --watch refreshes; a single snapshot stays on the
// per-snapshot placeholder heuristic.
let placeholderTracker = PlaceholderTracker()
func allReadings() -> [TemperatureReading] {
    var readings = hidReader.readAll()
    if let smc = smcReader {
        readings += smc.temperatures()
    }
    return readings
}

// MARK: - Formatting helpers

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func degrees(_ celsius: Double) -> String {
    "\(Int(celsius.rounded()))°"
}

let line = String(repeating: "─", count: 62)

// MARK: - Dashboard

func printDashboard() {
    let grouped = SensorLabeler.group(allReadings(), tracker: placeholderTracker)
    history.record(grouped)

    guard !grouped.isEmpty else {
        print("No temperature sensors found.")
        return
    }

    // --- Temperatures ---
    print(line)
    for row in grouped {
        let trend = history.trend(for: row.id).rawValue
        let peak = history.peak(for: row.id).map { "peak \(degrees($0))" } ?? ""
        print("  \(pad(row.group.displayName, 22))"
            + "\(pad(degrees(row.celsius), 6))"
            + "\(trend)   "
            + "\(pad(row.status.rawValue, 8))"
            + peak)
    }
    print(line)

    // --- Thermal pressure (the OS's own throttling signal) ---
    let pressure = ThermalPressure.current()
    let marker = pressure.isThrottling ? "⚠︎ " : ""
    print("  \(marker)Thermal pressure: \(pressure.label) — \(pressure.detail)")

    // --- Fans ---
    if let smc = smcReader {
        let fans = smc.fans()
        if fans.isEmpty {
            print("  Fans: none detected — this Mac cools silently.")
        } else {
            let parts = fans.map { fan -> String in
                var s = "\(Int(fan.rpm.rounded())) rpm"
                if let load = fan.load {
                    s += " (\(Int((load * 100).rounded()))%)"
                }
                return s
            }
            print("  Fans: " + parts.joined(separator: " · "))
        }
    }

    // --- Why: top heat sources ---
    let processes = ProcessMonitor.topProcesses(limit: 4)
    if !processes.isEmpty {
        let parts = processes.map { "\($0.name) \(Int($0.cpuPercent.rounded()))%" }
        print("  Top heat sources: " + parts.joined(separator: " · "))
    }

    // --- Summary sentence ---
    print(line)
    if pressure.isThrottling {
        print("  \(pressure.detail)")
    } else {
        print("  " + SensorLabeler.overallSummary(grouped))
    }
}

// MARK: - Raw mode (debugging / beta-tester diagnostics)

func printRawSnapshot() {
    let readings = SensorLabeler.deduplicate(allReadings())
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    if readings.isEmpty {
        print("No temperature sensors found.")
        return
    }

    print(String(repeating: "-", count: 60))
    for r in readings {
        let group = SensorLabeler.classify(r.name)
        print(String(
            format: "%-28s %6.1f °C   -> %@",
            (r.name as NSString).utf8String!,
            r.celsius,
            group.displayName
        ))
    }
    print(String(repeating: "-", count: 60))

    // What the app actually shows: the same readings after the full pipeline
    // (noise filter -> dedup -> placeholder walls dropped -> grouped).
    print("After pipeline (what the UI counts):")
    for row in SensorLabeler.group(allReadings(), tracker: placeholderTracker) {
        print(String(
            format: "  %-22s %3d sensors   hottest %5.1f °C",
            (row.group.displayName as NSString).utf8String!,
            row.sensors.count,
            row.celsius
        ))
    }
    print(String(repeating: "-", count: 60))
}

func printSnapshot() {
    showRaw ? printRawSnapshot() : printDashboard()
}

// MARK: - Run

if watchMode {
    while true {
        print("\u{001B}[2J\u{001B}[H", terminator: "") // clear screen
        printSnapshot()
        Thread.sleep(forTimeInterval: 2.0)
    }
} else {
    printSnapshot()
}
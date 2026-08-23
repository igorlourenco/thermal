import Foundation

// =============================================================================
// ThermalEventLog.swift
// Records *events* over time — the data behind "throttled 3× today" and
// chart annotations like "2:14 PM — Xcode (312%)".
//
// Two kinds of events:
//   .throttle — macOS thermal pressure changed (from the OS notification,
//               with a polling fallback since notifications can be missed).
//   .heat     — a sensor group entered Hot; annotated with the top process
//               at that moment, i.e. the probable cause.
//
// Persistence: JSON next to history.json, 7-day retention.
// =============================================================================

final class ThermalEventLog {

    struct Event: Codable, Identifiable {
        enum Kind: String, Codable {
            case throttleBegan
            case throttleEnded
            case groupRanHot
        }

        let id: UUID
        let date: Date
        let kind: Kind
        /// For throttle events: the pressure label ("Serious").
        /// For heat events: the group's displayName ("CPU – Performance").
        let subject: String
        /// Peak temperature for heat events.
        let celsius: Double?
        /// Top process at that moment — the probable cause. "Xcode (312%)"
        let probableCause: String?

        /// Ready-made annotation string for charts/history views.
        var annotation: String {
            switch kind {
            case .throttleBegan:
                return "macOS began throttling (\(subject))"
                    + (probableCause.map { " — \($0)" } ?? "")
            case .throttleEnded:
                return "Throttling ended"
            case .groupRanHot:
                let temp = celsius.map { " at \(Int($0.rounded()))°" } ?? ""
                return "\(subject) ran hot\(temp)"
                    + (probableCause.map { " — \($0)" } ?? "")
            }
        }
    }

    private(set) var events: [Event] = []

    private let retention: TimeInterval = 7 * 24 * 3600
    private var lastPressureLabel: String
    private var wasThrottling: Bool
    /// Groups currently in a Hot episode — so one episode logs one event.
    private var hotGroups: Set<String> = []
    private var observer: NSObjectProtocol?

    // MARK: Init / persistence

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("TempSensors", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.json")
    }

    init() {
        let pressure = ThermalPressure.current()
        lastPressureLabel = pressure.label
        wasThrottling = pressure.isThrottling

        load()

        // OS notification for thermal state changes (needs a run loop —
        // fine in the app; the polling fallback in check() covers the rest).
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkPressure(topProcess: nil)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func load() {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Event].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-retention)
        events = decoded.filter { $0.date >= cutoff }
    }

    func flush() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(events)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Recording — call check() once per refresh tick

    /// Inspect current pressure + grouped readings, log any transitions.
    /// `topProcesses` lets heat events carry their probable cause.
    func check(grouped: [GroupedReading], topProcesses: [HeatProcess]) {
        let cause = topProcesses.first.map {
            "\($0.name) (\(Int($0.cpuPercent.rounded()))%)"
        }

        checkPressure(topProcess: cause)
        checkHotGroups(grouped: grouped, cause: cause)
        prune()
    }

    private func checkPressure(topProcess: String?) {
        let pressure = ThermalPressure.current()
        defer {
            lastPressureLabel = pressure.label
            wasThrottling = pressure.isThrottling
        }

        if pressure.isThrottling, !wasThrottling {
            append(Event(
                id: UUID(), date: Date(), kind: .throttleBegan,
                subject: pressure.label, celsius: nil, probableCause: topProcess
            ))
        } else if !pressure.isThrottling, wasThrottling {
            append(Event(
                id: UUID(), date: Date(), kind: .throttleEnded,
                subject: pressure.label, celsius: nil, probableCause: nil
            ))
        }
    }

    private func checkHotGroups(grouped: [GroupedReading], cause: String?) {
        for row in grouped {
            if row.status == .hot {
                // Log once per episode, at its start.
                if !hotGroups.contains(row.id) {
                    hotGroups.insert(row.id)
                    append(Event(
                        id: UUID(), date: Date(), kind: .groupRanHot,
                        subject: row.group.displayName,
                        celsius: row.celsius,
                        probableCause: cause
                    ))
                }
            } else if row.status == .cool || row.status == .normal {
                // Episode over only once it's clearly cooled down
                // (skipping .warm gives hysteresis — no event spam
                // while hovering at the hot boundary).
                hotGroups.remove(row.id)
            }
        }
    }

    private func append(_ event: Event) {
        events.append(event)
        flush()   // events are rare; save immediately
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        if let firstValid = events.firstIndex(where: { $0.date >= cutoff }),
           firstValid > 0 {
            events.removeFirst(firstValid)
        }
    }

    // MARK: Queries

    /// Events within a window, newest first — feed for a history list.
    func recent(hoursBack: Double = 24) -> [Event] {
        let cutoff = Date().addingTimeInterval(-hoursBack * 3600)
        return events.filter { $0.date >= cutoff }.reversed()
    }

    /// "Throttled 3× today" -> throttleCount(hoursBack: 24)
    func throttleCount(hoursBack: Double = 24) -> Int {
        recent(hoursBack: hoursBack).filter { $0.kind == .throttleBegan }.count
    }

    /// Annotations for a chart's time range (oldest first).
    func annotations(from start: Date, to end: Date) -> [Event] {
        events.filter { $0.date >= start && $0.date <= end }
    }
}
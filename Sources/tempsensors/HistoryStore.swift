import Foundation

// =============================================================================
// HistoryStore.swift  (v2 — persistent)
// Two resolutions, one store:
//
//   FINE:    every reading as-is, in memory, last hour.
//            -> powers trend arrows and live sparklines.
//   MINUTE:  per-minute avg+max, persisted to disk, kept 7 days.
//            -> powers the multi-day history charts.
//
// Persistence: JSON in ~/Library/Application Support/TempSensors/history.json
// Saved at most once per minute and on demand (call flush() on app quit).
// API is a superset of v1 — record/peak/trend/history keep working.
// =============================================================================

final class HistoryStore {

    // MARK: Types

    struct Sample {
        let date: Date
        let celsius: Double
    }

    /// One minute of a group's readings, persisted.
    struct MinuteSample: Codable {
        let date: Date        // start of the minute
        let average: Double
        let max: Double
    }

    enum Trend: String {
        case rising  = "↑"
        case falling = "↓"
        case steady  = "→"
    }

    // MARK: State

    private var fine: [String: [Sample]] = [:]              // last hour, in memory
    private var minutes: [String: [MinuteSample]] = [:]     // 7 days, persisted

    /// Accumulator for the minute currently in progress.
    private var currentMinute: Date?
    private var accumulator: [String: (sum: Double, max: Double, count: Int)] = [:]

    private let fineMaxAge: TimeInterval = 3600
    private let minuteRetention: TimeInterval = 7 * 24 * 3600
    private let trendWindow: TimeInterval = 60
    private let trendThreshold: Double = 1.5

    private var lastSave: Date = .distantPast
    let sessionStart = Date()

    // MARK: Init / persistence

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("TempSensors", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    private func load() {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [MinuteSample]].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-minuteRetention)
        minutes = decoded.mapValues { list in list.filter { $0.date >= cutoff } }
    }

    /// Write minute-resolution history to disk. Called automatically about
    /// once a minute; call directly when the app is about to quit.
    func flush() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(minutes)
        else { return }
        try? data.write(to: url, options: .atomic)
        lastSave = Date()
    }

    // MARK: Recording

    /// Record the current grouped readings. Call once per refresh.
    func record(_ grouped: [GroupedReading]) {
        let now = Date()
        let minuteStart = Date(
            timeIntervalSinceReferenceDate:
                (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        )

        // Minute rolled over -> commit the accumulated minute.
        if let current = currentMinute, current != minuteStart {
            commitMinute(current)
        }
        currentMinute = minuteStart

        let fineCutoff = now.addingTimeInterval(-fineMaxAge)

        for row in grouped {
            // Fine samples.
            var list = fine[row.id, default: []]
            list.append(Sample(date: now, celsius: row.celsius))
            if let firstValid = list.firstIndex(where: { $0.date >= fineCutoff }),
               firstValid > 0 {
                list.removeFirst(firstValid)
            }
            fine[row.id] = list

            // Minute accumulator.
            var acc = accumulator[row.id] ?? (0, -.infinity, 0)
            acc.sum += row.celsius
            acc.max = Swift.max(acc.max, row.celsius)
            acc.count += 1
            accumulator[row.id] = acc
        }

        // Save at most once per minute.
        if now.timeIntervalSince(lastSave) >= 60 {
            flush()
        }
    }

    private func commitMinute(_ minuteStart: Date) {
        let cutoff = Date().addingTimeInterval(-minuteRetention)
        for (id, acc) in accumulator where acc.count > 0 {
            var list = minutes[id, default: []]
            list.append(MinuteSample(
                date: minuteStart,
                average: acc.sum / Double(acc.count),
                max: acc.max
            ))
            if let firstValid = list.firstIndex(where: { $0.date >= cutoff }),
               firstValid > 0 {
                list.removeFirst(firstValid)
            }
            minutes[id] = list
        }
        accumulator.removeAll(keepingCapacity: true)
    }

    // MARK: Queries

    /// Highest temperature seen this session for a group.
    func peak(for id: String) -> Double? {
        fine[id]?.map(\.celsius).max()
    }

    /// Direction of change over the last ~minute.
    func trend(for id: String) -> Trend {
        guard let list = fine[id], let latest = list.last else { return .steady }
        let target = latest.date.addingTimeInterval(-trendWindow)
        guard let reference = list.first(where: { $0.date >= target }),
              reference.date < latest.date
        else { return .steady }

        let delta = latest.celsius - reference.celsius
        if delta >= trendThreshold  { return .rising }
        if delta <= -trendThreshold { return .falling }
        return .steady
    }

    /// Fine-grained samples (last hour) — live sparkline fuel.
    func history(for id: String) -> [Sample] {
        fine[id] ?? []
    }

    /// Minute-resolution samples for charts. `hoursBack` up to 168 (7 days).
    /// Includes the minute in progress so charts reach "now".
    func minuteHistory(for id: String, hoursBack: Double = 24) -> [MinuteSample] {
        let cutoff = Date().addingTimeInterval(-hoursBack * 3600)
        var list = (minutes[id] ?? []).filter { $0.date >= cutoff }
        if let current = currentMinute, let acc = accumulator[id], acc.count > 0 {
            list.append(MinuteSample(
                date: current,
                average: acc.sum / Double(acc.count),
                max: acc.max
            ))
        }
        return list
    }

    /// True once enough persisted data exists to draw a meaningful chart.
    /// Use to switch the UI between an empty state and the real chart.
    func hasChartableHistory(for id: String, minimumMinutes: Int = 10) -> Bool {
        (minutes[id]?.count ?? 0) >= minimumMinutes
    }
}
import Foundation

// =============================================================================
// HistoryStore.swift
// Keeps a rolling window of readings per group: powers trend arrows,
// session peaks, and (later) the 24h charts in the app.
//
// In-memory for now — the CLI's history lasts one session. When we build the
// app, the same store gains a tiny JSON/SQLite persistence layer.
// =============================================================================

final class HistoryStore {

    struct Sample {
        let date: Date
        let celsius: Double
    }

    enum Trend: String {
        case rising  = "↑"
        case falling = "↓"
        case steady  = "→"
    }

    private var samples: [String: [Sample]] = [:]   // keyed by GroupedReading.id
    private let maxAge: TimeInterval = 24 * 3600

    /// How far back to look when deciding the trend, and how big a move counts.
    private let trendWindow: TimeInterval = 60
    private let trendThreshold: Double = 1.5

    /// Record the current grouped readings. Call once per refresh.
    func record(_ grouped: [GroupedReading]) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-maxAge)

        for row in grouped {
            var list = samples[row.id, default: []]
            list.append(Sample(date: now, celsius: row.celsius))
            // Prune anything older than 24h (cheap: list is chronological).
            if let firstValid = list.firstIndex(where: { $0.date >= cutoff }),
               firstValid > 0 {
                list.removeFirst(firstValid)
            }
            samples[row.id] = list
        }
    }

    /// Highest temperature seen this session for a group.
    func peak(for id: String) -> Double? {
        samples[id]?.map(\.celsius).max()
    }

    /// Direction of change over the last ~minute.
    func trend(for id: String) -> Trend {
        guard let list = samples[id], let latest = list.last else { return .steady }

        let target = latest.date.addingTimeInterval(-trendWindow)
        // Oldest sample that's still inside the window.
        guard let reference = list.first(where: { $0.date >= target }),
              reference.date < latest.date
        else { return .steady }

        let delta = latest.celsius - reference.celsius
        if delta >= trendThreshold  { return .rising }
        if delta <= -trendThreshold { return .falling }
        return .steady
    }

    /// Full sample list for a group (chronological) — chart fuel for the app.
    func history(for id: String) -> [Sample] {
        samples[id] ?? []
    }
}

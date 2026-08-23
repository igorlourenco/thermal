import Foundation

// =============================================================================
// NotificationGovernor.swift
// Decides WHEN the "sustained high" notification should fire (DESIGN §7).
// No visual output yet — the app is a bare SwiftPM executable, and a real
// UNUserNotificationCenter needs an app bundle. Everything here (sustained
// window, hysteresis, snooze, popover suppression) survives that migration;
// only `deliver` changes.
//
// Rules:
//   - Fires when the hottest reading stays >= threshold for 5 continuous
//     minutes. Never on spikes.
//   - One notification per episode: re-arms only after the reading falls
//     back below (threshold - 5°) — hysteresis, no flapping.
//   - Suppressed while the popover is open.
//   - "Snooze 1 hour" persists across launches.
// =============================================================================

final class NotificationGovernor {

    struct Payload {
        let celsius: Double
        let groupLabel: String
        let topProcesses: [String]
    }

    private let sustainWindow: TimeInterval = 5 * 60
    private let rearmMargin: Double = 5

    private var aboveSince: Date?
    private var firedThisEpisode = false

    private static let snoozeKey = "notificationSnoozeUntil"

    var snoozeUntil: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: Self.snoozeKey)
            return t > 0 ? Date(timeIntervalSinceReferenceDate: t) : nil
        }
        set {
            UserDefaults.standard.set(
                newValue?.timeIntervalSinceReferenceDate ?? 0, forKey: Self.snoozeKey
            )
        }
    }

    func snooze(hours: Double = 1) {
        snoozeUntil = Date().addingTimeInterval(hours * 3600)
    }

    /// Call once per refresh tick. Returns a payload when a notification
    /// should be delivered right now.
    func evaluate(
        hottest: GroupedReading?,
        thresholdC: Double,
        popoverOpen: Bool,
        topProcesses: [HeatProcess],
        now: Date = Date()
    ) -> Payload? {
        guard let hottest else {
            aboveSince = nil
            firedThisEpisode = false
            return nil
        }

        if hottest.celsius >= thresholdC {
            if aboveSince == nil { aboveSince = now }
        } else {
            // Any dip below the threshold resets the 5-minute sustain clock;
            // the episode itself re-arms only after cooling a further 5°.
            aboveSince = nil
            if hottest.celsius < thresholdC - rearmMargin {
                firedThisEpisode = false
            }
            return nil
        }

        guard let since = aboveSince,
              now.timeIntervalSince(since) >= sustainWindow,
              !firedThisEpisode,
              !popoverOpen,
              snoozeUntil.map({ now >= $0 }) ?? true
        else { return nil }

        firedThisEpisode = true
        return Payload(
            celsius: hottest.celsius,
            groupLabel: hottest.group.specLabel,
            topProcesses: topProcesses.prefix(2).map(\.name)
        )
    }

    /// Placeholder delivery until the app is bundled. Logged so the logic is
    /// observable in development.
    func deliver(_ payload: Payload) {
        let processes = payload.topProcesses.joined(separator: " and ")
        NSLog(
            "Thermal notification (suppressed, no bundle): sustained %d° — %@ driving the CPU.",
            Int(payload.celsius.rounded()),
            processes.isEmpty ? payload.groupLabel : processes
        )
    }
}

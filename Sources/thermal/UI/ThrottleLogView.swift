import SwiftUI

// =============================================================================
// ThrottleLogView.swift — the throttle event log (§4.6)
// Title, subtitle and the History link count all derive from the same
// episode list, so they can never disagree.
// =============================================================================

struct ThrottleLogView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel

    private var episodes: [ThermalModel.ThrottleEpisode] {
        model.throttleEpisodes(hoursBack: model.range.hours)
    }

    var body: some View {
        let episodes = episodes

        VStack(alignment: .leading, spacing: 0) {
            if episodes.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title(episodes))
                        .font(.system(size: 18, weight: .thin))
                        .foregroundStyle(theme.textStrong)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(episodes))
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(theme.textDim)
                }
                .padding(.horizontal, 20)
                .padding(.top, 15)
                .padding(.bottom, 13)

                episodeList(episodes)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
    }

    private func title(_ episodes: [ThermalModel.ThrottleEpisode]) -> String {
        let count = episodes.count
        let times = count == 1 ? "once" : (count == 2 ? "twice" : "\(spelledOut(count)) times")
        return "Your Mac slowed itself down \(times) \(model.range.periodWord)."
    }

    private func subtitle(_ episodes: [ThermalModel.ThrottleEpisode]) -> String {
        let totalMinutes = episodes.reduce(0.0) { total, episode in
            total + (episode.duration ?? Date().timeIntervalSince(episode.start)) / 60
        }
        let minutes = max(1, Int(totalMinutes.rounded()))
        return "\(minutes) minute\(minutes == 1 ? "" : "s") in total."
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Text("No throttling so far.")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(theme.textStrong)
            Text("When macOS slows your Mac down to cool it, the event lands here with what caused it.")
                .font(.system(size: 12))
                .lineSpacing(3.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textDim)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func episodeList(_ episodes: [ThermalModel.ThrottleEpisode]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                    episodeRow(episode, divider: index < episodes.count - 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .card()
    }

    private func episodeRow(_ episode: ThermalModel.ThrottleEpisode, divider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                RampDot(color: episode.peak.map(theme.ramp) ?? theme.textDim)
                Text(whenLabel(episode.start))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textStrong)
                Spacer()
                Text(episode.peak.map(model.fmt) ?? "—")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(episode.peak.map(theme.ramp) ?? theme.textDim)
            }

            HStack(spacing: 8) {
                Text(durationLabel(episode))
                if let cause = episode.cause {
                    Text("·")
                    Text(cause)
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(theme.textDim)
            .padding(.leading, 16)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle().fill(theme.rowBorder).frame(height: 1)
            }
        }
    }

    private func whenLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return "Today · \(formatter.string(from: date))"
        }
        if date > Date().addingTimeInterval(-6 * 24 * 3600) {
            formatter.dateFormat = "EEE · h:mm a"
            return formatter.string(from: date)
        }
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter.string(from: date)
    }

    private func durationLabel(_ episode: ThermalModel.ThrottleEpisode) -> String {
        guard let duration = episode.duration else { return "ongoing" }
        let minutes = max(1, Int((duration / 60).rounded()))
        return "\(minutes) min"
    }
}

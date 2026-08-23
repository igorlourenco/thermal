import SwiftUI

// =============================================================================
// FansView.swift — fan tiles, range and session sparkline (§4.7)
// Rail percentage and the idle/max row use each fan's real min/max RPM.
// Fan speed isn't persisted (temps are), so the sparkline covers this session.
// =============================================================================

struct FansView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel

    var body: some View {
        if model.fans.isEmpty {
            fanless
        } else {
            fansContent
        }
    }

    // MARK: Fanless hardware

    private var fanless: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No fans — your Mac cools silently.")
                .font(.system(size: 19, weight: .thin))
                .foregroundStyle(theme.textStrong)
            Text("The Air moves heat through its chassis. Under long loads it will slow itself down instead of getting louder.")
                .font(.system(size: 12.5))
                .lineSpacing(3.5)
                .foregroundStyle(theme.textMid)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Fans present

    private var fansContent: some View {
        let fans = Array(model.fans.prefix(2))
        let headlineColor = theme.ramp(model.hottest?.celsius ?? 0)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(Array(fans.enumerated()), id: \.offset) { index, fan in
                    fanTile(fan, index: index, count: fans.count, fill: headlineColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)

            rangeRow(fans)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            sparklineCard
                .padding(.horizontal, 14)
                .padding(.top, 16)

            Spacer(minLength: 0)

            Text(note)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textMid)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
    }

    private func fanTile(
        _ fan: SMCReader.Fan, index: Int, count: Int, fill: Color
    ) -> some View {
        let label = count == 2 ? (index == 0 ? "Left" : "Right") : "Fan \(index + 1)"
        let fraction = fan.load ?? min(1, fan.rpm / 5400)

        return VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .microcaps(9.5)
                .foregroundStyle(theme.textDim)

            Text(model.rpmString(fan.rpm))
                .font(.system(size: 26, weight: .thin))
                .monospacedDigit()
                .foregroundStyle(theme.textStrong)
                .padding(.top, 6)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.rail)
                    Capsule().fill(fill)
                        .frame(width: max(4, fraction * geo.size.width))
                }
            }
            .frame(height: 2)
            .padding(.top, 10)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 11)
    }

    @ViewBuilder
    private func rangeRow(_ fans: [SMCReader.Fan]) -> some View {
        if let minRPM = fans.compactMap(\.minRPM).min(),
           let maxRPM = fans.compactMap(\.maxRPM).max() {
            HStack {
                Text("Idle \(model.rpmString(minRPM))")
                Spacer()
                Text("Max \(model.rpmString(maxRPM))")
            }
            .microcaps(9.5)
            .monospacedDigit()
            .foregroundStyle(theme.textDim)
        }
    }

    private var sparklineCard: some View {
        let samples = model.fanSamples

        return VStack(alignment: .leading, spacing: 8) {
            Text("This session")
                .microcaps(9.5)
                .foregroundStyle(theme.textDim)

            if samples.count >= 2 {
                LineChart(
                    series: ChartSeries(celsius: samples.map(\.rpm)),
                    stroke: theme.neutralLine,
                    lineWidth: 1.2
                )
                .frame(height: 42)
            } else {
                Text("Collecting — the sparkline fills in as Thermal runs.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textDim)
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .card()
    }

    private var note: String {
        let load = model.fans.compactMap(\.load).max()
            ?? min(1, (model.fans.map(\.rpm).max() ?? 0) / 5400)
        if load >= 0.8 { return "Running near maximum. You can hear these." }
        if load >= 0.25 { return "Ramping up gently. You probably can't hear them yet." }
        return "Barely turning. Silent from here."
    }
}

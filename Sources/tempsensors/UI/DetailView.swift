import SwiftUI

// =============================================================================
// DetailView.swift — one sensor group in depth (§4.4)
// Headline + session peak, the group's explanation, a scrubbable 24h chart,
// and the raw monospaced sensor rows.
// =============================================================================

struct DetailView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel
    @State private var cursor: Int?

    private var samples: [(date: Date, celsius: Double)] {
        model.chartSamples(for: model.detailGroup, hoursBack: 24)
    }

    var body: some View {
        let reading = model.detailReading

        VStack(alignment: .leading, spacing: 0) {
            header(reading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Text(model.detailGroup.specExplanation)
                .font(.system(size: 12.5))
                .lineSpacing(3.5)
                .foregroundStyle(theme.textMid)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            chartCard
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            rawSensorsCard(reading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
    }

    // MARK: Headline row

    private func header(_ reading: GroupedReading?) -> some View {
        let celsius = reading?.celsius ?? 0

        return HStack(alignment: .bottom) {
            HStack(alignment: .top, spacing: 5) {
                Text(reading == nil ? "--" : model.num(celsius))
                    .font(.system(size: 58, weight: .thin))
                    .tracking(58 * -0.05)
                    .monospacedDigit()
                    .foregroundStyle(theme.textStrong)
                    .shadow(
                        color: reading == nil ? .clear : theme.ramp(celsius).opacity(0.55),
                        radius: 11, y: 2
                    )
                    .fixedSize()

                UnitChip(fontSize: 14)
                    .padding(.top, 8)
            }
            .frame(height: 54, alignment: .top)

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("Session peak")
                    .microcaps(9.5)
                    .foregroundStyle(theme.textDim)
                Text(model.sessionPeak(for: model.detailGroup).map(model.fmt) ?? "--")
                    .font(.system(size: 18, weight: .thin))
                    .monospacedDigit()
                    .foregroundStyle(theme.textMid)
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: Chart card

    private var chartCard: some View {
        let hasHistory = model.hasChartableHistory(for: model.detailGroup) && samples.count >= 2
        let series = ChartSeries(celsius: samples.map(\.celsius))
        let color = theme.ramp(model.detailReading?.celsius ?? 0)
        let scrubbing = cursor != nil

        return VStack(spacing: 8) {
            HStack {
                Text("24 hours")
                    .microcaps(9.5)
                    .foregroundStyle(theme.textDim)
                Spacer()
                Text(readout(hasHistory: hasHistory))
                    .microcaps(9.5)
                    .foregroundStyle(scrubbing ? theme.textStrong : theme.textDim)
                    .monospacedDigit()
            }

            if hasHistory {
                ScrubbableChart(series: series, stroke: color, cursor: $cursor)
                    .frame(height: 76)
            } else {
                Text("Not enough history yet.\nThis chart fills in over the first hour.")
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.textDim)
                    .frame(maxWidth: .infinity, minHeight: 76)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .card()
    }

    private func readout(hasHistory: Bool) -> String {
        guard hasHistory, !samples.isEmpty else { return "Collecting" }
        let index = min(max(cursor ?? samples.count - 1, 0), samples.count - 1)
        let sample = samples[index]
        return "\(Self.timeFormatter.string(from: sample.date)) · \(model.fmt(sample.celsius))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: Raw sensors card

    private func rawSensorsCard(_ reading: GroupedReading?) -> some View {
        let sensors = reading?.sensors ?? []

        return VStack(alignment: .leading, spacing: 0) {
            Text("Raw sensors")
                .microcaps(9.5, tracking: 0.2)
                .foregroundStyle(theme.textDim)
                .padding(.bottom, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.rowBorder).frame(height: 1)
                }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(sensors) { sensor in
                        HStack {
                            Text(sensor.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textDim)
                            Spacer()
                            Text(model.raw(sensor.celsius))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textMid)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .card(fill: theme.glassSoft)
    }
}

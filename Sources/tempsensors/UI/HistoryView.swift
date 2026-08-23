import SwiftUI

// =============================================================================
// HistoryView.swift — stacked multi-day charts (§4.5)
// 24h and 7d ranges draw from real persisted minute samples; 30d shows an
// honest empty state (the store keeps 7 days for now). Subtitles are derived
// from the data, never invented.
// =============================================================================

struct HistoryView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textMid)
                    .lineLimit(1)
                Spacer()
                SegmentedPills(
                    options: HistoryRange.allCases.map { ($0, $0.segmentLabel) },
                    selection: $model.range,
                    micro: true
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            content
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
    }

    // MARK: Data plumbing

    private var chartGroups: (primary: SensorGroup?, secondary: SensorGroup?, tertiary: SensorGroup?) {
        model.historyChartGroups
    }

    private func samples(_ group: SensorGroup?) -> [(date: Date, celsius: Double)] {
        guard let group else { return [] }
        return model.chartSamples(for: group, hoursBack: model.range.hours)
    }

    private var hasData: Bool {
        model.range != .month
            && chartGroups.primary.map { model.hasChartableHistory(for: $0) } == true
            && samples(chartGroups.primary).count >= 2
    }

    private var subtitle: String {
        guard hasData, let peak = samples(chartGroups.primary).map(\.celsius).max() else {
            return model.range == .month ? "Coming with more history." : "Collecting readings."
        }
        return "Peaked at \(model.fmt(peak)) \(model.range.periodWord)."
    }

    // MARK: Body switch

    @ViewBuilder
    private var content: some View {
        if model.range == .month {
            DashedPanel(
                title: "Not enough history for 30 days yet.",
                body_: "Thermal currently keeps a week of readings on this Mac. This view unlocks as retention grows."
            )
            .frame(maxHeight: .infinity)
        } else if !hasData {
            DashedPanel(
                title: "Nothing recorded yet.",
                body_: "Thermal keeps a week of readings on this Mac. The first charts appear after about an hour of use."
            )
            .frame(maxHeight: .infinity)
        } else {
            chartsCard
        }
    }

    // MARK: The stacked-chart card

    private var chartsCard: some View {
        let groups = chartGroups
        let annotations = annotationPair
        let episodeCount = model.throttleEpisodes(hoursBack: model.range.hours).count

        return VStack(alignment: .leading, spacing: 12) {
            if let primary = groups.primary {
                chart(
                    group: primary,
                    height: 60,
                    stroke: theme.ramp(current(primary) ?? 0),
                    dot: theme.ramp(current(primary) ?? 0),
                    metaPrefix: "peak",
                    annotation: annotations.0,
                    annotationColor: theme.annotation
                )
            }
            if let secondary = groups.secondary {
                chart(
                    group: secondary,
                    height: 48,
                    stroke: theme.neutralLine,
                    dot: theme.neutralDot,
                    metaPrefix: "peak",
                    annotation: annotations.1,
                    annotationColor: theme.textDim
                )
            }
            if let tertiary = groups.tertiary {
                chart(
                    group: tertiary,
                    height: 34,
                    stroke: theme.neutralLineSoft,
                    dot: nil,
                    metaPrefix: "now",
                    annotation: nil,
                    annotationColor: theme.textDim
                )
            }

            axisRow

            HStack {
                Text("\(episodeCount) throttle event\(episodeCount == 1 ? "" : "s") \(model.range.periodWord)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textMid)
                Spacer()
                Text("→").font(.system(size: 11.5)).foregroundStyle(theme.textDim)
            }
            .padding(.top, 4)
            .contentShape(Rectangle())
            .onTapGesture { model.screen = .events }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private func current(_ group: SensorGroup) -> Double? {
        model.grouped.first { $0.group == group }?.celsius
    }

    private func chart(
        group: SensorGroup,
        height: CGFloat,
        stroke: Color,
        dot: Color?,
        metaPrefix: String,
        annotation: (text: String, fraction: Double)?,
        annotationColor: Color
    ) -> some View {
        let data = samples(group)
        let series = ChartSeries(celsius: data.map(\.celsius))
        let meta: String = {
            if metaPrefix == "now" {
                return current(group).map { "now \(model.fmt($0))" } ?? ""
            }
            return data.map(\.celsius).max().map { "peak \(model.fmt($0))" } ?? ""
        }()

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(group.specLabel)
                    .microcaps(9.5)
                    .foregroundStyle(theme.textMid)
                Spacer()
                Text(meta)
                    .microcaps(9.5)
                    .monospacedDigit()
                    .foregroundStyle(theme.textDim)
            }

            LineChart(series: series, stroke: stroke, lineWidth: dot == nil ? 1.2 : 1.3, dot: dot)
                .frame(height: height)

            if let annotation {
                GeometryReader { geo in
                    Text(annotation.text)
                        .microcaps(9, tracking: 0.14)
                        .foregroundStyle(annotationColor)
                        .fixedSize()
                        .offset(x: min(annotation.fraction, 0.72) * geo.size.width)
                }
                .frame(height: 13)
            }
        }
    }

    // MARK: Annotations — real events placed at their time fraction

    private var annotationPair: ((text: String, fraction: Double)?, (text: String, fraction: Double)?) {
        let windowHours = model.range.hours
        let start = Date().addingTimeInterval(-windowHours * 3600)
        let events = model.annotationEvents(hoursBack: windowHours)
            .filter { $0.kind != .throttleEnded }
            .sorted { $0.date > $1.date }

        func annotate(_ event: ThermalEventLog.Event) -> (text: String, fraction: Double) {
            let fraction = event.date.timeIntervalSince(start) / (windowHours * 3600)
            return (text: "\(timeLabel(event.date)) · \(causeName(event))", fraction: max(0, fraction))
        }

        let first = events.first.map(annotate)
        let second = events.dropFirst().first.map(annotate)
        return (first, second)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch model.range {
        case .day: formatter.dateFormat = "h:mm a"
        case .week: formatter.dateFormat = "EEE"
        case .month: formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    private func causeName(_ event: ThermalEventLog.Event) -> String {
        if let cause = event.probableCause {
            return cause.components(separatedBy: " (").first ?? cause
        }
        return event.kind == .throttleBegan ? "Throttled" : event.subject
    }

    // MARK: Axis

    private var axisRow: some View {
        let labels = axisLabels
        return HStack {
            ForEach(labels.indices, id: \.self) { index in
                Text(labels[index])
                    .microcaps(9.5)
                    .foregroundStyle(theme.textDim)
                if index < labels.count - 1 { Spacer() }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.rowBorder).frame(height: 1)
        }
    }

    private var axisLabels: [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = model.range == .day ? "HH:mm" : "EEE"
        let span = model.range.hours * 3600
        let start = Date().addingTimeInterval(-span)
        let marks = [0.0, 0.25, 0.5, 0.75].map {
            formatter.string(from: start.addingTimeInterval($0 * span))
        }
        return marks + ["Now"]
    }
}

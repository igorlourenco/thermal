import SwiftUI

// =============================================================================
// Components.swift
// Small shared pieces: line charts, segmented pills, toggle, rail slider,
// stepper, ramp dot, unit chip, primary button, dashed empty panel.
// =============================================================================

// MARK: - Line chart

/// Normalized samples for a polyline. `v` is 0…1 (1 = highest in window).
struct ChartSeries {
    let values: [Double]

    init(celsius: [Double]) {
        guard let lo = celsius.min(), let hi = celsius.max(), hi - lo > 0.5 else {
            values = celsius.map { _ in 0.5 }
            return
        }
        values = celsius.map { ($0 - lo) / (hi - lo) }
    }

    var peakIndex: Int? {
        guard let maxValue = values.max() else { return nil }
        return values.firstIndex(of: maxValue)
    }

    /// Prototype poly(): y from 6 (v=1) down to height-4 (v=0).
    func point(_ i: Int, in size: CGSize) -> CGPoint {
        let n = max(values.count - 1, 1)
        return CGPoint(
            x: CGFloat(i) / CGFloat(n) * size.width,
            y: (size.height - 4) - values[i] * (size.height - 10)
        )
    }
}

struct LineChart: View {
    let series: ChartSeries
    let stroke: Color
    var lineWidth: CGFloat = 1.3
    var dot: Color?
    var dotRadius: CGFloat = 2.6

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Path { path in
                for i in series.values.indices {
                    let p = series.point(i, in: size)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
            }
            .stroke(stroke, lineWidth: lineWidth)

            if let dot, let peak = series.peakIndex {
                let p = series.point(peak, in: size)
                Circle()
                    .fill(dot)
                    .frame(width: dotRadius * 2, height: dotRadius * 2)
                    .position(p)
            }
        }
    }
}

/// Detail chart with hover scrubbing (§4.4): crosshair + dot follow the
/// pointer, leaving resets to the last sample.
struct ScrubbableChart: View {
    @Environment(\.theme) private var theme
    let series: ChartSeries
    let stroke: Color
    @Binding var cursor: Int?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let index = boundedCursor

            ZStack(alignment: .topLeading) {
                Path { path in
                    for i in series.values.indices {
                        let p = series.point(i, in: size)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                .stroke(stroke, lineWidth: 1.3)

                if let index {
                    let p = series.point(index, in: size)
                    Path { path in
                        path.move(to: CGPoint(x: p.x, y: 4))
                        path.addLine(to: CGPoint(x: p.x, y: size.height))
                    }
                    .stroke(theme.crosshair, lineWidth: 1)

                    Circle()
                        .fill(stroke)
                        .frame(width: 5.2, height: 5.2)
                        .position(p)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { hoverPhase in
                switch hoverPhase {
                case .active(let location):
                    guard series.values.count > 1 else { return }
                    let fraction = max(0, min(1, location.x / max(size.width, 1)))
                    cursor = Int((fraction * Double(series.values.count - 1)).rounded())
                case .ended:
                    cursor = nil
                }
            }
        }
    }

    private var boundedCursor: Int? {
        guard !series.values.isEmpty else { return nil }
        let last = series.values.count - 1
        return min(max(cursor ?? last, 0), last)
    }
}

// MARK: - Ramp dot

struct RampDot: View {
    let color: Color
    var glow = false
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: glow ? color.opacity(0.7) : .clear, radius: glow ? 4 : 0)
    }
}

// MARK: - Unit chip (Now 16pt / detail 14pt)

struct UnitChip: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel
    var fontSize: CGFloat = 16
    @State private var hovering = false

    var body: some View {
        Text(model.unitLabel)
            .font(.system(size: fontSize, weight: .light))
            .foregroundStyle(hovering ? theme.textStrong : theme.textDim)
            .padding(.horizontal, fontSize > 14 ? 6 : 5)
            .padding(.vertical, fontSize > 14 ? 3 : 2)
            .background(
                RoundedRectangle(cornerRadius: fontSize > 14 ? 6 : 5, style: .continuous)
                    .fill(theme.chipBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: fontSize > 14 ? 6 : 5, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1)
            )
            .onHover { hovering = $0 }
            .onTapGesture { model.useFahrenheit.toggle() }
    }
}

// MARK: - Segmented pills (Settings, History ranges)

struct SegmentedPills<T: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var micro = false   // History range style: 10pt uppercase tracked

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                Group {
                    if micro {
                        Text(option.label).microcaps(10, tracking: 0.1)
                    } else {
                        Text(option.label).font(.system(size: 11))
                    }
                }
                .foregroundStyle(selection == option.value ? theme.textStrong : theme.textDim)
                .padding(.horizontal, micro ? 9 : 11)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: micro ? 5 : 4, style: .continuous)
                        .fill(selection == option.value ? theme.hoverBg : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { selection = option.value }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: micro ? 7 : 6, style: .continuous)
                .fill(theme.chipBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: micro ? 7 : 6, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Toggle (38×22, 18pt knob)

struct GlassToggle: View {
    @Environment(\.theme) private var theme
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? theme.toggleOn : theme.rail)
                .frame(width: 38, height: 22)
            Circle()
                .fill(theme.knob)
                .frame(width: 18, height: 18)
                .padding(2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        }
    }
}

// MARK: - Rail slider (Refresh, 100×3, click anywhere)

struct RailSlider: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)

            ZStack(alignment: .leading) {
                Capsule().fill(theme.rail).frame(height: 3)
                Capsule().fill(theme.textMid).frame(width: fraction * width, height: 3)
                Circle()
                    .fill(theme.knob)
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                    .offset(x: fraction * width - 6.5)
            }
            .frame(height: 13)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let f = max(0, min(1, gesture.location.x / width))
                        value = (range.lowerBound + f * (range.upperBound - range.lowerBound)).rounded()
                    }
            )
        }
        .frame(width: 100, height: 13)
    }
}

// MARK: - Stepper (− 90° +)

struct ChipStepper: View {
    @Environment(\.theme) private var theme
    let label: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            stepButton("−", action: onDecrement)
            Text(label)
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(theme.textStrong)
                .frame(minWidth: 34)
            stepButton("+", action: onIncrement)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.chipBg))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Text(symbol)
            .font(.system(size: 13))
            .foregroundStyle(theme.textMid)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .hoverFill()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onTapGesture(perform: action)
    }
}

// MARK: - Primary button (onboarding, failure)

struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(title)
            .microcaps(11, tracking: 0.12)
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.primaryBg))
            .opacity(hovering ? 0.85 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

struct GhostButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(title)
            .microcaps(11, tracking: 0.12)
            .foregroundStyle(hovering ? theme.textMid : theme.textDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

// MARK: - Dashed empty panel (§4.2 empty, §6 no history)

struct DashedPanel: View {
    @Environment(\.theme) private var theme
    let title: String
    let body_: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(theme.textStrong)
                .multilineTextAlignment(.center)
            Text(body_)
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .foregroundStyle(theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.glassSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

import SwiftUI
import AppKit

// =============================================================================
// ZenView.swift — the 660×420 ambient window (§4.9)
// Same tokens, more air. Meant to be left open on a second display.
// =============================================================================

struct ZenView: View {
    @EnvironmentObject var model: ThermalModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme

    private var theme: Theme {
        Theme(appearance: model.appearance.resolved(systemIsDark: systemScheme == .dark))
    }

    var body: some View {
        let theme = theme
        let hottest = model.hottest
        let celsius = hottest?.celsius

        ZStack {
            SubstrateBackground(
                hot: model.headlineBand == .hot && !model.blind,
                warmBloomCelsius: model.blind ? nil : celsius,
                coolBloomCelsius: model.blind ? nil : coolestCelsius,
                warmBloomSize: CGSize(width: 560, height: 420),
                coolBloomSize: CGSize(width: 480, height: 360),
                warmBlur: 46,
                coolBlur: 48
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Thermal · Zen")
                        .microcaps(9.5, tracking: 0.3)
                        .foregroundStyle(theme.textDim)
                    Spacer()
                    ExitLabel { dismiss() }
                }

                Spacer()

                HStack(alignment: .center, spacing: 48) {
                    // Three digits (Fahrenheit) at full size crowd the right
                    // column — scale the number down so the layout holds.
                    let numberText = model.blind ? "--" : model.num(celsius ?? 0)
                    let numberSize: CGFloat = numberText.count >= 3 ? 112 : 148

                    HStack(alignment: .top, spacing: 8) {
                        Text(numberText)
                            .font(.system(size: numberSize, weight: .ultraLight))
                            .tracking(numberSize * -0.055)
                            .monospacedDigit()
                            .foregroundStyle(theme.textStrong)
                            .shadow(
                                color: model.blind ? .clear : theme.ramp(celsius ?? 0).opacity(0.5),
                                radius: 25, y: 4
                            )
                            .fixedSize()

                        ZenUnitToggle()
                            .padding(.top, 16)
                    }

                    VStack(alignment: .leading, spacing: 22) {
                        Text(model.sentence)
                            .font(.system(size: 18, weight: .thin))
                            .lineSpacing(7)
                            .foregroundStyle(theme.textMid)
                            .fixedSize(horizontal: false, vertical: true)

                        zenCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 38)
        }
        .frame(width: 660, height: 420)
        .environment(\.theme, theme)
        .environmentObject(model)
        .preferredColorScheme({
            switch model.appearance {
            case .system: return nil
            case .dark: return .dark
            case .light: return .light
            }
        }())
        .background(WindowChrome())
    }

    private var coolestCelsius: Double? {
        model.grouped.map(\.celsius).min()
    }

    /// Efficiency cores, GPU, memory (§4.9), padded from whatever exists.
    private var zenGroups: [GroupedReading] {
        let byGroup = Dictionary(uniqueKeysWithValues: model.grouped.map { ($0.group, $0) })
        var rows = [SensorGroup.cpuEfficiency, .gpu, .memory].compactMap { byGroup[$0] }
        if rows.count < 3 {
            for row in model.allGroups where !rows.contains(where: { $0.group == row.group }) {
                rows.append(row)
                if rows.count >= 3 { break }
            }
        }
        return Array(rows.prefix(3))
    }

    private var zenCard: some View {
        let theme = theme
        let rows = zenGroups

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 10) {
                    RampDot(color: theme.ramp(row.celsius), size: 5)
                    Text(row.group.specLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textMid)
                    Spacer()
                    Text(model.fmt(row.celsius))
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.textStrong)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 {
                        Rectangle().fill(theme.rowBorder).frame(height: 1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 14)
        .card()
    }
}

private struct ZenUnitToggle: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel
    @State private var hovering = false

    var body: some View {
        Text(model.unitLabel)
            .font(.system(size: 24, weight: .thin))
            .foregroundStyle(hovering ? theme.textMid : theme.textDim)
            .fixedSize()
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { model.useFahrenheit.toggle() }
    }
}

private struct ExitLabel: View {
    @Environment(\.theme) private var theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text("Exit")
            .microcaps(9.5, tracking: 0.3)
            .foregroundStyle(theme.textDim)
            .opacity(hovering ? 0.6 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

/// Hides the traffic lights and title bar of the hosting window so Zen reads
/// as a plain ambient panel.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

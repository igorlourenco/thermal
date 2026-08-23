import SwiftUI
import AppKit

// =============================================================================
// SettingsView.swift — one card, the §4.8 rows
// =============================================================================

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel
    @State private var styleMenuOpen = false

    var body: some View {
        VStack(spacing: 0) {
            settingsCard
                .padding(.horizontal, 14)
                .padding(.top, 14)

            Spacer(minLength: 0)

            footerRow
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            row(divider: true) {
                rowLabel("Units")
                SegmentedPills(
                    options: [(false, "°C"), (true, "°F")],
                    selection: $model.useFahrenheit
                )
            }

            row(divider: true) {
                rowLabel("Appearance")
                SegmentedPills(
                    options: [
                        (Appearance.system, "circle.lefthalf.filled"),
                        (Appearance.light, "sun.max"),
                        (Appearance.dark, "moon"),
                    ],
                    selection: $model.appearance,
                    icons: true
                )
                .help("System · Light · Dark")
            }

            row(divider: true) {
                rowLabel("Menu bar style")
                styleDropdownButton
            }
            .overlay(alignment: .topTrailing) {
                if styleMenuOpen {
                    styleDropdownPanel
                        .offset(y: 38)
                        .zIndex(10)
                }
            }
            .zIndex(styleMenuOpen ? 10 : 0)

            row(divider: true) {
                rowLabel("Refresh")
                HStack(spacing: 12) {
                    RailSlider(value: $model.refreshInterval, range: 1...10)
                    Text("\(Int(model.refreshInterval)) s")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(theme.textMid)
                        .frame(width: 30, alignment: .leading)
                }
            }

            row(divider: true) {
                rowLabel("Launch at login")
                GlassToggle(isOn: $model.launchAtLogin)
            }

            row(divider: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notify above")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textStrong)
                    Text("Only for sustained highs, never for spikes")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ChipStepper(
                    label: model.fmt(model.notifyThresholdC),
                    onDecrement: { model.notifyThresholdC = max(60, model.notifyThresholdC - 1) },
                    onIncrement: { model.notifyThresholdC = min(100, model.notifyThresholdC + 1) }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .card()
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(theme.textStrong)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row<Content: View>(
        divider: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 14, content: content)
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) {
                if divider {
                    Rectangle().fill(theme.rowBorder).frame(height: 1)
                }
            }
    }

    // MARK: Menu bar style dropdown

    private var styleDropdownButton: some View {
        StyleDropdownButton(label: model.menuBarStyle.label) {
            withAnimation(.easeOut(duration: 0.12)) { styleMenuOpen.toggle() }
        }
    }

    private var styleDropdownPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(MenuBarStyle.allCases.enumerated()), id: \.element) { index, style in
                let active = model.menuBarStyle == style
                HStack(spacing: 8) {
                    Text(style.label)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textStrong)
                    Spacer()
                    if active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.textDim)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 11)
                .background(active ? theme.hoverBg : .clear)
                .contentShape(Rectangle())
                .hoverFill()
                .onTapGesture {
                    model.menuBarStyle = style
                    styleMenuOpen = false
                }
                .overlay(alignment: .bottom) {
                    if index < MenuBarStyle.allCases.count - 1 {
                        Rectangle().fill(theme.rowBorder).frame(height: 1)
                    }
                }
            }
        }
        .frame(width: 184)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.menuPanel))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 15, y: 12)
    }

    // MARK: Footer row

    private var footerRow: some View {
        HStack {
            FooterLink(title: "Sensor service · reconnect") { model.connect() }
            Spacer()
            FooterLink(title: "Replay setup") { model.replaySetup() }
        }
    }
}

private struct StyleDropdownButton: View {
    @Environment(\.theme) private var theme
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 12))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .opacity(0.7)
        }
        .foregroundStyle(hovering ? theme.textStrong : theme.textMid)
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.chipBg))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

private struct FooterLink: View {
    @Environment(\.theme) private var theme
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(hovering ? theme.textMid : theme.textDim)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

import SwiftUI

// =============================================================================
// OnboardingView.swift — first run (§5, adapted), connecting and failure (§6)
// Two steps: welcome → menu bar style. There is no real macOS permission for
// these sensors, so no consent theater — readers init silently during the
// welcome step, and step two shows a live reading as proof of life.
// =============================================================================

struct OnboardingView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if step == 0 {
                    welcome
                } else {
                    styleChooser
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            bottomBar
                .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    // MARK: Step 0 — welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            appTile(size: 46, radius: 13)

            Spacer(minLength: 0)

            Text("Thermal")
                .font(.system(size: 26, weight: .thin))
                .tracking(26 * -0.02)
                .foregroundStyle(theme.textStrong)

            Text("Your Mac measures its own temperature in about forty places. Thermal reads those numbers and tells you what they mean.")
                .font(.system(size: 13.5))
                .lineSpacing(4.5)
                .foregroundStyle(theme.textMid)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    // MARK: Step 1 — menu bar style, with a live reading

    private var styleChooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How it should look up there")
                .font(.system(size: 21, weight: .thin))
                .foregroundStyle(theme.textStrong)

            Text("You can change this any time in Settings.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textMid)
                .padding(.top, 9)

            VStack(spacing: 8) {
                ForEach(MenuBarStyle.allCases, id: \.self) { style in
                    styleCard(style)
                }
            }
            .padding(.top, 16)
        }
    }

    private func styleCard(_ style: MenuBarStyle) -> some View {
        let selected = model.menuBarStyle == style

        return HStack(spacing: 12) {
            MenuBarItemPreview(style: style)
                .frame(width: 74, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.menubar))

            VStack(alignment: .leading, spacing: 2) {
                Text(style.label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textStrong)
                Text(style.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textDim)
            }

            Spacer()
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? theme.hoverBg : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? theme.textDim : theme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.menuBarStyle = style }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            PrimaryButton(title: step == 0 ? "Continue" : "Start Thermal") {
                model.advanceOnboarding()
            }

            Spacer()

            HStack(spacing: 5) {
                ForEach(0..<2, id: \.self) { dot in
                    Circle()
                        .fill(dot == step ? theme.textStrong : theme.rail)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private func appTile(size: CGFloat, radius: CGFloat) -> some View {
        let color = model.blind || model.hottest == nil
            ? theme.hairline
            : theme.ramp(model.hottest!.celsius)

        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.8), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(color, lineWidth: 1)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Live menu bar item preview (onboarding cards; mirrors the real item)

struct MenuBarItemPreview: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel
    let style: MenuBarStyle

    var body: some View {
        let celsius = model.hottest?.celsius

        HStack(spacing: 5) {
            if style != .number {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                celsius.map { theme.ramp($0) } ?? .clear,
                                .clear,
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(
                                celsius.map { theme.ramp($0) } ?? theme.hairline,
                                lineWidth: 1
                            )
                    )
                    .frame(width: 11, height: 11)
            }
            if style != .chip {
                Text(celsius.map(model.fmt) ?? "--")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(theme.menuText)
            }
        }
    }
}

// MARK: - Connecting (§6)

struct ConnectingView: View {
    @Environment(\.theme) private var theme
    @State private var animating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(theme.textMid)
                        .frame(width: 7, height: 7)
                        .opacity(animating ? 0.9 : 0.25)
                        .animation(
                            .easeInOut(duration: 0.65)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.18),
                            value: animating
                        )
                }
            }
            .padding(.bottom, 20)

            Text("Reading sensors…")
                .font(.system(size: 19, weight: .thin))
                .foregroundStyle(theme.textStrong)

            Text("First readings take a few seconds. Thermal is finding out which sensors your Mac has.")
                .font(.system(size: 12.5))
                .lineSpacing(4)
                .foregroundStyle(theme.textMid)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { animating = true }
    }
}

// MARK: - Failure — zero sensors readable (§6 sensor error, honest copy)

struct FailureView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.glassSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
                    .frame(width: 44, height: 44)
                    .padding(.bottom, 16)

                Text("We can't read the sensors right now.")
                    .font(.system(size: 18, weight: .thin))
                    .foregroundStyle(theme.textStrong)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Nothing is wrong with your Mac — Thermal couldn't reach its sensor sources. This can happen on unsupported machines or when the app is sandboxed.")
                    .font(.system(size: 12.5))
                    .lineSpacing(4)
                    .foregroundStyle(theme.textMid)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                TryAgainButton { model.retryReaders() }
                GhostButton(title: "Quit Thermal") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
    }
}

private struct TryAgainButton: View {
    @Environment(\.theme) private var theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text("Try again")
            .microcaps(10, tracking: 0.1)
            .foregroundStyle(theme.textStrong)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? theme.hoverBg : theme.chipBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

import SwiftUI

// =============================================================================
// NowView.swift — the default screen (§4.1)
// =============================================================================

struct NowView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            if model.isThrottling {
                throttleBanner
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            sensorList
                .padding(.horizontal, 14)

            Spacer(minLength: 0)

            footerPair
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
    }

    // MARK: Headline — 72pt, weight 200, ramp glow

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                let celsius = model.hottest?.celsius
                Text(model.blind ? "--" : model.num(celsius ?? 0))
                    .font(.system(size: 72, weight: .thin))
                    .tracking(72 * -0.05)
                    .monospacedDigit()
                    .foregroundStyle(theme.textStrong)
                    .shadow(
                        color: model.blind ? .clear : theme.ramp(celsius ?? 0).opacity(0.55),
                        radius: 12, y: 2
                    )
                    .lineLimit(1)
                    .fixedSize()

                UnitChip(fontSize: 16)
                    .padding(.top, 10)
            }
            .frame(height: 66, alignment: .top)

            // Locked to two lines' height so the layout doesn't jump when the
            // sentence changes length with the temperature.
            Text(model.sentence)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(theme.textMid)
                .lineLimit(2)
                .frame(height: 40, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
    }

    // MARK: Throttle banner (hot only)

    private var throttleBanner: some View {
        let hotColor = theme.ramp(95)
        return HStack(spacing: 10) {
            RampDot(color: hotColor, glow: true)
            Text("macOS is slowing things down to stay cool.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textStrong)
            Spacer()
            Text("→").font(.system(size: 12)).foregroundStyle(theme.textDim)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hotColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(hotColor.opacity(0.42), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { model.navigate(to: .events) }
    }

    // MARK: Sensor list — one card, six rows

    private var sensorList: some View {
        let rows = model.nowGroups
        let hottestGroup = model.hottest?.group

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let isHottest = row.group == hottestGroup
                HStack(spacing: 10) {
                    RampDot(
                        color: model.blind ? theme.textDim : theme.ramp(row.celsius),
                        glow: isHottest && !model.blind
                    )
                    Text(row.group.specLabel)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isHottest ? theme.textStrong : theme.textMid)
                    Spacer()
                    Text(model.blind ? "--" : model.fmt(row.celsius))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(isHottest ? theme.textStrong : theme.textMid)
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
                .hoverFill()
                .onTapGesture { model.openDetail(row.group) }
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 {
                        Rectangle().fill(theme.rowBorder).frame(height: 1)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .card()
    }

    // MARK: Footer pair

    private var footerPair: some View {
        HStack(spacing: 8) {
            footerButton(
                label: model.headlineBand == .cool ? "What is running?" : "Why is it hot?",
                flexible: true
            ) { model.navigate(to: .why) }

            footerButton(label: "All sensors", flexible: false) { model.navigate(to: .sensors) }
        }
    }

    private func footerButton(
        label: String, flexible: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(theme.textMid)
            if flexible { Spacer() }
            Text("→").font(.system(size: 12)).foregroundStyle(theme.textDim)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: flexible ? .infinity : nil)
        .contentShape(Rectangle())
        .hoverFill()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .card(radius: 10, fill: theme.glassSoft, inset: false)
        .onTapGesture(perform: action)
    }
}

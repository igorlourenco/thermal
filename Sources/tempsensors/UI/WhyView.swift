import SwiftUI
import AppKit

// =============================================================================
// WhyView.swift — "Why is it hot" (§4.2)
// Real processes only. The prototype's activity notes ("38 TABS") are
// deliberately absent — we can't know that, so we don't pretend to.
// =============================================================================

struct WhyView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel

    /// Only processes doing real work qualify (§4.2 empty state: "No process
    /// is using more than 5% of the CPU.")
    private var busyProcesses: [HeatProcess] {
        model.processes.filter { $0.cpuPercent >= 5 }
    }

    var body: some View {
        let processes = busyProcesses

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title(count: processes.count))
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(theme.textStrong)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle(count: processes.count))
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundStyle(theme.textDim)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)

            if processes.isEmpty {
                DashedPanel(
                    title: "Nothing is working hard.",
                    body_: "No process is using more than 5% of the CPU. Any warmth you see now is left over heat."
                )
                .padding(.horizontal, 14)
            } else {
                processCard(processes)
                    .padding(.horizontal, 14)
            }

            Spacer(minLength: 0)

            Text(footerLine(count: processes.count))
                .font(.system(size: 11))
                .foregroundStyle(theme.textDim)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }

    private func title(count: Int) -> String {
        switch count {
        case 0: return "Nothing is driving the CPU."
        case 1: return "One app is keeping the CPU busy."
        default: return "\(spelledOut(count).capitalized) apps are keeping the CPU busy."
        }
    }

    private func subtitle(count: Int) -> String {
        count == 0
            ? "Temperatures should keep falling for the next few minutes."
            : "Quitting the top one usually drops 10–15° within a minute."
    }

    private func footerLine(count: Int) -> String {
        guard count > 0 else { return "Nothing heavy is running now." }
        let seconds = max(0, Int(Date().timeIntervalSince(model.lastRefresh).rounded()))
        switch seconds {
        case 0: return "Updated just now"
        case 1: return "Updated 1 second ago"
        default: return "Updated \(seconds) seconds ago"
        }
    }

    private func processCard(_ processes: [HeatProcess]) -> some View {
        let headlineColor = theme.ramp(model.hottest?.celsius ?? 0)

        return VStack(spacing: 0) {
            ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                HStack(spacing: 11) {
                    appIcon(for: process)

                    Text(process.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.textStrong)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int(process.cpuPercent.rounded()))%")
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(index < 2 ? headlineColor : theme.textMid)

                    quitChip(process)
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 13)
                .overlay(alignment: .bottom) {
                    if index < processes.count - 1 {
                        Rectangle().fill(theme.rowBorder).frame(height: 1)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .card()
    }

    @ViewBuilder
    private func appIcon(for process: HeatProcess) -> some View {
        if process.pid > 0,
           let icon = NSRunningApplication(processIdentifier: process.pid)?.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.chipBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
                .frame(width: 22, height: 22)
        }
    }

    private func quitChip(_ process: HeatProcess) -> some View {
        QuitChip { model.quitProcess(process) }
    }
}

private struct QuitChip: View {
    @Environment(\.theme) private var theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text("Quit")
            .microcaps(10, tracking: 0.1)
            .foregroundStyle(hovering ? theme.textStrong : theme.textMid)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.chipBg))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

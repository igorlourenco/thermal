import SwiftUI
import AppKit

// =============================================================================
// MenuBarApp.swift
// The menu bar app shell. Launched when the executable runs with no CLI flags
// (see main.swift). Deliberately restrained visually — a functional base that
// the chosen Claude Design direction will be applied to.
// =============================================================================

struct TempBarApp: App {

    @StateObject private var model = TempModel()

    init() {
        // Menu bar app: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(model)
        } label: {
            Text(model.menuBarLabel)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Model

@MainActor
final class TempModel: ObservableObject {

    @Published var grouped: [GroupedReading] = []
    @Published var pressure: ThermalPressure.State = ThermalPressure.current()
    @Published var fans: [SMCReader.Fan] = []
    @Published var processes: [HeatProcess] = []

    @AppStorage("useFahrenheit") var useFahrenheit = false

    let history = HistoryStore()

    private let hid = SensorReader()
    private let smc = SMCReader()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        var readings = hid?.readAll() ?? []
        if let smc { readings += smc.temperatures() }

        let newGrouped = SensorLabeler.group(readings)
        history.record(newGrouped)

        grouped = newGrouped
        pressure = ThermalPressure.current()
        fans = smc?.fans() ?? []
        processes = ProcessMonitor.topProcesses(limit: 4)
    }

    // MARK: Derived

    /// The number shown in the menu bar: the hottest group right now.
    var menuBarLabel: String {
        guard let hottest = grouped.max(by: { $0.celsius < $1.celsius }) else {
            return "––°"
        }
        return format(hottest.celsius)
    }

    var summary: String {
        pressure.isThrottling ? pressure.detail : SensorLabeler.overallSummary(grouped)
    }

    /// °C/°F formatting, one place only.
    func format(_ celsius: Double) -> String {
        let value = useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    var unitLabel: String { useFahrenheit ? "°F" : "°C" }

    func quitProcess(_ process: HeatProcess) {
        kill(process.pid, SIGTERM)
        // Refresh shortly after so the list reflects reality.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refresh()
        }
    }
}

// MARK: - Status color (the only saturated color in the UI)

extension ThermalStatus {
    var color: Color {
        switch self {
        case .cool:   return Color(nsColor: .tertiaryLabelColor)
        case .normal: return Color(nsColor: .secondaryLabelColor)
        case .warm:   return .orange
        case .hot:    return .red
        }
    }
}

// MARK: - Views

struct DashboardView: View {
    @EnvironmentObject var model: TempModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // --- Header: summary sentence + unit toggle ---
            HStack(alignment: .firstTextBaseline) {
                Text(model.summary)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Button(model.unitLabel) {
                    model.useFahrenheit.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .help("Switch temperature unit")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // --- Throttling banner (only when it matters) ---
            if model.pressure.isThrottling {
                Label(model.pressure.detail, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            Divider()

            // --- Grouped readings ---
            VStack(spacing: 2) {
                ForEach(model.grouped) { row in
                    GroupRowView(row: row)
                }
            }
            .padding(.vertical, 6)

            Divider()

            // --- Fans ---
            FansLineView()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            // --- Top heat sources ---
            if !model.processes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top heat sources")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(model.processes) { process in
                        ProcessRowView(process: process)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            Divider()

            // --- Footer ---
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }
}

struct GroupRowView: View {
    @EnvironmentObject var model: TempModel
    let row: GroupedReading

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.group.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(row.group.displayName)
                .font(.system(.body))
                .foregroundStyle(.primary)

            Spacer()

            // Session peak, quietly.
            if let peak = model.history.peak(for: row.id),
               peak > row.celsius + 0.5 {
                Text("peak \(model.format(peak))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(model.history.trend(for: row.id).rawValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(model.format(row.celsius))
                .font(.system(.body, design: .monospaced, weight: .medium))
                .foregroundStyle(row.status == .warm || row.status == .hot
                                 ? row.status.color
                                 : .primary)
                .frame(minWidth: 40, alignment: .trailing)

            Circle()
                .fill(row.status.color)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .help(row.group.explanation)
    }
}

struct FansLineView: View {
    @EnvironmentObject var model: TempModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "fan")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if model.fans.isEmpty {
                Text("No fans — this Mac cools silently.")
            } else if model.fans.allSatisfy({ $0.rpm < 1 }) {
                Text("Fans off — cooling passively.")
            } else {
                Text(model.fans
                    .map { fan in
                        var s = "\(Int(fan.rpm.rounded())) rpm"
                        if let load = fan.load {
                            s += " (\(Int((load * 100).rounded()))%)"
                        }
                        return s
                    }
                    .joined(separator: " · "))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ProcessRowView: View {
    @EnvironmentObject var model: TempModel
    let process: HeatProcess
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(process.name)
                .font(.system(.caption))
                .lineLimit(1)
            Spacer()
            Text("\(Int(process.cpuPercent.rounded()))%")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Button {
                model.quitProcess(process)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Quit \(process.name)")
        }
        .onHover { hovering = $0 }
    }
}
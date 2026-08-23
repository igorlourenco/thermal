import SwiftUI
import IOKit
import ServiceManagement

// =============================================================================
// ThermalModel.swift
// One observable model behind every screen. Owns the readers, the refresh
// loop, persisted settings (DESIGN §9), navigation state, and the derived
// values the views render. Demo seed data only enters through `demo`.
// =============================================================================

enum Screen: Equatable {
    case now, why, sensors, detail, history, events, fans, settings
}

enum Phase: Equatable {
    case onboarding(step: Int)   // 0 welcome · 1 menu bar style
    case connecting
    case ready
    case failure                 // zero sensors readable
}

enum MenuBarStyle: String, CaseIterable {
    case both, number, chip

    var label: String {
        switch self {
        case .both: return "Chip + number"
        case .number: return "Number only"
        case .chip: return "Chip only"
        }
    }

    var note: String {
        switch self {
        case .both: return "Colour and reading"
        case .number: return "Quietest option"
        case .chip: return "Colour at a glance"
        }
    }
}

enum HistoryRange: String, CaseIterable {
    case day, week, month

    var segmentLabel: String {
        switch self {
        case .day: return "24h"
        case .week: return "7d"
        case .month: return "30d"
        }
    }

    var headerWord: String {
        switch self {
        case .day: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        }
    }

    var eventsHeaderWord: String {
        switch self {
        case .day: return "Today"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        }
    }

    var periodWord: String {
        switch self {
        case .day: return "today"
        case .week: return "this week"
        case .month: return "this month"
        }
    }

    var hours: Double {
        switch self {
        case .day: return 24
        case .week: return 7 * 24
        case .month: return 30 * 24
        }
    }
}

@MainActor
final class ThermalModel: ObservableObject {

    // MARK: Navigation (ephemeral, §9)

    @Published var phase: Phase
    @Published var screen: Screen = .now
    @Published var detailGroup: SensorGroup = .cpuPerformance
    @Published var range: HistoryRange = .day
    @Published var query = ""
    @Published var popoverVisible = false

    // MARK: Live data

    @Published private(set) var grouped: [GroupedReading] = []
    @Published private(set) var pressure = ThermalPressure.current()
    @Published private(set) var fans: [SMCReader.Fan] = []
    @Published private(set) var processes: [HeatProcess] = []
    @Published private(set) var lastRefresh = Date()

    // MARK: Persisted settings (§9)

    @Published var useFahrenheit: Bool { didSet { defaults.set(useFahrenheit, forKey: "useFahrenheit") } }
    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    @Published var refreshInterval: Double {
        didSet {
            defaults.set(refreshInterval, forKey: "refreshInterval")
            scheduleTimer()
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            applyLaunchAtLogin()
        }
    }
    @Published var notifyThresholdC: Double { didSet { defaults.set(notifyThresholdC, forKey: "notifyThresholdC") } }

    private(set) var hasCompletedFirstRun: Bool {
        get { defaults.bool(forKey: "hasCompletedFirstRun") }
        set { defaults.set(newValue, forKey: "hasCompletedFirstRun") }
    }

    // MARK: Internals

    let history = HistoryStore()
    let eventLog = ThermalEventLog()
    let governor = NotificationGovernor()
    let demo: DemoData?

    private var hid: SensorReader?
    private var smc: SMCReader?
    private var timer: Timer?
    private var connectTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    /// In-memory fan RPM samples for the session sparkline (temps persist in
    /// HistoryStore; fan speed does not — yet).
    private(set) var fanSamples: [(date: Date, rpm: Double)] = []

    private let defaults = UserDefaults.standard

    init(demoLevel: DemoLevel? = nil) {
        demo = demoLevel.map(DemoData.init)

        useFahrenheit = defaults.bool(forKey: "useFahrenheit")
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .dark
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .both
        let storedRefresh = defaults.double(forKey: "refreshInterval")
        refreshInterval = storedRefresh >= 1 ? min(10, storedRefresh) : 2
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        let storedThreshold = defaults.double(forKey: "notifyThresholdC")
        notifyThresholdC = storedThreshold >= 60 ? min(100, storedThreshold) : 90

        phase = .onboarding(step: 0)

        if demo == nil {
            hid = SensorReader()
            smc = SMCReader()
        }

        if defaults.bool(forKey: "hasCompletedFirstRun") {
            connect()
        }

        refresh()
        scheduleTimer()

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // willTerminate arrives on the main thread.
            MainActor.assumeIsolated {
                guard let self, self.demo == nil else { return }
                self.history.flush()
                self.eventLog.flush()
            }
        }
    }

    // MARK: Lifecycle / phases

    /// Show "Reading sensors…" then advance — always (§6: there is no nav out).
    func connect() {
        phase = .connecting
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard let self, !Task.isCancelled else { return }
            self.refresh()
            self.phase = self.sensorsAvailable ? .ready : .failure
            self.screen = .now
        }
    }

    /// Failure-screen retry: rebuild both readers, then reconnect.
    func retryReaders() {
        if demo == nil {
            hid = SensorReader()
            smc = SMCReader()
        }
        connect()
    }

    func advanceOnboarding() {
        guard case .onboarding(let step) = phase else { return }
        if step >= 1 {
            hasCompletedFirstRun = true
            connect()
        } else {
            phase = .onboarding(step: step + 1)
        }
    }

    func replaySetup() {
        phase = .onboarding(step: 0)
    }

    var sensorsAvailable: Bool {
        demo != nil || !grouped.isEmpty
    }

    /// Readings render as "--", blooms and glows off (§6 sensor error).
    var blind: Bool {
        phase == .failure || phase == .connecting || (phase == .ready && grouped.isEmpty)
    }

    // MARK: Refresh loop

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        if let demo {
            grouped = demo.grouped()
            processes = demo.processes()
            fans = demo.fans()
            fanSamples = demo.fanSamples()
            pressure = ThermalPressure.State(
                label: demo.level == .hot ? "Serious" : "Nominal",
                detail: demo.level == .hot
                    ? "macOS is reducing performance to stay cool."
                    : "macOS is not limiting performance.",
                isThrottling: demo.level == .hot
            )
            lastRefresh = Date()
            return
        }

        var readings = hid?.readAll() ?? []
        if let smc { readings += smc.temperatures() }

        let newGrouped = SensorLabeler.group(readings)
        history.record(newGrouped)

        grouped = newGrouped
        pressure = ThermalPressure.current()
        fans = smc?.fans() ?? []
        processes = ProcessMonitor.topProcesses(limit: 6)
        lastRefresh = Date()

        eventLog.check(grouped: newGrouped, topProcesses: processes)
        recordFanSample()

        // Mid-session sensor loss -> the designed error state.
        if phase == .ready && newGrouped.isEmpty {
            phase = .failure
        }

        if let payload = governor.evaluate(
            hottest: hottest,
            thresholdC: notifyThresholdC,
            popoverOpen: popoverVisible,
            topProcesses: processes
        ) {
            governor.deliver(payload)
        }
    }

    private func recordFanSample() {
        let spinning = fans.filter { $0.rpm > 0 }
        guard !spinning.isEmpty else { return }
        let avg = spinning.map(\.rpm).reduce(0, +) / Double(spinning.count)
        fanSamples.append((date: Date(), rpm: avg))
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        if let firstValid = fanSamples.firstIndex(where: { $0.date >= cutoff }), firstValid > 0 {
            fanSamples.removeFirst(firstValid)
        }
    }

    // MARK: Derived readings

    var hottest: GroupedReading? {
        grouped.max { $0.celsius < $1.celsius }
    }

    /// The six rows on Now (§4.1). Chassis and storage stay behind
    /// "All sensors" unless the machine lacks the preferred six.
    var nowGroups: [GroupedReading] {
        let byGroup = Dictionary(uniqueKeysWithValues: grouped.map { ($0.group, $0) })
        var rows = SensorGroup.nowOrder.compactMap { byGroup[$0] }
        if rows.count < 6 {
            for group in SensorGroup.nowFallback {
                if rows.count >= 6 { break }
                if let row = byGroup[group] { rows.append(row) }
            }
        }
        return Array(rows.prefix(6))
    }

    /// Every present group, spec order first, for All Sensors (§4.3).
    var allGroups: [GroupedReading] {
        let order = SensorGroup.nowOrder + [.enclosure, .storage] + SensorGroup.nowFallback
        let byGroup = Dictionary(uniqueKeysWithValues: grouped.map { ($0.group, $0) })
        var seen = Set<SensorGroup>()
        var rows: [GroupedReading] = []
        for group in order where !seen.contains(group) {
            seen.insert(group)
            if let row = byGroup[group] { rows.append(row) }
        }
        return rows
    }

    var detailReading: GroupedReading? {
        grouped.first { $0.group == detailGroup }
    }

    var headlineBand: RampBand {
        RampBand(celsius: hottest?.celsius ?? 0)
    }

    /// The sentence under the headline (§4.1).
    var sentence: String {
        guard !blind else { return "No sensor data." }
        guard let hottest else { return "No sensor data." }
        switch headlineBand {
        case .hot:
            return "Your Mac is hot. \(hottest.group.specLabel) hit \(fmt(hottest.celsius))."
        case .warm:
            return "\(hottest.group.specLabel) is warm. Expected under load."
        case .normal:
            return "Everything is normal. Nothing is working hard."
        case .cool:
            return "Everything is cool. Nothing is working hard."
        }
    }

    var isThrottling: Bool {
        !blind && pressure.isThrottling
    }

    func sessionPeak(for group: SensorGroup) -> Double? {
        if let demo { return demo.peak(for: group) }
        return history.peak(for: group.id)
    }

    // MARK: Charts

    /// Minute-resolution max temps over a window, oldest first.
    func chartSamples(for group: SensorGroup, hoursBack: Double) -> [(date: Date, celsius: Double)] {
        if let demo { return demo.samples(for: group, hoursBack: hoursBack) }
        return history.minuteHistory(for: group.id, hoursBack: hoursBack)
            .map { (date: $0.date, celsius: $0.max) }
    }

    func hasChartableHistory(for group: SensorGroup) -> Bool {
        demo != nil || history.hasChartableHistory(for: group.id)
    }

    /// History screen's three stacked charts (§4.5), falling back when a
    /// machine lacks the spec groups.
    var historyChartGroups: (primary: SensorGroup?, secondary: SensorGroup?, tertiary: SensorGroup?) {
        let present = Set(grouped.map(\.group))
        func pick(_ candidates: [SensorGroup], excluding used: Set<SensorGroup>) -> SensorGroup? {
            candidates.first { present.contains($0) && !used.contains($0) }
        }
        let primary = pick([.cpuPerformance, .soc, .cpuEfficiency], excluding: [])
        var used: Set<SensorGroup> = primary.map { [$0] } ?? []
        let secondary = pick([.gpu, .memory, .power], excluding: used)
        if let secondary { used.insert(secondary) }
        let tertiary = pick([.enclosure, .storage, .battery, .display], excluding: used)
        return (primary, secondary, tertiary)
    }

    // MARK: Throttle episodes (§4.6)

    struct ThrottleEpisode: Identifiable {
        let id: UUID
        let start: Date
        let duration: TimeInterval?   // nil while ongoing
        let peak: Double?
        let cause: String?
    }

    private var allEvents: [ThermalEventLog.Event] {
        demo?.events() ?? eventLog.events
    }

    func throttleEpisodes(hoursBack: Double) -> [ThrottleEpisode] {
        let cutoff = Date().addingTimeInterval(-hoursBack * 3600)
        let events = allEvents.sorted { $0.date < $1.date }

        var episodes: [ThrottleEpisode] = []
        var openBegan: ThermalEventLog.Event?

        for event in events {
            switch event.kind {
            case .throttleBegan:
                openBegan = event
            case .throttleEnded:
                if let began = openBegan {
                    episodes.append(ThrottleEpisode(
                        id: began.id,
                        start: began.date,
                        duration: event.date.timeIntervalSince(began.date),
                        peak: began.celsius ?? peakDuring(began.date, event.date, in: events),
                        cause: began.probableCause
                    ))
                    openBegan = nil
                }
            case .groupRanHot:
                break
            }
        }
        if let began = openBegan {
            episodes.append(ThrottleEpisode(
                id: began.id,
                start: began.date,
                duration: nil,
                peak: began.celsius ?? peakDuring(began.date, Date(), in: events),
                cause: began.probableCause
            ))
        }

        return episodes.filter { $0.start >= cutoff }.reversed()
    }

    private func peakDuring(
        _ start: Date, _ end: Date, in events: [ThermalEventLog.Event]
    ) -> Double? {
        events
            .filter { $0.kind == .groupRanHot && $0.date >= start && $0.date <= end }
            .compactMap(\.celsius)
            .max()
    }

    /// Chart annotations: events inside a window, oldest first.
    func annotationEvents(hoursBack: Double) -> [ThermalEventLog.Event] {
        let start = Date().addingTimeInterval(-hoursBack * 3600)
        return allEvents.filter { $0.date >= start }
    }

    // MARK: Actions

    func openDetail(_ group: SensorGroup) {
        detailGroup = group
        screen = .detail
    }

    func quitProcess(_ process: HeatProcess) {
        guard demo == nil else { return }
        kill(process.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refresh()
        }
    }

    private func applyLaunchAtLogin() {
        // Real registration needs an app bundle; harmless no-op until then.
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login unavailable (no app bundle yet): %@", "\(error)")
        }
    }

    // MARK: Formatting

    func fmt(_ celsius: Double) -> String {
        "\(num(celsius))°"
    }

    func num(_ celsius: Double) -> String {
        let value = useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(Int(value.rounded()))
    }

    /// Raw sensor rows: one decimal, unit-converted (§4.4).
    func raw(_ celsius: Double) -> String {
        let value = useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(format: "%.1f", value)
    }

    var unitLabel: String { useFahrenheit ? "°F" : "°C" }

    /// RPM with a thin-space thousands separator: "4 720" (§4.7).
    func rpmString(_ rpm: Double) -> String {
        let n = Int(rpm.rounded())
        guard n >= 1000 else { return String(n) }
        return "\(n / 1000)\u{2009}\(String(format: "%03d", n % 1000))"
    }

    // MARK: Device identity (Now header)

    lazy var deviceLine: String = {
        if demo != nil { return "MacBook Pro · M4 Pro" }
        var parts: [String] = []
        if let product = Self.productName() {
            parts.append(product)
        }
        if let chip = Self.chipName() {
            parts.append(chip)
        }
        return parts.isEmpty ? "This Mac" : parts.joined(separator: " · ")
    }()

    /// "MacBook Pro (14-inch, Nov 2024)" -> "MacBook Pro"
    private static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(
            entry, "product-name" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Data,
              let full = String(data: data, encoding: .utf8)
        else { return nil }
        let name = full.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        return name.components(separatedBy: " (").first
    }

    /// "Apple M4 Pro" -> "M4 Pro"
    private static func chipName() -> String? {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let brand = String(cString: buffer)
        return brand.hasPrefix("Apple ") ? String(brand.dropFirst(6)) : brand
    }
}

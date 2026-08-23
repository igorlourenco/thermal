import SwiftUI

// =============================================================================
// PopoverRoot.swift — the 360×520 popover shell (§1)
// Substrate + blooms, header, one screen at a time, footer nav.
// =============================================================================

/// The blurred blooms + vertical substrate gradient behind everything.
/// The hot substrate's red-shifted top stop is the one global "something is
/// wrong" signal — it crossfades over 400ms so the room warms up rather than
/// switching (§8).
struct SubstrateBackground: View {
    @Environment(\.theme) private var theme
    let hot: Bool
    let warmBloomCelsius: Double?
    let coolBloomCelsius: Double?
    var warmBloomSize = CGSize(width: 340, height: 270)
    var coolBloomSize = CGSize(width: 300, height: 240)
    var warmBlur: CGFloat = 28
    var coolBlur: CGFloat = 30

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: (hot ? theme.substrateHot : theme.substrateNormal)[0], location: 0),
                    .init(color: (hot ? theme.substrateHot : theme.substrateNormal)[1], location: 0.58),
                    .init(color: (hot ? theme.substrateHot : theme.substrateNormal)[2], location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .animation(.easeInOut(duration: 0.4), value: hot)

            GeometryReader { geo in
                if let warm = warmBloomCelsius {
                    RadialGradient(
                        colors: [theme.bloom(warm, alpha: 0.30), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: warmBloomSize.width * 0.35
                    )
                    .frame(width: warmBloomSize.width, height: warmBloomSize.height)
                    .blur(radius: warmBlur)
                    .position(x: -30 + warmBloomSize.width / 2, y: -70 + warmBloomSize.height / 2)
                }

                if let cool = coolBloomCelsius {
                    RadialGradient(
                        colors: [theme.bloom(cool, alpha: 0.18), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: coolBloomSize.width * 0.35
                    )
                    .frame(width: coolBloomSize.width, height: coolBloomSize.height)
                    .blur(radius: coolBlur)
                    .position(
                        x: geo.size.width + 50 - coolBloomSize.width / 2,
                        y: geo.size.height + 90 - coolBloomSize.height / 2
                    )
                }
            }
        }
        .clipped()
        .ignoresSafeArea()
    }
}

// MARK: - Root

struct PopoverRoot: View {
    @EnvironmentObject var model: ThermalModel
    @Environment(\.openWindow) private var openWindow

    private var theme: Theme { Theme(appearance: model.appearance) }

    private var isOnboarding: Bool {
        if case .onboarding = model.phase { return true }
        return false
    }

    private var showFooter: Bool {
        // Prototype: footer hidden while onboarding or connecting; the sensor
        // error screen keeps its chrome.
        !(isOnboarding || model.phase == .connecting)
    }

    var body: some View {
        let theme = theme

        ZStack {
            SubstrateBackground(
                hot: model.headlineBand == .hot && !model.blind,
                warmBloomCelsius: model.blind ? nil : model.hottest?.celsius,
                coolBloomCelsius: model.blind ? nil : model.grouped.map(\.celsius).min()
            )

            VStack(spacing: 0) {
                if !isOnboarding {
                    HeaderBar()
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showFooter {
                    FooterNav(openZen: {
                        openWindow(id: "zen")
                        // Accessory apps don't activate on openWindow, which
                        // leaves the Zen window buried behind other apps.
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    })
                }
            }
        }
        .frame(width: 360, height: 520)
        .environment(\.theme, theme)
        .preferredColorScheme(model.appearance == .dark ? .dark : .light)
        .onAppear { model.popoverVisible = true }
        .onDisappear {
            model.popoverVisible = false
            model.query = ""
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch model.phase {
            case .onboarding(let step):
                OnboardingView(step: step).id("onboard-\(step)")
            case .connecting:
                ConnectingView()
            case .failure:
                FailureView()
            case .ready:
                readyScreen
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.phase)
        .animation(.easeOut(duration: 0.18), value: model.screen)
    }

    @ViewBuilder
    private var readyScreen: some View {
        switch model.screen {
        case .now: NowView().transition(.opacity)
        case .why: WhyView().transition(.opacity)
        case .sensors: AllSensorsView().transition(.opacity)
        case .detail: DetailView().id(model.detailGroup).transition(.opacity)
        case .history: HistoryView().transition(.opacity)
        case .events: ThrottleLogView().transition(.opacity)
        case .fans: FansView().transition(.opacity)
        case .settings: SettingsView().transition(.opacity)
        }
    }
}

// MARK: - Header (§1)

struct HeaderBar: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel
    @State private var hoveringLeft = false

    var body: some View {
        let (left, right) = labels

        HStack {
            Text(left)
                .microcaps(10, tracking: 0.2)
                .foregroundStyle(theme.textDim)
                .opacity(hoveringLeft ? 0.7 : 1)
                .contentShape(Rectangle())
                .onHover { hoveringLeft = $0 }
                .onTapGesture {
                    if model.phase == .ready { model.screen = .now }
                }

            Spacer()

            Text(right)
                .microcaps(10, tracking: 0.2)
                .foregroundStyle(theme.textDim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .frame(minHeight: 36, alignment: .bottom)
    }

    private var labels: (String, String) {
        switch model.phase {
        case .connecting:
            return (model.deviceLine, "Starting")
        case .failure:
            return (model.deviceLine, "No data")
        case .onboarding:
            return ("Thermal", "")
        case .ready:
            break
        }

        switch model.screen {
        case .now:
            return (model.deviceLine, model.blind ? "No data" : pressureWord)
        case .why:
            return (
                model.headlineBand == .cool ? "← What is running" : "← Why is it hot",
                "Top processes"
            )
        case .sensors:
            let shown: Int = {
                let q = model.query.trimmingCharacters(in: .whitespaces).lowercased()
                guard !q.isEmpty else { return model.allGroups.count }
                return model.allGroups.filter { row in
                    row.group.specLabel.lowercased().contains(q)
                        || row.sensors.contains { $0.name.lowercased().contains(q) }
                }.count
            }()
            return ("← All sensors", "\(shown) of \(model.allGroups.count) groups")
        case .detail:
            let count = model.detailReading?.sensors.count ?? 0
            return ("← \(model.detailGroup.specLabel)", "\(count) sensor\(count == 1 ? "" : "s")")
        case .history:
            return ("← History", model.range.headerWord)
        case .events:
            return ("← Throttle log", model.range.eventsHeaderWord)
        case .fans:
            return ("← Fans", model.fans.isEmpty ? "Fanless" : "\(model.fans.count) unit\(model.fans.count == 1 ? "" : "s")")
        case .settings:
            return ("← Settings", "Thermal 1.0")
        }
    }

    private var pressureWord: String {
        model.pressure.label
    }
}

// MARK: - Footer nav (§1)

struct FooterNav: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel
    let openZen: () -> Void

    var body: some View {
        // space-between: equal gaps between the labels themselves, first and
        // last flush with the 16pt padding (prototype footer layout).
        HStack(spacing: 0) {
            item("Now", active: model.screen == .now) { model.screen = .now }
            Spacer()
            item("History", active: model.screen == .history || model.screen == .events) {
                model.screen = .history
            }
            Spacer()
            item("Fans", active: model.screen == .fans) { model.screen = .fans }
            Spacer()
            item("Zen", active: false, action: openZen)
            Spacer()
            item("Settings", active: model.screen == .settings) { model.screen = .settings }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
        .background(theme.glassSoft)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }

    private func item(
        _ label: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        FooterNavItem(label: label, active: active, action: action)
    }
}

private struct FooterNavItem: View {
    @Environment(\.theme) private var theme
    let label: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(label)
            .microcaps(9.5, tracking: 0.14)
            .foregroundStyle(active ? theme.textStrong : theme.textDim)
            .opacity(hovering ? 0.7 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

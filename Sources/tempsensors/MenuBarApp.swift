import SwiftUI
import AppKit

// =============================================================================
// MenuBarApp.swift
// App shell: the menu bar item (13×13 ramp chip + tabular reading, per the
// chosen style), the 360×520 popover, and the separate Zen window.
// Launched when the executable runs without CLI flags (see main.swift).
// `--demo [cool|warm|hot]` injects prototype seed data — see DemoData.swift.
// =============================================================================

struct TempBarApp: App {

    @StateObject private var model: ThermalModel

    init() {
        // Menu bar app: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)

        let demoLevel: DemoLevel? = {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: "--demo") else { return nil }
            let next = args.indices.contains(index + 1) ? args[index + 1] : ""
            return DemoLevel(rawValue: next) ?? .warm
        }()

        _model = StateObject(wrappedValue: ThermalModel(demoLevel: demoLevel))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverRoot()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Zen", id: "zen") {
            ZenView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 660, height: 420)
    }
}

// MARK: - Menu bar item

struct MenuBarLabel: View {
    @ObservedObject var model: ThermalModel

    var body: some View {
        let celsius = model.blind ? nil : model.hottest?.celsius

        HStack(spacing: 6) {
            if model.menuBarStyle != .number {
                Image(nsImage: Self.chipImage(
                    color: celsius.map { rampNSColor($0, appearance: model.appearance) }
                ))
            }
            if model.menuBarStyle != .chip {
                Text(celsius.map(model.fmt) ?? "--°")
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
        }
    }

    /// Ramp color as NSColor for the chip image (mirrors Theme.ramp).
    private func rampNSColor(_ celsius: Double, appearance: Appearance) -> NSColor {
        let systemIsDark = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let isDark = appearance.resolved(systemIsDark: systemIsDark) == .dark

        let hex: UInt32
        switch RampBand(celsius: celsius) {
        case .hot:    hex = isDark ? 0xED5C48 : 0xC93E31
        case .warm:   hex = isDark ? 0xEFAF5F : 0xCE8A3A
        case .normal: hex = isDark ? 0x9CC7AC : 0x74A085
        case .cool:   hex = isDark ? 0x86ADCB : 0x5F8CAD
        }
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }

    /// 13×13 rounded chip: ramp gradient fading to clear, 1px ramp border.
    /// nil color = blind state: hairline border, no fill.
    /// The canvas is 2px wider than the chip — transparent right margin that
    /// guarantees the gap to the reading even if the label flattens spacing.
    static func chipImage(color: NSColor?) -> NSImage {
        let size = NSSize(width: 15, height: 13)
        let image = NSImage(size: size, flipped: false) { _ in
            let chipRect = NSRect(x: 0, y: 0, width: 13, height: 13)
            let path = NSBezierPath(
                roundedRect: chipRect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: 4, yRadius: 4
            )
            if let color {
                let gradient = NSGradient(
                    starting: color,
                    ending: color.withAlphaComponent(0)
                )
                gradient?.draw(in: path, angle: -90)
                color.setStroke()
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.4).setStroke()
            }
            path.lineWidth = 1
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}

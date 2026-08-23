import SwiftUI

// =============================================================================
// Theme.swift
// Design tokens from DESIGN.md §2 and the temperature color ramp from §3.
// One ramp function drives every dot, glow, line and bloom — nothing in the
// UI colors itself thermally by hand.
// =============================================================================

enum Appearance: String {
    case dark, light
}

/// The four ramp bands. Thresholds are UI-wide (§3), not the per-component
/// ThermalStatus thresholds used by the data layer.
enum RampBand {
    case hot, warm, normal, cool

    init(celsius: Double) {
        switch celsius {
        case 90...: self = .hot
        case 70...: self = .warm
        case 55...: self = .normal
        default:    self = .cool
        }
    }

    var statusWord: String {
        switch self {
        case .hot: return "Hot"
        case .warm: return "Warm"
        case .normal: return "Normal"
        case .cool: return "Cool"
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

/// All tokens for one appearance. Built once per mode; views read it from
/// the environment.
struct Theme {
    let appearance: Appearance

    // MARK: Ramp (§3) — OKLCH converted to sRGB hex

    func ramp(_ celsius: Double) -> Color {
        switch RampBand(celsius: celsius) {
        case .hot:    return appearance == .dark ? Color(hex: 0xED5C48) : Color(hex: 0xC93E31)
        case .warm:   return appearance == .dark ? Color(hex: 0xEFAF5F) : Color(hex: 0xCE8A3A)
        case .normal: return appearance == .dark ? Color(hex: 0x9CC7AC) : Color(hex: 0x74A085)
        case .cool:   return appearance == .dark ? Color(hex: 0x86ADCB) : Color(hex: 0x5F8CAD)
        }
    }

    /// Bloom fill for a temperature. Alpha per DESIGN §1; light mode at 70%.
    func bloom(_ celsius: Double, alpha: Double) -> Color {
        ramp(celsius).opacity(appearance == .light ? alpha * 0.7 : alpha)
    }

    // MARK: Surfaces

    var substrateNormal: [Color] {
        appearance == .dark
            ? [Color(hex: 0x1A1719), Color(hex: 0x111114), Color(hex: 0x0E0E11)]
            : [Color(hex: 0xFDF8F4), Color(hex: 0xF7F7F9), Color(hex: 0xF3F3F6)]
    }

    var substrateHot: [Color] {
        appearance == .dark
            ? [Color(hex: 0x241618), Color(hex: 0x161113), Color(hex: 0x100D0E)]
            : [Color(hex: 0xFDF3F0), Color(hex: 0xF7F5F6), Color(hex: 0xF3F3F6)]
    }

    var menubar: Color   { appearance == .dark ? Color(hex: 0x18181B, alpha: 0.96) : Color(hex: 0xF6F6F8, alpha: 0.96) }
    var menuText: Color  { appearance == .dark ? Color(hex: 0xE6E6EA) : Color(hex: 0x1C1C1F) }
    var menuPanel: Color { appearance == .dark ? Color(hex: 0x222125, alpha: 0.98) : Color(hex: 0xFAFAFC, alpha: 0.98) }

    var glass: Color     { appearance == .dark ? .white.opacity(0.055) : .white.opacity(0.62) }
    var glassSoft: Color { appearance == .dark ? .white.opacity(0.035) : .white.opacity(0.45) }
    var hairline: Color  { appearance == .dark ? .white.opacity(0.09) : .black.opacity(0.08) }
    var rowBorder: Color { appearance == .dark ? .white.opacity(0.055) : .black.opacity(0.05) }
    var inset: Color     { appearance == .dark ? .white.opacity(0.09) : .white.opacity(0.9) }

    var textStrong: Color { appearance == .dark ? Color(hex: 0xFBF7F2) : Color(hex: 0x17130F) }
    var textMid: Color    { appearance == .dark ? .white.opacity(0.72) : Color(hex: 0x141418, alpha: 0.72) }
    var textDim: Color    { appearance == .dark ? .white.opacity(0.45) : Color(hex: 0x141418, alpha: 0.45) }

    var chipBg: Color   { appearance == .dark ? .white.opacity(0.07) : .white.opacity(0.7) }
    var hoverBg: Color  { appearance == .dark ? .white.opacity(0.09) : .black.opacity(0.05) }
    var rail: Color     { appearance == .dark ? .white.opacity(0.12) : .black.opacity(0.12) }
    var knob: Color     { appearance == .dark ? Color(hex: 0xF4F4F8) : .white }
    var toggleOn: Color { appearance == .dark ? .white.opacity(0.24) : .black.opacity(0.28) }

    var crosshair: Color       { appearance == .dark ? .white.opacity(0.25) : .black.opacity(0.25) }
    var neutralLine: Color     { appearance == .dark ? .white.opacity(0.5) : Color(hex: 0x141418, alpha: 0.42) }
    var neutralLineSoft: Color { appearance == .dark ? .white.opacity(0.32) : Color(hex: 0x141418, alpha: 0.28) }
    var neutralDot: Color      { appearance == .dark ? .white.opacity(0.6) : Color(hex: 0x141418, alpha: 0.5) }
    var annotation: Color      { appearance == .dark ? Color(hex: 0xFFDCBE, alpha: 0.7) : Color(hex: 0x785028, alpha: 0.85) }

    var primaryBg: Color   { appearance == .dark ? Color(hex: 0xF6F3EE) : Color(hex: 0x1B1A1D) }
    var primaryText: Color { appearance == .dark ? Color(hex: 0x17130F) : Color(hex: 0xFBF9F6) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(appearance: .dark)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Card recipe (§2)

/// glass fill + 1px top inset highlight + hairline stroke. The prototype adds
/// backdrop-blur, but the blooms behind cards are already blurred 28px, so a
/// flat token fill reads the same (SwiftUI materials blur behind the window,
/// not sibling views, so they can't reproduce the prototype effect anyway).
struct CardBackground: ViewModifier {
    @Environment(\.theme) private var theme
    var radius: CGFloat = 12
    var fill: Color?
    var showInset = true

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill ?? theme.glass)
                    .overlay(alignment: .top) {
                        if showInset {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(theme.inset)
                                .frame(height: 1)
                                .padding(.horizontal, radius / 2)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    }
            }
    }
}

extension View {
    func card(radius: CGFloat = 12, fill: Color? = nil, inset: Bool = true) -> some View {
        modifier(CardBackground(radius: radius, fill: fill, showInset: inset))
    }

    /// 10pt/9.5pt uppercase tracked label style used across headers and axes.
    func microcaps(_ size: CGFloat = 9.5, tracking em: CGFloat = 0.18) -> some View {
        font(.system(size: size))
            .tracking(size * em)
            .textCase(.uppercase)
    }
}

// MARK: - Hover fill for tappable rows (120ms, §8)

struct HoverFill: ViewModifier {
    @Environment(\.theme) private var theme
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? theme.hoverBg : .clear)
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
            }
    }
}

extension View {
    func hoverFill() -> some View { modifier(HoverFill()) }
}

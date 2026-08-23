import Foundation

// =============================================================================
// ThermalPressure.swift
// Wraps macOS's official thermal pressure signal — this is how the OS itself
// says whether it's throttling. Public API, works everywhere.
// =============================================================================

enum ThermalPressure {

    struct State {
        let label: String     // "Nominal" / "Fair" / "Serious" / "Critical"
        let detail: String    // human sentence for the UI
        let isThrottling: Bool
    }

    static func current() -> State {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return State(
                label: "Nominal",
                detail: "macOS is not limiting performance.",
                isThrottling: false
            )
        case .fair:
            return State(
                label: "Fair",
                detail: "The system is warming up — fans may spin up soon.",
                isThrottling: false
            )
        case .serious:
            return State(
                label: "Serious",
                detail: "macOS is reducing performance to stay cool.",
                isThrottling: true
            )
        case .critical:
            return State(
                label: "Critical",
                detail: "Your Mac is throttling heavily to protect itself.",
                isThrottling: true
            )
        @unknown default:
            return State(
                label: "Unknown",
                detail: "Thermal state unavailable.",
                isThrottling: false
            )
        }
    }
}

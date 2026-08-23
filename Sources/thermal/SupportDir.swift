import Foundation

// =============================================================================
// SupportDir.swift — ~/Library/Application Support/Thermal, shared by the
// persisted stores (HistoryStore, ThermalEventLog).
// =============================================================================

/// The app's Application Support directory, created on first use. Migrates the
/// pre-rename "TempSensors" folder once, so recorded history survives the
/// product rename.
func thermalSupportDir() -> URL? {
    guard let base = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first else { return nil }
    let dir = base.appendingPathComponent("Thermal", isDirectory: true)
    let legacy = base.appendingPathComponent("TempSensors", isDirectory: true)
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: legacy.path) {
        try? fm.moveItem(at: legacy, to: dir)
    }
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

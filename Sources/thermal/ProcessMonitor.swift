import Foundation

// =============================================================================
// ProcessMonitor.swift
// "Why is my Mac hot?" — the top CPU-consuming processes right now.
// Uses /bin/ps (public, sandbox-unfriendly but we're not sandboxed anyway).
// Note: %CPU is per-core, so values above 100% are normal on multi-core work.
// =============================================================================

struct HeatProcess: Identifiable {
    let pid: Int32
    let name: String
    let cpuPercent: Double

    var id: Int32 { pid }
}

enum ProcessMonitor {

    /// Top processes by current CPU usage, highest first.
    static func topProcesses(limit: Int = 5) -> [HeatProcess] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -A all processes, -c short command name, -e no need for env,
        // -o custom columns (= suppresses headers), -r sort by CPU desc.
        task.arguments = ["-Aceo", "pid=,pcpu=,comm=", "-r"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output
            .split(separator: "\n")
            .prefix(limit * 2)   // headroom in case some lines fail to parse
            .compactMap { line -> HeatProcess? in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 3,
                      let pid = Int32(parts[0]),
                      let cpu = Double(parts[1]),
                      cpu > 0.5   // ignore idle noise
                else { return nil }
                let name = parts[2...].joined(separator: " ")
                return HeatProcess(pid: pid, name: name, cpuPercent: cpu)
            }
            .prefix(limit)
            .map { $0 }
    }
}

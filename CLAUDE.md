# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Swift Package Manager project. Temperature monitor for Apple Silicon Macs (M1–M4), runs as a menu bar app or terminal dashboard from the same executable. No sudo required. macOS 13+.

## Commands

```bash
swift build                      # compile
swift run tempsensors             # menu bar app (Ctrl-C or Quit to stop)
swift run tempsensors --cli       # terminal dashboard, one snapshot
swift run tempsensors --watch     # live terminal dashboard, 2s refresh
swift run tempsensors --raw       # raw sensor list with group mapping (debugging)
swift run tempsensors --watch --raw
scripts/bundle.sh                 # release build -> dist/Thermal.app (ad-hoc signed)
scripts/bundle.sh --debug --install   # debug bundle, copy to /Applications
```

There is no test target in `Package.swift` — nothing to run via `swift test`. Verification is done by running `--raw` on real hardware and checking sensor names land in the right group (see "Verifying sensor mappings" below).

## Architecture

Two targets: `CPrivateHID` (C shim) and `tempsensors` (executable, depends on `CPrivateHID`).

### Data flow

`main.swift` dispatches on CLI flags: no flags → `TempBarApp.main()` (SwiftUI menu bar app); any of `--cli`/`--watch`/`--raw` → terminal mode. Both paths pull from the same two readers and the same `SensorLabeler`/`HistoryStore`, so a change to labeling or history logic affects both UIs identically.

Readings merge from two independent sources at each poll:

1. **`SensorReader`** — wraps the private `IOHIDEventSystemClient` API (declared in `Sources/CPrivateHID/include/CPrivateHID.h` since Apple ships no public header for it). Matches on Apple's vendor usage page (`0xff00`) / temperature usage (`5`). Provides die sensors (`PMU tdie…` on M3/M4; `pACC`/`eACC`/`GPU…` on M1/M2), NAND, battery.
2. **`SMCReader`** — talks to the `AppleSMC` IOKit user client (struct/selectors in `Sources/CPrivateHID/include/CSMC.h`). At init it enumerates *every* SMC key via `#KEY` and keeps only temperature-typed (`T…` prefix, float-ish `flt `/`ioft`/`sp78` type) keys — no hardcoded per-machine key list, so it generalizes across chip generations. Also reads fan RPM (`FNum`, `F0Ac`…) over the same connection.

Both readers return `[TemperatureReading]` (name + celsius). `SensorLabeler.group()` is the merge point: filters noise → `deduplicate` (collapse same-name readings to max) → placeholder-wall removal → `classify` each name into a `SensorGroup` by prefix pattern (`Te`→ CPU efficiency, `Tg`→ GPU, `Ts`→ chassis, `tdie`→ generic SoC, etc.) → picks each group's hottest sensor and a per-group `ThermalStatus` (Cool/Normal/Warm/Hot) via `ThermalStatus.thresholds(for:)`, since 75° is warm for a CPU die but a battery is warm at 40°.

**Placeholder walls** (e.g. 45 `Tp0…` keys frozen at 40.0° on M4 Pro) can't be detected reliably from one snapshot: under load they jitter microscopically (leak in), and at idle real sensors quantize into exact collisions (get over-dropped). Callers that poll (the app, `--watch`) pass a `PlaceholderTracker` to `group(_:tracker:)` — a channel is a placeholder only if it never moves across polls *while reading something plausible* (walls flicker to garbage 2–5° values, which don't count as movement) and ≥4 same-prefix siblings sit static at the same value; garbage readings inside a wall family are dropped too. Single snapshots fall back to the per-snapshot heuristic (`dropPlaceholders`). Verify with `--watch --raw`, which prints an "After pipeline" summary of exactly what the UI counts.

`HistoryStore` records each `group()` snapshot in-memory (rolling 24h, per-process — no persistence yet) and derives trend arrows and session peaks per group id.

### C shim boundary (`Sources/CPrivateHID`)

Swift can't call the private `IOHIDEventSystemClient` symbols directly or manage their memory via ARC, since they're undeclared opaque types. The shim:
- Declares the private functions/structs Apple doesn't header (`CPrivateHID.h`, `CSMC.h`).
- Exposes `CPHIDReleaseClient`/`CPHIDReleaseEvent` as real C functions (not macros — macros don't import into Swift) because Swift sees these types as plain `OpaquePointer` and refuses to `CFRelease` them directly.
- Functions following Apple's "Copy" naming convention (`IOHIDEventSystemClientCopyServices`, `IOHIDServiceClientCopyProperty`) return values Swift/ARC manages automatically; anything else (raw event pointers) needs manual release via the shim.

### Verifying sensor mappings

`SensorLabeler.classify`/`classifySMCKey` are pattern-based (prefix matching), not per-machine hardcoded tables — intentional, so new hardware degrades gracefully into "Other Sensors" instead of crashing or misreporting. When adding/adjusting a mapping:
- Run `swift run tempsensors --raw` (or `--watch --raw`) to see every deduplicated sensor with its currently assigned group.
- To identify an unknown grid (`TD…`, `TRD…`, `TUD…`, `TPD…`), stress one component and watch which grid's values move in `--watch --raw`.
- Comments in `SensorLabeler.swift` note mappings that were verified empirically on specific hardware (e.g. `TCMz` matching the hottest P-core exactly on M4 Pro) rather than from documentation — the private APIs here have none. Preserve/extend those provenance notes when changing classification.

### UI layer (`Sources/tempsensors/UI/`)

The menu bar app implements DESIGN.md — a complete visual spec (tokens, copy, states); `prototype/Thermal - 2a Complete.dc.html` is the pixel source of truth. Rules that matter when touching UI code:

- **One ramp function** (`Theme.ramp`, thresholds 90/70/55 °C) colors every dot, glow, line, and bloom. Never color anything thermally by hand. These UI-wide ramp thresholds are distinct from the data layer's per-group `ThermalStatus` thresholds.
- `ThermalModel` is the single observable behind all screens: readers, refresh loop, persisted settings (UserDefaults, DESIGN §9), navigation (`phase` for onboarding/connecting/ready/failure, `screen` within ready).
- Spec copy lives verbatim in `SpecGroups.swift` and the screen views — it's the product; don't paraphrase it.
- **Demo data is quarantined**: `--demo [cool|warm|hot]` injects prototype seed data via `DemoData.swift`; the model must never record demo readings to the persisted history/event stores. Real data with honest empty states is the default — never fake history or invented process activity.
- Notification (§7) is logic-only (`NotificationGovernor`); the visual needs an app bundle (UNUserNotificationCenter). Launch-at-login is attempted but also needs the bundle.
- Cards use flat token fills, not SwiftUI Materials — materials blur behind the window, not the in-window blooms, so they can't reproduce the prototype's backdrop-blur (the blooms are pre-blurred, so flat fills read the same).

### Key constraints

- **App Sandbox must stay off** — both readers return nothing under sandboxing.
- Uses private API (`IOHIDEventSystemClient`), so this is fine for a notarized direct-download app but not Mac App Store eligible.
- Bare SwiftPM executable, no `.app` bundle — no launch-at-login, notifications, or app icon until wrapped in an Xcode project.

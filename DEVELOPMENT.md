# Developing Thermal

Notes for working on the source. For what the app is and how to install it, see
[README.md](README.md); for shipping a release, see [RELEASING.md](RELEASING.md).

Thermal is a Swift Package Manager project. Runs as a **menu bar app** or a **terminal dashboard** from the same executable. No sudo required. macOS 13+.

Reads every thermal sensor the machine exposes, translates ~250 cryptic channels into a handful of groups a normal person understands, and adds the context that makes the numbers meaningful: trends, session peaks, macOS's own throttling signal, fan state, and which apps are generating the heat.

```
──────────────────────────────────────────────────────────────
  CPU – Performance     83°  ↑   Warm    peak 88°
  CPU – Efficiency      67°  →   Normal
  Graphics (GPU)        61°  →   Cool
  Memory                51°  →   Cool
  Storage (SSD)         42°  →   Cool
  Battery               42°  →   Warm
  Power Delivery        83°  ↑   Warm
  Display               71°  →   Warm
  Chassis & Airflow     57°  →   Normal
──────────────────────────────────────────────────────────────
  Thermal pressure: Nominal — macOS is not limiting performance.
  Fans: off — cooling passively.
  Top heat sources: Xcode 214% · Chrome 96% · WindowServer 41%
──────────────────────────────────────────────────────────────
  CPU – Performance is warm — expected under load.
```

## Run

```bash
swift run thermal            # menu bar app (Ctrl-C or Quit to stop)
swift run thermal --cli      # terminal dashboard, one snapshot
swift run thermal --watch    # live terminal dashboard, 2s refresh
swift run thermal --raw      # raw sensor list with group mapping (debugging)
swift run thermal --watch --raw
```

The menu bar app shows the hottest group's temperature; clicking opens the dashboard popover. Click the °C/°F label to switch units (persisted). Hover a heat-source row to reveal a quit button. Appearance follows the system.

`--raw` is the diagnostic view: every deduplicated sensor with its assigned group. Keep it forever: it's how you audit the mapping on new hardware.

## Layout

```
Package.swift
Sources/
  CPrivateHID/               C shim target
    include/
      CPrivateHID.h          private IOHIDEventSystemClient declarations
      CSMC.h                 AppleSMC user-client struct + selectors
    shim.c
  thermal/
    SensorReader.swift       HID sensor hub reader (die temps, NAND, battery)
    SMCReader.swift          SMC reader: temps, fans, generic key access
    SensorLabeler.swift      names -> groups, statuses, dedup, placeholder filter
    ThermalPressure.swift    macOS throttling state (ProcessInfo.thermalState)
    ProcessMonitor.swift     top CPU processes via /bin/ps
    HistoryStore.swift       recorded samples: trends, peaks, chart data
    ThermalEventLog.swift    throttle log (thermal pressure changes + causes)
    SupportDir.swift         ~/Library/Application Support/Thermal/
    MenuBarApp.swift         SwiftUI MenuBarExtra entry point
    UI/                      screens, model, theme (see DESIGN.md)
    main.swift               dispatcher: flags -> CLI, no flags -> app
Resources/                   Info.plist, icons, DMG background
scripts/                     bundle.sh, dmg.sh, appcast.sh, genassets.swift, ...
```

## How it works

**Two data sources, merged:**

1. **HID sensor hub** (`IOHIDEventSystemClient`, private API): matched on Apple's
   vendor usage page (0xff00) / temperature usage (5). Provides die sensors
   (`PMU tdie…` on M3/M4; `pACC`/`eACC`/`GPU…` on M1/M2), NAND, and battery.
2. **AppleSMC** (undocumented-but-public user client): all keys are enumerated
   at init via `#KEY`, temperature-typed `T…` keys are kept and polled.
   Provides per-cluster CPU, GPU, chassis, airflow, display, VRM sensors,
   plus fan RPM (`FNum`, `F0Ac`…) via the same connection.

**Labeling** (`SensorLabeler`) is pattern-based, never hardcoded per machine:
name prefixes map to groups (`Te`→ CPU efficiency, `Tg`→ GPU, `Ts`→ chassis…),
duplicates collapse to the max per name, and placeholder walls (many sibling
keys with bit-identical values, e.g. `Tp0…` all at exactly 40.0°) are dropped.
Each group reports its **hottest** sensor and a plain-language status
(Cool / Normal / Warm / Hot) with per-component thresholds: 75° is warm for a
CPU die but a battery is warm at 40°.

Several mappings were verified empirically on an M4 Pro (e.g. `TCMz` matches
the hottest P-core exactly; `TVM…` tracks CPU load, so it's a voltage
regulator, not the display). Unknown keys land visibly in "Other Sensors"
rather than disappearing.

## Known limitations / notes

- **Private API**: fine for a notarized direct-download app (the approach of
  Stats, TG Pro, iStat Menus), but not Mac App Store eligible.
- **App Sandbox must stay OFF**: sandboxed, both readers return nothing.
- `swift run` gives you a bare executable: no launch-at-login, notifications,
  or app icon. Those need the bundle from `scripts/bundle.sh`.
- Sensor sets vary by model: 3–10 groups depending on the Mac. On M3/M4,
  per-block identification of the remaining unknown grids (`TD…`, `TRD…`,
  `TUD…`, `TPD…`) is pending empirical testing (stress one component,
  watch which grid responds in `--watch --raw`).
- `%CPU` in heat sources is per-core, so >100% is normal.

## Verified on

- MacBook Pro, M4 Pro (macOS 26). Other M-series: mappings should degrade
  gracefully; please run `--raw` and report what lands in "Other Sensors".
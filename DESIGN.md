

&nbsp;

# Thermal — design specification for SwiftUI implementation

Thermal is a macOS menu-bar utility that reads the Mac's own thermal sensors and
explains, in plain language, what the numbers mean.

**What this document is.** A complete visual and behavioural spec for the UI. The
data layer already exists — nothing here describes how to read SMC / IOKit
sensors, poll them, or persist history. Everything here is presentation: layout,
tokens, typography, copy, states, transitions.

**What the bundled HTML is.** `prototype/Thermal - 2a Complete.dc.html` is a
design reference, not production code. Open it in a browser: the controls under
the window switch load level (Cool / Warm / Hot), first run, the notification,
the empty-history state, connecting, sensor error, fanless hardware, and
light/dark. Read it to resolve any ambiguity in this document — it is the source
of truth for pixel values. Do not port its markup; rebuild it in SwiftUI with
native idioms (`MenuBarExtra`, `Form`, `Chart`, `.ultraThinMaterial`).

Fidelity: **high**. Colors, sizes, spacing, and copy are final. Match them.

---

## 1. Shell and geometry


| Surface       | Size      | Corner radius | Notes                                            |
| ------------- | --------- | ------------- | ------------------------------------------------ |
| Menu bar item | intrinsic | 5             | 13×13 chip (radius 4) + tabular reading, 6pt gap |
| Popover       | 360 × 520 | 16            | Fixed. Never resizes; screens fit inside it      |
| Zen window    | 660 × 420 | 18            | Separate window, opened from the popover footer  |
| Notification  | 344 wide  | 14            | System notification; see §7                      |


Popover shadow: `0 24 60 rgba(0,0,0,0.5)` plus a 1px inner top highlight at
`rgba(255,255,255,0.06)`. In SwiftUI the popover chrome is system-drawn — apply
the material and the 1px top hairline, skip the outer shadow.

**Popover structure**, top to bottom, in a `VStack(spacing: 0)`:

1. **Header** — 18pt top padding, 20pt horizontal. Two 10pt uppercase labels
 with 0.2em tracking, dimmed: left is context or a back affordance
 (`← CPU — PERFORMANCE`), right is a status word. Left label is tappable and
 returns to Now.
2. **Body** — flexible, one screen at a time (§4).
3. **Footer nav** — 9pt padding vertical, 16pt horizontal, hairline top border,
 `glassSoft` fill. Five 9.5pt uppercase items with 0.14em tracking, spaced
 `.frame(maxWidth: .infinity)` apart: **Now · History · Fans · Zen ·
 Settings**. Active item is `textStrong`, the rest `textDim`.

Header and footer are both hidden on first run, denied, and connecting — those
screens own the whole popover.

**Background.** Two blurred radial blooms behind the content, tinted by the
hottest current reading (§3):

- warm bloom — 340×270, offset top −70 / left −30, blur 28, alpha 0.30
- cool bloom — 300×240, offset bottom −90 / right −50, blur 30, alpha 0.18

Over that sits a vertical substrate gradient. In the hot state the gradient's top
stop shifts red — this is the one global signal that something is wrong, and it
reads before any number does. Do not skip it.

Zen uses the same blooms at 560×420 / 480×360, blur 46 / 48.

---

## 2. Design tokens

The prototype uses OKLCH. SwiftUI has no OKLCH initializer, so the hexes below
are conversions — accurate enough to ship, but the OKLCH values are canonical if
you want to convert precisely at build time.

### Dark (default)


| Token                    | Value                                          |
| ------------------------ | ---------------------------------------------- |
| `stage` (desktop behind) | `#0F0F11`                                      |
| `menubar`                | `#18181B` @ 96%                                |
| `menuText`               | `#E6E6EA`                                      |
| `menuPanel` (dropdown)   | `#222125` @ 98%                                |
| `notifBg`                | `#1E1D21` @ 78%                                |
| `substrate` normal       | linear ↓ `#1A1719` → `#111114` 58% → `#0E0E11` |
| `substrate` hot          | linear ↓ `#241618` → `#161113` 58% → `#100D0E` |
| `glass`                  | white @ 5.5%                                   |
| `glassSoft`              | white @ 3.5%                                   |
| `hairline`               | white @ 9%                                     |
| `rowBorder`              | white @ 5.5%                                   |
| `inset` (top highlight)  | white @ 9%, 1px                                |
| `textStrong`             | `#FBF7F2`                                      |
| `textMid`                | white @ 72%                                    |
| `textDim`                | white @ 45%                                    |
| `chipBg`                 | white @ 7%                                     |
| `hoverBg`                | white @ 9%                                     |
| `rail`                   | white @ 12%                                    |
| `knob`                   | `#F4F4F8`                                      |
| `toggleOn`               | `#F5BB6A` (brand amber, both modes)            |
| `crosshair`              | white @ 25%                                    |
| `neutralLine`            | white @ 50%                                    |
| `neutralLineSoft`        | white @ 32%                                    |
| `annotation`             | `#FFDCBE` @ 70%                                |
| `primary` button         | fill `#F6F3EE`, label `#17130F`                |


### Light


| Token              | Value                                          |
| ------------------ | ---------------------------------------------- |
| `stage`            | `#E8E6E3`                                      |
| `menubar`          | `#F6F6F8` @ 96%                                |
| `menuText`         | `#1C1C1F`                                      |
| `menuPanel`        | `#FAFAFC` @ 98%                                |
| `notifBg`          | `#FCFBFC` @ 86%                                |
| `substrate` normal | linear ↓ `#FDF8F4` → `#F7F7F9` 58% → `#F3F3F6` |
| `substrate` hot    | linear ↓ `#FDF3F0` → `#F7F5F6` 58% → `#F3F3F6` |
| `glass`            | white @ 62%                                    |
| `glassSoft`        | white @ 45%                                    |
| `hairline`         | black @ 8%                                     |
| `rowBorder`        | black @ 5%                                     |
| `inset`            | white @ 90%, 1px                               |
| `textStrong`       | `#17130F`                                      |
| `textMid`          | `#141418` @ 72%                                |
| `textDim`          | `#141418` @ 45%                                |
| `chipBg`           | white @ 70%                                    |
| `hoverBg`          | black @ 5%                                     |
| `rail`             | black @ 12%                                    |
| `knob`             | `#FFFFFF`                                      |
| `toggleOn`         | `#F5BB6A` (brand amber, both modes)            |
| `crosshair`        | black @ 25%                                    |
| `neutralLine`      | `#141418` @ 42%                                |
| `neutralLineSoft`  | `#141418` @ 28%                                |
| `annotation`       | `#785028` @ 85%                                |
| `primary` button   | fill `#1B1A1D`, label `#FBF9F6`                |


Appearance is an explicit Light / Dark preference in Settings, not
`.colorScheme`-derived. Persist it; default dark. Blooms drop to 70% alpha in
light mode.

### Card recipe

Every card in the app is the same construction, and consistency here is most of
what makes the UI feel built:

```
RoundedRectangle(cornerRadius: 12)
  .fill(.ultraThinMaterial)          // glass
  .overlay(top 1px inset highlight)
  .overlay(RoundedRectangle(cornerRadius: 12).stroke(hairline, lineWidth: 1))
```

Radii: 12 cards · 11 fan tiles · 10 banners and buttons · 9 search field and
dropdown · 7 segmented containers · 6 chips · 5–6 inner segmented pills.
Row dividers are `rowBorder`, and the **last row in a card has no divider**.

### Spacing

Card gutter 14pt from the popover edge. Text blocks 20pt. Row padding 11pt
vertical × 14pt horizontal (13pt where a 22pt icon leads). Card-internal
padding 12–16pt. Inter-card gap 8–12pt.

---

## 3. The temperature color ramp

One function drives every dot, number glow, line, and bloom in the app. Never
color anything thermally by hand.


| Range   | Meaning | Dark                               | Light                              |
| ------- | ------- | ---------------------------------- | ---------------------------------- |
| ≥ 90 °C | Hot     | `oklch(0.65 0.19 30)` ≈ `#ED5C48`  | `oklch(0.55 0.18 30)` ≈ `#C93E31`  |
| 70–89   | Warm    | `oklch(0.78 0.13 75)` ≈ `#EFAF5F`  | `oklch(0.68 0.14 68)` ≈ `#CE8A3A`  |
| 55–69   | Normal  | `oklch(0.74 0.05 155)` ≈ `#9CC7AC` | `oklch(0.62 0.06 155)` ≈ `#74A085` |
| &lt; 55 | Cool    | `oklch(0.70 0.06 235)` ≈ `#86ADCB` | `oklch(0.60 0.07 235)` ≈ `#5F8CAD` |


Two derived words, used in the header and in Zen:

- **status** (Zen header): Hot ≥90 · Warm ≥70 · Normal ≥55 · Cool below
- **pressure** (Now header): Serious ≥95 · Fair ≥88 · Nominal below

The headline value is always the **hottest group**, not a fixed sensor. So the
big number can jump between CPU and power delivery, and the sentence beneath it
names whichever group it came from.

Glows: headline `0 2 24 <rampColor>`, detail number `0 2 22`, Zen `0 4 50`. On
the Now list, only the hottest row's dot gets `0 0 8 <rampColor>`; every other
dot is flat.

---

## 4. Screens

Eight sensor groups, all with hand-written explanatory copy. Reproduce the copy
verbatim — it is the product.


| Key       | Label                 | Sensor IDs                          |
| --------- | --------------------- | ----------------------------------- |
| `pcore`   | CPU — Performance     | Tp01, Tp05, Tp09, Tp0D · P-core 0–3 |
| `ecore`   | CPU — Efficiency      | Te01, Te05 · E-core 0–1             |
| `gpu`     | Graphics (GPU)        | Tg05, Tg0D · GPU cluster 0–1        |
| `mem`     | Memory                | Tm02, Tm06 · DRAM 0–1               |
| `power`   | Power delivery        | Ts01, Ts05 · VRM A–B                |
| `display` | Display               | Td01 · Panel                        |
| `chassis` | Chassis &amp; airflow | Ta01 · Airflow in, Tc0A · Top case  |
| `storage` | Storage (SSD)         | Tn01 · NAND                         |


Explanations, one per group:

- **CPU — Performance** — "The performance cores handle demanding work — compiles, exports, rendering. Sustained highs are normal; macOS manages them."
- **CPU — Efficiency** — "The efficiency cores run background work — indexing, sync, notifications. They stay cool almost all the time."
- **Graphics (GPU)** — "Graphics work: displays, video decode, rendering. It warms in bursts rather than staying hot."
- **Memory** — "Unified memory sits beside the chip on the same package, so it tracks the die but stays much cooler."
- **Power delivery** — "The regulators feeding the chip. They run hot by design — normal even when the CPU is close to idle."
- **Display** — "Backlight and panel driver. Brightness matters more here than workload."
- **Chassis &amp; airflow** — "Skin and airflow sensors — the closest thing to how warm the Mac feels in your hands."
- **Storage (SSD)** — "The SSD controller. It spikes during big copies and settles within seconds."

### 4.1 Now — the default screen

Header: `MACBOOK PRO · M4 PRO` / pressure word.

- **Headline** — 72pt, weight 200, tracking −0.05em, tabular, `textStrong`, with
the ramp glow. Beside it a tappable unit chip (`°C` / `°F`, 16pt weight 300,
radius 6, `chipBg`) that toggles units app-wide. 10pt below, a 14pt sentence in
`textMid`:
  - hot — "Your Mac is hot. CPU — Performance hit 97°."
  - warm — "CPU — Performance is warm. Expected under load."
  - cool — "Everything is cool. Nothing is working hard."
- **Throttle banner** (hot only) — radius 10, 1px border `hot @ 42%`, fill
`hot @ 12%`, a 6pt glowing dot, then "macOS is slowing things down to stay
cool." at 12.5pt, and a trailing `→`. Tapping it opens the throttle log.
- **Sensor list** — one card, six rows: pcore, ecore, gpu, mem, power, display.
Each row: 6pt ramp dot · 12.5pt label · 13pt tabular reading. The hottest row
renders label and value in `textStrong`; others `textMid`. Whole row tappable →
detail.
- **Footer pair** — two side-by-side buttons, 8pt gap: a flexible one reading
"Why is it hot?" (or "What is running?" in the cool state) and a compact "All
sensors". Both radius 10, `glassSoft`, with a trailing `→` in `textDim`.

Only six of eight groups appear here. Chassis and storage are deliberately behind
"All sensors" — the list stays scannable at a glance.

### 4.2 Why is it hot

Header: `← WHY IS IT HOT` (or `← WHAT IS RUNNING` when cool) / `TOP PROCESSES`.

Title 19pt weight 300, pluralized by count: "Four apps are keeping the CPU
busy." Sub: "Quitting the top one usually drops 10–15° within a minute."

Process rows: 22pt app icon (radius 6) · name 12.5pt `textStrong` · below it a
10pt uppercase note with 0.1em tracking (`38 TABS`, `BUILDING · AURORA`,
`6 CONTAINERS`, `BACKGROUND RENDER`) · CPU percentage, tabular, ramp-colored for
the top two and `textMid` below · a `QUIT` chip (10pt uppercase, radius 5).

Seed set: Google Chrome 214%, Xcode 186%, Docker Desktop 94%, Final Cut Pro 61%
(the first two drop to 96% / 74% when not hot).

Footer line, 11pt `textDim`: "Updated 4 seconds ago".

**Empty state** — reached by quitting everything, and the normal case on an idle
Mac. Replace the card with a dashed-border `glassSoft` panel, centered, 26pt
vertical padding: "Nothing is working hard." then, dimmer, "No process is using
more than 5% of the CPU. Any warmth you see now is left over heat." Title
becomes "Nothing is driving the CPU.", sub becomes "Temperatures should keep
falling for the next few minutes.", footer becomes "Nothing heavy is running
now."

### 4.3 All sensors

Header: `← ALL SENSORS` / `<n> OF 8 GROUPS`.

A search field at the top — full width, radius 9, `chipBg`, 12.5pt, placeholder
"Search sensors", no focus ring. It filters on **both** group label and raw
sensor ID, so typing `vrm` finds Power delivery. Below, a scrolling card of all
eight groups: dot · label · a 10pt uppercase meta line ("2 SENSORS · PEAK 90°")
· reading. Rows open detail. No match: "No sensor matches that." centered at
12pt `textDim`.

### 4.4 Sensor detail

Header: `← <GROUP LABEL>` / `<n> SENSORS`.

- 58pt headline + unit chip on the left; right-aligned "SESSION PEAK" label with
an 18pt weight-200 value beneath.
- The group's explanation paragraph, 12.5pt, 20pt margins.
- **Chart card** — a 9.5pt uppercase row reading `24 HOURS` on the left and a
readout on the right, then a 76pt-tall line chart, 1.3pt stroke in the ramp
color. A vertical crosshair and a 2.6pt dot mark the cursor. Default cursor is
the last sample and the readout shows `14:12 · 91°` in `textDim`. **On hover
the chart scrubs**: crosshair and dot follow the pointer, and the readout
switches to `textStrong` showing that sample's time and temperature
(`09:47 · 74°`). Leaving resets to the default. 13 samples across the day.
- **Raw sensors card** — "RAW SENSORS" header over a hairline, then monospaced
rows (`SF Mono`, 11pt): sensor ID left in `textDim`, value right in `textMid`,
one decimal place, converted with the unit setting.

### 4.5 History

Header: `← HISTORY` / `TODAY` · `7 DAYS` · `30 DAYS`.

A subtitle on the left and a three-way segmented control on the right
(`24H / 7D / 30D`, radius 7 container, radius 5 pills, active pill `hoverBg` and
`textStrong`). All three ranges are real: each has its own series, axis labels,
annotations, and subtitle.


| Range | Subtitle                                   | Axis                                  | Annotations                                                |
| ----- | ------------------------------------------ | ------------------------------------- | ---------------------------------------------------------- |
| 24h   | "Two busy stretches today."                | 00:00 · 06:00 · 12:00 · 18:00 · Now   | "2:14 PM · Xcode build" @56%, "9:40 AM · Export" @16%      |
| 7d    | "Tuesday ran hottest — three long builds." | Thu · Sat · Mon · Tue · Now           | "Tue · 4 h build" @46%, "Sat · Video export" @18%          |
| 30d   | "Two hot weeks. Both were release weeks."  | Jul 25 · Aug 1 · Aug 8 · Aug 15 · Now | "Aug 11 · Release week" @54%, "Jul 29 · Export batch" @12% |


One card holds three stacked charts of decreasing prominence — the visual
hierarchy is the point:

1. **CPU — Performance**, 60pt tall, ramp-colored 1.3pt stroke, a 2.6pt dot on
 the peak, and beneath it a 9pt uppercase annotation in `annotation` color,
 absolutely positioned at the percentage above.
2. **Graphics (GPU)**, 48pt, `neutralLine` at 1.2pt, dot in `neutralDot`,
 annotation in `textDim`.
3. **Chassis &amp; airflow**, 34pt, `neutralLineSoft`, no dot, no annotation.

Each chart carries a 9.5pt uppercase header row: name left, `peak 91°` or
`now 57°` right in `textDim`. Then the shared axis row above a hairline, then a
tappable link row: "5 throttle events this week" with a trailing `→`.

### 4.6 Throttle log

Header: `← THROTTLE LOG` / `TODAY` · `LAST 7 DAYS` · `LAST 30 DAYS`, following
the range chosen on History.

Title 18pt weight 200: "Your Mac slowed itself down five times this week." Sub
12pt `textDim`: "33 minutes in total, all of it during builds and exports."

Both strings and the History link count are derived from **one** event list
filtered by the range — they must never disagree. Seed events, with an age in
days used for filtering:


| When              | Duration | Peak | Cause                | Age |
| ----------------- | -------- | ---- | -------------------- | --- |
| Today · 2:14 PM   | 6 min    | 97°  | Xcode build · Chrome | 0   |
| Today · 9:41 AM   | 2 min    | 92°  | Final Cut export     | 0   |
| Mon · 4:08 PM     | 18 min   | 99°  | Docker build         | 2   |
| Sun · 11:20 AM    | 3 min    | 93°  | macOS update         | 3   |
| Sat · 8:52 PM     | 4 min    | 91°  | Photos analysis      | 4   |
| Aug 14 · 3:30 PM  | 11 min   | 98°  | Release build        | 9   |
| Aug 11 · 10:06 AM | 7 min    | 95°  | Xcode archive        | 12  |
| Aug 3 · 6:14 PM   | 9 min    | 96°  | Export batch         | 20  |


So: today 2 events / 8 min, 7 days 5 / 33, 30 days 8 / 60. Counts spell out in
words in the title ("twice", "five times"), digits in the link.

Row: a 6pt ramp dot (colored by that event's peak) · when, 12.5pt `textStrong` ·
peak, tabular, ramp-colored. Second line, indented 16pt, 10.5pt `textDim`:
`6 min · Xcode build · Chrome`.

### 4.7 Fans

Header: `← FANS` / `2 UNITS` or `FANLESS`.

Two side-by-side tiles (radius 11, 10pt gap): `LEFT` / `RIGHT` label, a 26pt
weight-200 tabular RPM with a thin-space thousands separator (`4 720`), and a 2pt
progress rail beneath filled in the headline ramp color. Percentage maps
1200–5400 RPM. Below the tiles, a range row: `IDLE 1 200` / `MAX 5 400`. Then a
24-hour fan-speed sparkline in its own card, 42pt tall, `neutralLine`. A closing
sentence in `textMid`:

- hot — "Running near maximum. You can hear these."
- warm — "Ramping up gently. You probably can't hear them yet."
- cool — "Barely turning. Silent from here."

Seed RPM: 1 210 cool · 2 480 warm · 4 720 hot; the right fan always runs 30 RPM
faster than the left.

**Fanless hardware** replaces the whole screen with centered copy: "No fans —
your Mac cools silently." and "The Air moves heat through its chassis. Under long
loads it will slow itself down instead of getting louder." Detect fan count and
switch automatically.

### 4.8 Settings

Main card, six rows, each 11pt vertical:

1. **Units** — segmented `°C` / `°F`. Two independent targets: re-picking the
 active unit must not toggle.
2. **Appearance** — segmented Light / Dark.
3. **Menu bar style** — a dropdown reading `Chip + number ⌄`. Opens a 184pt panel
 below-right (radius 9, `menuPanel`, shadow `0 12 30 rgba(0,0,0,0.35)`) with
 three options, a `✓` on the active one, and the active row filled `hoverBg`:
  - **Chip + number** — "Colour and reading"
  - **Number only** — "Quietest option"
  - **Chip only** — "Colour at a glance"
   The choice changes the menu bar item immediately.
4. **Refresh** — a 100×3pt rail, clickable anywhere along its length, 13pt knob,
 value 1–10 s shown tabular to the right. Seed 2 s.
5. **Launch at login** — 38×22 switch, 18pt knob, `toggleOn` when on. Seed on.
6. **Notify above** — sub-line "Only for sustained highs, never for spikes", and
 a `− 90° +` stepper clamped to 60–100 °C.

A second **Updates card** below (10pt gap), two rows:

1. **Updates** — sub-line "You have Thermal 1.0" (current version), and a
 `Check now` chip that triggers a user-initiated Sparkle check
 (installer.md §4).
2. **Update automatically** — 38×22 switch, seed on. Drives Sparkle's check
 and download/install together. Both rows dim when running unbundled
 (`swift run`), where Sparkle can't operate.

Footer row outside the cards: "Reconnect" (→ connecting), "Replay setup"
(→ first run), and "Quit Thermal" (quits the app), all 11pt `textDim` — copy
short enough that the row never wraps at 360pt.

### 4.9 Zen

A separate 660×420 window. Header row: `THERMAL · ZEN` left, `EXIT` right, both
9.5pt uppercase with 0.3em tracking. Body is two columns 48pt apart: a 148pt
weight-100 number with a 24pt unit toggle beside it, and on the right an 18pt
weight-200 sentence over a compact three-row card (efficiency cores, GPU,
memory). Same tokens, more air. Intended to be left open on a second display.

---

## 5. First run

Three steps in the popover with header and footer nav hidden, 26pt padding, and a
persistent bottom bar: a primary button on the left, an optional "Not now" beside
it, and three 5pt progress dots pushed right (active `textStrong`, rest `rail`).

**Step 1 — welcome.** A 46pt app tile (radius 13, ramp-tinted) pinned top-left,
then, pushed to the bottom of the pane, "Thermal" at 26pt weight 200 and: "Your
Mac measures its own temperature in about forty places. Thermal reads those
numbers and tells you what they mean." Button: **Continue**.

**Step 2 — permission.** Title "Allow sensor access" 21pt weight 200. Body:
"macOS keeps sensor readings behind a permission. Thermal needs it to show
anything at all." Then a two-row disclosure card — a 52pt uppercase gutter label
against a value:

- **READS** — "Temperatures, fan speed, power draw" (`textStrong`)
- **NEVER** — "Files, network, screen, keystrokes" (`textMid`)

Below, 11pt `textDim`: "Readings stay on this Mac. Thermal has no network
access." Buttons: **Allow access** and **Not now**.

Being specific about what is *not* read is the whole job of this screen. Keep
both rows.

**Step 3 — menu bar style.** "How it should look up there", sub "You can change
this any time in Settings." Three selectable cards, 8pt apart, each showing a
**live 74pt-wide preview of the actual menu bar item** on a `menubar`-colored
plate, then the option name and note (same three options as Settings). Selected
card takes a `textDim` border and `hoverBg` fill. Button: **Start Thermal** →
connecting → Now.

**Denied** (from "Not now"). Own screen, no nav. A 44pt neutral tile, then
"Thermal has nothing to show yet." at 19pt weight 200 and "Without sensor access
there are no temperatures to read. You can grant it here, or later in System
Settings › Privacy &amp; Security." Buttons: **Allow access** (→ connecting) and
**Quit Thermal**. Note the tone: no scolding, and a real route back.

---

## 6. States

Every one of these is a state the app will actually be in. All are reachable in
the prototype from the controls beneath the window.


| State              | Trigger                                            | Presentation                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------ | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cool**           | everything &lt; 55°                                | Blue ramp, cool substrate, "Everything is cool. Nothing is working hard.", no throttle banner, empty process list, fans near idle. The most common real state — check it looks intentional, not empty.                                                                                                                                                                                                                                                |
| **Warm**           | default seed                                       | Amber ramp, warm substrate                                                                                                                                                                                                                                                                                                                                                                                                                            |
| **Hot**            | sustained ≥ 90°                                    | Red ramp, red-shifted substrate, throttle banner on Now, notification fires, fans near max                                                                                                                                                                                                                                                                                                                                                            |
| **Connecting**     | launch, "Try again", "reconnect", end of first run | Header and footer hidden. Three 7pt dots pulsing on a 1.3s ease-in-out loop, staggered 0.18s. "Reading sensors…" 19pt weight 200 and "First readings take a few seconds. Thermal is finding out which sensors your Mac has." Auto-advances to Now after ~1.9s — **it must always advance**, since there is no nav out.                                                                                                                                |
| **No history yet** | fresh install                                      | History: a dashed-border panel, "Nothing recorded yet." over "Thermal keeps 30 days of readings on this Mac. The first charts appear after about an hour of use." Detail chart: a 76pt placeholder reading "Not enough history yet. / This chart fills in over the first hour." and the readout shows `COLLECTING`. Throttle log: "No throttling so far." over "When macOS slows your Mac down to cool it, the event lands here with what caused it." |
| **Sensor error**   | service lost mid-session                           | Readings render as `--`, blooms and glows off, chip border falls to `hairline`, sentence "No sensor data.", header right reads `NO DATA`. A 44pt neutral tile, "We can't read the sensors right now." and "Nothing is wrong with your Mac — the app lost its connection to the sensor service." Buttons **Try again** (→ connecting) and "Contact support".                                                                                           |
| **Fanless**        | no fans detected                                   | §4.7                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **Light / Dark**   | Settings                                           | §2                                                                                                                                                                                                                                                                                                                                                                                                                                                    |


---

## 7. Notification

The app's primary output when the window is closed, so it carries the full
argument rather than a bare number. Fires when a reading stays above the
threshold for five minutes — never on spikes. Suppress while the popover is open.

Layout, 344pt wide, radius 14, `notifBg` over a heavy blur:

- Top block, 13pt padding: a 26pt ramp-tinted app tile; beside it `THERMAL` at
10pt uppercase with 0.16em tracking and a dim "now"; a 13.5pt title; a 12pt
body in `textMid`; and a `×` on the far right.
- Title: "Sustained 92° for five minutes" — the number is the live reading.
- Body: "Chrome and Xcode are driving the CPU. Quitting Chrome usually drops
10–15°." Name real processes; the advice is the payload.
- A hairline divider, then two equal action buttons split by a vertical hairline:
**Show details** (opens the popover on Why is it hot) and **Snooze 1 hour**.

---

## 8. Interaction and motion

- Menu bar item click toggles the popover.
- Every list row is a full-width tap target with a `hoverBg` fill on hover.
- The header's left label and the footer's Now item both return to Now.
- The unit chip appears on Now, detail, and Zen; tapping any of them switches
units everywhere, including the monospaced raw values.
- Detail chart hover scrubs (§4.4). Pointer leave resets.
- Refresh rail responds to a click anywhere along it, not just a drag.

Motion is quiet. Suggested: screen changes 180ms ease-out with no slide; hover
fills 120ms; notification in on a 260ms spring from the top-right and out on
200ms ease-in; connecting dots as specified; substrate gradient cross-fades over
400ms when the load level changes so the room warming up is felt rather than
seen. Nothing else animates. No spinners besides the three dots, no easing on
numbers — readings snap.

---

## 9. State to persist

`unit` (C/F) · `appearance` (light/dark) · `menuBarStyle` (both/number/chip) ·
`refreshInterval` (1–10s) · `launchAtLogin` · `notifyThresholdC` (60–100) ·
`hasCompletedFirstRun` · `sensorPermissionGranted` · notification snooze-until.

Ephemeral: current screen, selected detail group, history range, search query,
chart cursor, dismissed processes.

---

## 10. Type reference

Single family: SF Pro Display (`-apple-system`), plus SF Mono for raw sensor
values. Weight is the main instrument — 100 through 300 for anything large,
regular for body.


| Role                    | Size   | Weight  | Tracking              |
| ----------------------- | ------ | ------- | --------------------- |
| Zen number              | 148    | 100     | −0.055em              |
| Now headline            | 72     | 200     | −0.05em               |
| Detail headline         | 58     | 200     | −0.05em               |
| Fan RPM                 | 26     | 200     | —                     |
| First-run wordmark      | 26     | 200     | −0.02em               |
| Screen title            | 18–21  | 200–300 | —                     |
| Zen sentence            | 18     | 200     | —                     |
| Now sentence            | 14     | regular | —                     |
| Settings row label      | 13     | regular | —                     |
| Body / row label        | 12.5   | regular | —                     |
| Sub-copy                | 11–12  | regular | —                     |
| Raw sensor value (mono) | 11     | regular | —                     |
| Card header, axis       | 9.5    | regular | 0.18em, uppercase     |
| Header, footer nav      | 9.5–10 | regular | 0.14–0.2em, uppercase |
| Chart annotation        | 9      | regular | 0.14em, uppercase     |


All numeric readings use tabular figures — `.monospacedDigit()` — everywhere,
without exception. Long text takes `text-wrap: pretty`; in SwiftUI, allow two
lines and avoid truncation.

---

## 11. Files

- `prototype/Thermal - 2a Complete.dc.html` — the full interactive design.
Open directly in a browser; the controls below the window reach every screen
and state described here.
- `prototype/support.js` — runtime the prototype needs. Keep it alongside.


# Thermal

**Know why your Mac is hot, right from the menu bar.**

Thermal is a temperature monitor for Apple Silicon Macs (M1–M4). It reads every
thermal sensor your machine exposes and turns ~250 cryptic channels into a
handful of things a normal person understands: how hot the processor, graphics,
memory, battery and chassis are right now, how that compares to the last days,
whether macOS is quietly slowing your Mac down, and which apps are generating
the heat.

**[⬇ Download the latest version](https://github.com/igorlourenco/thermal/releases/latest)**

Open the DMG, drag Thermal to Applications, open it once. Done.

<img width="347" height="474" alt="image" src="https://github.com/user-attachments/assets/50fc3824-69ce-45b9-a49c-54cc39f323ca" />


## What you get

- **Live temperatures** in the menu bar: a color chip, a number, or both.
- **History.** Real recorded readings for the last days, with session peaks.
- **Throttle log.** Every time macOS slowed your Mac down, and what caused it.
- **Heat sources.** The apps driving the heat, with a one-click quit.
- **Fans.** Current speed, when your Mac has them.

## Safe and private, by design

- **Everything stays on your Mac.** No account, no analytics, no tracking.
  Readings are stored locally in `~/Library/Application Support/Thermal/` and
  nowhere else.
- **The only network request Thermal ever makes** is checking this page for a
  new version, and you can turn that off in Settings.
- **Read-only.** Thermal only *reads* sensors. It never touches your fans,
  never overrides your Mac's own thermal management, and can't change how your
  machine behaves.
- **No admin password, ever.** No sudo, no kernel extensions, no system
  modifications.
- **Signed and notarized** with an Apple Developer ID, so macOS itself has
  scanned and approved every release you download here.

## Updating

Thermal updates itself: when a new version is out, it offers it in-app and the
update takes a few seconds. Your recorded history is kept. You can also check
manually in **Settings → Check now**, or turn automatic updates off entirely.

## Removing

Quit Thermal and drag it from Applications to the Trash. If you also want the
recorded readings gone, delete `~/Library/Application Support/Thermal/`.

## Requirements

- Apple Silicon Mac (M1, M2, M3 or M4, any variant)
- macOS 13 Ventura or newer

## Build from source

Thermal is a plain Swift package. Xcode 15 or newer (Swift 5.9) on an Apple
Silicon Mac is all you need:

```bash
git clone https://github.com/igorlourenco/thermal.git
cd thermal
swift run thermal            # menu bar app
swift run thermal --watch    # live terminal dashboard instead
scripts/bundle.sh            # dist/Thermal.app, ad-hoc signed for local use
```

Architecture, sensor mapping notes and the diagnostic `--raw` mode are in
[DEVELOPMENT.md](DEVELOPMENT.md). The signing, notarization and update feed
steps are in [RELEASING.md](RELEASING.md).

The source is published so you can see exactly what runs on your Mac. Sensor
access goes through a private Apple API (`IOHIDEventSystemClient`), which is
why Thermal ships as a notarized direct download and not through the App Store.

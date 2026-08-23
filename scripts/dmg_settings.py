# dmgbuild settings — the Finder view state from installer.md §2.
# dmgbuild writes the .DS_Store directly (no Finder scripting, so it runs
# headless and in CI). Invoked by scripts/dmg.sh.

app = defines.get("app", "dist/Thermal.app")  # noqa: F821

files = [(app, "Thermal.app")]
symlinks = {"Applications": "/Applications"}

# Volume
icon = "Resources/VolumeIcon.icns"
filesystem = "HFS+"
format = "UDZO"
compression_level = 9

# Window: 660 x 420 of content, icon view, all chrome hidden.
# window_rect height includes the ~28pt title bar; +28 so the full 420px of
# background art is visible (otherwise Finder clips the closing lines).
background = "Resources/dmg/background.tiff"
default_view = "icon-view"
window_rect = ((200, 120), (660, 448))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

# Icons: 128px, labels below, fixed centres, nothing auto-arranged.
icon_size = 128
text_size = 12
arrange_by = None
show_icon_preview = False
icon_locations = {
    "Thermal.app": (197, 206),
    "Applications": (463, 206),
}

# dmgbuild settings for Remembrance-<version>.dmg (see dmg/make-dmg.sh).
# -D app=<path to Remembrance.app> -D background=<tiff> -D icon=<volume .icns>
import os.path

application = defines["app"]
appname = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")
badge_icon = None

background = defines["background"]
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {
    appname: (170, 190),
    "Applications": (490, 190),
}
hide_extensions = [appname]

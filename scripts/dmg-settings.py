# dmgbuild settings, see https://dmgbuild.readthedocs.io
import os.path

app = defines["app"]  # noqa: F821
appname = os.path.basename(app)

format = "ULFO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
badge_icon = os.path.join(app, "Contents/Resources/AppIcon.icns")

background = defines["background"]  # noqa: F821
window_rect = ((200, 160), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
# match the wells drawn by scripts/render-art.swift
icon_locations = {appname: (165, 200), "Applications": (495, 200)}

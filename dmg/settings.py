# dmgbuild 설정. build.sh가 -D app=... -D background=... 로 경로를 넘긴다.
# 아이콘 위치(Finder 좌표, 위에서부터)는 make-background.swift의 화살표 위치와 맞춰야 한다.

files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
icon_locations = {"AppMixer.app": (150, 150), "Applications": (390, 150)}

background = defines["background"]
window_rect = ((200, 200), (540, 360))
default_view = "icon-view"
icon_size = 96
text_size = 13

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

format = "UDZO"

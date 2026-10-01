#!/bin/zsh
# Rebuilds AppIcon.icns (only needed if the icon design changes).
set -e
mkdir -p "${0:A:h}/.tmp_icon"; cp "${0:A:h}/make_icon.swift" "${0:A:h}/.tmp_icon/main.swift"
HERE="${0:A:h}"
swiftc -O -swift-version 5 "$HERE/GrainEngine.swift" "$HERE/ImageFiles.swift" "$HERE/.tmp_icon/main.swift" -o "$HERE/.build_icon" 2>&1 | grep -E "error" || true
"$HERE/.build_icon" "$HERE"
iconutil -c icns "$HERE/AppIcon.iconset" -o "$HERE/AppIcon.icns"
rm -rf "$HERE/.tmp_icon" "$HERE/AppIcon.iconset" "$HERE/.build_icon"
echo "AppIcon.icns ready"

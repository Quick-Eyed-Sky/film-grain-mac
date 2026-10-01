#!/bin/zsh
# Builds "Film Grain.app" next to this folder from the .swift files.
# Needs only the Xcode Command Line Tools (swiftc). Nothing else is installed.
#
#   cd film-grain-mac/source && ./build_app.sh     (the folder that contains this script)

set -e
if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc was not found. Install Apple's command line tools first (a few minutes, no Apple ID needed):"
  echo "    xcode-select --install"
  echo "then run this script again."
  exit 1
fi
HERE="${0:A:h}"
ROOT="${HERE:h}"
APP="$ROOT/Film Grain.app"
BUILD="$HERE/.build"

# One version number, defined once, in GrainEngine.swift.
VERSION=$(grep -E 'static let version = ' "$HERE/GrainEngine.swift" | sed -E 's/.*"([^"]+)".*/\1/')
echo "Building Film Grain $VERSION ..."

rm -rf "$BUILD"; mkdir -p "$BUILD"
swiftc -O -swift-version 5 -parse-as-library \
  -target arm64-apple-macos14.0 \
  "$HERE/GrainEngine.swift" "$HERE/ImageFiles.swift" "$HERE/FilmGrainApp.swift" \
  -o "$BUILD/FilmGrain"

# Shown in the "About Film Grain" window (a GPL program must show its legal notice).
# The source link is added only for a public release:  SOURCE_URL="https://github.com/..." ./build_app.sh
COPYRIGHT="Copyright (C) 2026 Jean-Pascal (Quick-Eyed Sky). Derived from the FilmGrain node by EllangoK (GPL-3.0). Free software under the GPL-3.0, with NO WARRANTY."
if [ -n "${SOURCE_URL:-}" ]; then COPYRIGHT="$COPYRIGHT Source code: $SOURCE_URL"; fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/FilmGrain" "$APP/Contents/MacOS/FilmGrain"
[ -f "$HERE/AppIcon.icns" ] && cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Film Grain</string>
  <key>CFBundleDisplayName</key><string>Film Grain</string>
  <key>CFBundleIdentifier</key><string>com.jpm.filmgrain</string>
  <key>CFBundleExecutable</key><string>FilmGrain</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>$COPYRIGHT</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Picture</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.image</string><string>public.folder</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 && echo "Signed (ad hoc)."
echo "Done: $APP"

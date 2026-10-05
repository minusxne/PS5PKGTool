#!/usr/bin/env bash
# Packages a build of the Linux edition as an AppImage with linuxdeploy and its Qt plugin.
# Usage: packaging/appimage.sh <qt-build-dir> <dist-dir>   (normally called by build-linux.sh --appimage)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QT_BUILD="${1:?qt build directory}"
DIST="${2:?dist directory}"
TOOLS="$ROOT/build/tools"
APPDIR="$ROOT/build/AppDir"

fetch() {
    local name="$1" url="$2"
    if [[ ! -x "$TOOLS/$name" ]]; then
        mkdir -p "$TOOLS"
        echo "Downloading $name"
        curl -fsSL -o "$TOOLS/$name" "$url"
        chmod +x "$TOOLS/$name"
    fi
}
fetch linuxdeploy-x86_64.AppImage \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch linuxdeploy-plugin-qt-x86_64.AppImage \
    https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage

rm -rf "$APPDIR"
DESTDIR="$APPDIR" cmake --install "$QT_BUILD" --prefix /usr >/dev/null
mkdir -p "$APPDIR/usr/lib/ps5pkgtool"
cp -a "$DIST/lib/ps5pkgtool/bridge" "$APPDIR/usr/lib/ps5pkgtool/bridge"

export QML_SOURCES_PATHS="$ROOT/PS5PKGTool.Qt/qml"
export EXTRA_QT_MODULES="svg"
export EXTRA_PLATFORM_PLUGINS="libqwayland-egl.so;libqwayland-generic.so"
export OUTPUT="$ROOT/PS5_PKG_Tool-x86_64.AppImage"
# The .NET engine is self-contained; keep linuxdeploy from rewriting its native libraries.
export NO_STRIP=1

cd "$ROOT/build"
"$TOOLS/linuxdeploy-x86_64.AppImage" --appimage-extract-and-run \
    --appdir "$APPDIR" \
    --executable "$APPDIR/usr/bin/ps5pkgtool" \
    --desktop-file "$APPDIR/usr/share/applications/ps5pkgtool.desktop" \
    --icon-file "$ROOT/PS5PKGTool.Qt/resources/app/ps5pkgtool-256.png" \
    --icon-filename ps5pkgtool \
    --plugin qt \
    --output appimage
echo "AppImage: $OUTPUT"

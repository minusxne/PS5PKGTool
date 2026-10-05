#!/usr/bin/env bash
# Packages a build of the Linux edition as an AppImage.
# Usage: packaging/appimage.sh <qt-build-dir> <dist-dir>   (normally called by build-linux.sh --appimage)
#
# linuxdeploy (with its Qt plugin) bundles the Qt app and its libraries. The .NET engine is added
# afterwards and packed with appimagetool, because it is already self-contained: letting
# linuxdeploy scan it makes it chase optional runtime dependencies such as LTTng
# (liblttng-ust.so.0, used only by libcoreclrtraceptprovider.so) and fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QT_BUILD="${1:?qt build directory}"
DIST="${2:?dist directory}"
TOOLS="$ROOT/build/tools"
APPDIR="$ROOT/build/AppDir"
OUTPUT="${OUTPUT:-$ROOT/PS5_PKG_Tool-x86_64.AppImage}"

fetch() {
    local name="$1" url="$2"
    if [[ ! -x "$TOOLS/$name" ]]; then
        mkdir -p "$TOOLS"
        echo "Downloading $name"
        curl -fsSL -o "$TOOLS/$name.part" "$url"
        chmod +x "$TOOLS/$name.part"
        mv "$TOOLS/$name.part" "$TOOLS/$name"
    fi
}
fetch linuxdeploy-x86_64.AppImage \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch linuxdeploy-plugin-qt-x86_64.AppImage \
    https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage
fetch appimagetool-x86_64.AppImage \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage

# The Qt plugin locates Qt through qmake; prefer the Qt the app was built against.
if [[ -z "${QMAKE:-}" ]]; then
    qt_dir="$(sed -n 's/^Qt6_DIR:PATH=//p' "$QT_BUILD/CMakeCache.txt" 2>/dev/null || true)"
    for candidate in "$qt_dir/../../../bin/qmake" "$qt_dir/../../../bin/qmake6" \
                     "$(command -v qmake6 2>/dev/null || true)" /usr/lib/qt6/bin/qmake "$(command -v qmake 2>/dev/null || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" -query QT_VERSION 2>/dev/null | grep -q '^6\.'; then
            QMAKE="$(readlink -f "$candidate")"
            break
        fi
    done
fi
[[ -n "${QMAKE:-}" ]] || { echo "error: could not find qmake for Qt 6; set QMAKE=/path/to/qmake" >&2; exit 1; }
export QMAKE
echo "Using Qt $("$QMAKE" -query QT_VERSION) from $("$QMAKE" -query QT_INSTALL_PREFIX)"

rm -rf "$APPDIR"
DESTDIR="$APPDIR" cmake --install "$QT_BUILD" --prefix /usr >/dev/null

# 1. The Qt app: libraries, Qt plugins, QML modules, AppRun, desktop file and icon.
#    linuxdeploy-plugin-qt misses plugins the app only reaches through QML or at runtime: the
#    Wayland client buffer integrations (needed for OpenGL on Wayland), the multimedia backend
#    (audio/video previews) and the XDG desktop portal theme (native file dialogs). They are copied
#    in first and get their dependencies deployed with everything else.
QT_PLUGINS="$("$QMAKE" -query QT_INSTALL_PLUGINS)"
EXTRA_DEPS=()
for item in wayland-graphics-integration-client multimedia platformthemes/libqxdgdesktopportal.so; do
    if [[ -e "$QT_PLUGINS/$item" ]]; then
        mkdir -p "$APPDIR/usr/plugins/$(dirname "$item")"
        cp -a "$QT_PLUGINS/$item" "$APPDIR/usr/plugins/$(dirname "$item")/"
        while IFS= read -r library; do EXTRA_DEPS+=(--deploy-deps-only "$library"); done \
            < <(find "$APPDIR/usr/plugins/$item" -name '*.so')
    else
        echo "warning: Qt plugin $item not found in $QT_PLUGINS; it will be missing from the AppImage" >&2
    fi
done
export QML_SOURCES_PATHS="$ROOT/PS5PKGTool.Qt/qml"
export EXTRA_QT_MODULES="svg;dbus"
export EXTRA_PLATFORM_PLUGINS="libqwayland-egl.so;libqwayland-generic.so"
export NO_STRIP=1
"$TOOLS/linuxdeploy-x86_64.AppImage" --appimage-extract-and-run \
    --appdir "$APPDIR" \
    --executable "$APPDIR/usr/bin/ps5pkgtool" \
    --desktop-file "$APPDIR/usr/share/applications/ps5pkgtool.desktop" \
    --icon-file "$ROOT/PS5PKGTool.Qt/resources/app/ps5pkgtool-256.png" \
    --icon-filename ps5pkgtool \
    "${EXTRA_DEPS[@]}" \
    --plugin qt

# 2. The self-contained engine, copied in as-is. The LTTng trace provider is optional for .NET and
#    only drags in a library most systems do not have.
mkdir -p "$APPDIR/usr/lib/ps5pkgtool"
cp -a "$DIST/lib/ps5pkgtool/bridge" "$APPDIR/usr/lib/ps5pkgtool/bridge"
rm -f "$APPDIR/usr/lib/ps5pkgtool/bridge/libcoreclrtraceptprovider.so"

# 3. Pack.
rm -f "$OUTPUT"
ARCH=x86_64 "$TOOLS/appimagetool-x86_64.AppImage" --appimage-extract-and-run --no-appstream "$APPDIR" "$OUTPUT"
echo "AppImage: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"

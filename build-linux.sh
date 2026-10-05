#!/usr/bin/env bash
# Builds the Linux (Qt) edition of PS5 PKG Tool.
#
#   ./build-linux.sh                     build into ./dist (run ./dist/bin/ps5pkgtool)
#   ./build-linux.sh --install ~/.local  build, then install under a prefix
#   ./build-linux.sh --appimage          build, then package dist/ as an AppImage
#
# Options:
#   --install PREFIX   install to PREFIX (use sudo for /usr/local or /usr)
#   --appimage         create PS5_PKG_Tool-x86_64.AppImage (downloads linuxdeploy if needed)
#   --debug            debug build of the Qt app
#   --qt PATH          Qt 6 prefix if it is not found automatically (e.g. ~/Qt/6.8.2/gcc_64)
#   --jobs N           parallel build jobs (default: number of CPUs)
#   --clean            remove build/ and dist/ first
#   -h, --help         show this help
#
# Environment: CMAKE_ARGS is passed to CMake as-is; DOTNET overrides the dotnet executable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
CONFIG=Release
PREFIX=""
APPIMAGE=0
QT_PREFIX=""
JOBS="$(nproc 2>/dev/null || echo 4)"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install) PREFIX="${2:?--install needs a prefix}"; shift 2 ;;
        --appimage) APPIMAGE=1; shift ;;
        --debug) CONFIG=Debug; shift ;;
        --qt) QT_PREFIX="${2:?--qt needs a path}"; shift 2 ;;
        --jobs) JOBS="${2:?--jobs needs a number}"; shift 2 ;;
        --clean) rm -rf "$BUILD" "$DIST"; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

# ------------------------------------------------------------------ prerequisites

DOTNET="${DOTNET:-}"
if [[ -z "$DOTNET" ]]; then
    if command -v dotnet >/dev/null 2>&1; then DOTNET="$(command -v dotnet)"
    elif [[ -x "$HOME/.dotnet/dotnet" ]]; then DOTNET="$HOME/.dotnet/dotnet"; export DOTNET_ROOT="$HOME/.dotnet"
    else die ".NET 10 SDK not found. Install it from your distribution or with:
    curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0"
    fi
fi
"$DOTNET" --list-sdks 2>/dev/null | grep -q '^10\.' || die "the .NET 10 SDK is required (found: $("$DOTNET" --list-sdks 2>/dev/null | tr '\n' ' '))"
command -v cmake >/dev/null 2>&1 || die "cmake not found (Debian/Ubuntu: sudo apt install cmake ninja-build)"
GENERATOR=()
command -v ninja >/dev/null 2>&1 && GENERATOR=(-G Ninja)

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

# ------------------------------------------------------------------ engine (.NET bridge)

say "Building the engine (.NET bridge, self-contained linux-x64)"
rm -rf "$DIST/lib/ps5pkgtool/bridge"
"$DOTNET" publish "$ROOT/PS5PKGTool.Bridge/PS5PKGTool.Bridge.csproj" \
    -c Release -r linux-x64 --self-contained true \
    -p:PublishTrimmed=false -p:DebugType=none \
    -o "$DIST/lib/ps5pkgtool/bridge" --nologo -v quiet
[[ -x "$DIST/lib/ps5pkgtool/bridge/ps5pkgtool-bridge" ]] || die "the engine was not produced"
if ! ls "$DIST/lib/ps5pkgtool/bridge/LibProsperoPkg12/runtimes/linux-x64/native/"* >/dev/null 2>&1; then
    warn "the Magick.NET native library is missing; the LibProsperoPkg builder will fall back to ProsperoPkgTool"
fi

# ------------------------------------------------------------------ Qt app

say "Building the Qt app ($CONFIG)"
CMAKE_EXTRA=()
[[ -n "$QT_PREFIX" ]] && CMAKE_EXTRA+=("-DCMAKE_PREFIX_PATH=$QT_PREFIX")
# shellcheck disable=SC2206
[[ -n "${CMAKE_ARGS:-}" ]] && CMAKE_EXTRA+=($CMAKE_ARGS)
cmake -S "$ROOT/PS5PKGTool.Qt" -B "$BUILD/qt" "${GENERATOR[@]}" \
    -DCMAKE_BUILD_TYPE="$CONFIG" -DCMAKE_INSTALL_PREFIX="$DIST" \
    -DPS5PKGTOOL_DEV_BRIDGE="$DIST/lib/ps5pkgtool/bridge/ps5pkgtool-bridge" \
    "${CMAKE_EXTRA[@]}" >/dev/null \
    || die "CMake could not configure the Qt app. Install the Qt 6 development packages (see README) or pass --qt PATH."
cmake --build "$BUILD/qt" --parallel "$JOBS"
cmake --install "$BUILD/qt" >/dev/null

say "Built: $DIST/bin/ps5pkgtool"

# ------------------------------------------------------------------ install

if [[ -n "$PREFIX" ]]; then
    say "Installing to $PREFIX"
    cmake --install "$BUILD/qt" --prefix "$PREFIX"
    mkdir -p "$PREFIX/lib/ps5pkgtool"
    rm -rf "$PREFIX/lib/ps5pkgtool/bridge"
    cp -a "$DIST/lib/ps5pkgtool/bridge" "$PREFIX/lib/ps5pkgtool/bridge"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$PREFIX/share/applications" 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true
    say "Installed. Run: $PREFIX/bin/ps5pkgtool"
fi

# ------------------------------------------------------------------ AppImage

if [[ "$APPIMAGE" == 1 ]]; then
    "$ROOT/packaging/appimage.sh" "$BUILD/qt" "$DIST"
fi

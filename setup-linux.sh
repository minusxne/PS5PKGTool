#!/usr/bin/env bash
# One-command setup for the Linux edition of PS5 PKG Tool:
#   1. installs the build dependencies with your package manager (asks first, needs sudo),
#   2. installs the .NET 10 SDK for your user if it is missing (no sudo),
#   3. builds the app (./build-linux.sh),
#   4. installs it for your user (~/.local) so it shows up in your application menu.
#
# Usage:
#   ./setup-linux.sh                 interactive: asks before installing anything
#   ./setup-linux.sh --yes           no questions (still asks for your sudo password)
#   ./setup-linux.sh --no-deps       skip step 1 (you installed the packages yourself)
#   ./setup-linux.sh --no-install    build only; run ./dist/bin/ps5pkgtool
#   ./setup-linux.sh --prefix DIR    install somewhere else (default ~/.local; use sudo for /usr/local)
#   ./setup-linux.sh --appimage      also produce PS5_PKG_Tool-x86_64.AppImage
#   ./setup-linux.sh --uninstall     remove an installation made by this script
#
# Supported package managers: apt (Debian, Ubuntu, Mint, Pop!_OS), dnf (Fedora), pacman (Arch,
# Manjaro, EndeavourOS) and zypper (openSUSE). Elsewhere, install the packages listed in the README
# and run with --no-deps.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YES=0
DEPS=1
INSTALL=1
PREFIX="$HOME/.local"
APPIMAGE=0
UNINSTALL=0

say()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

ask() {
    [[ "$YES" == 1 ]] && return 0
    local reply
    read -r -p "    $1 [Y/n] " reply || reply=n
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes) YES=1; shift ;;
        --no-deps) DEPS=0; shift ;;
        --no-install) INSTALL=0; shift ;;
        --prefix) PREFIX="${2:?--prefix needs a directory}"; shift 2 ;;
        --appimage) APPIMAGE=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

[[ "$(uname -s)" == Linux ]] || die "this script is for Linux"
[[ "$(uname -m)" == x86_64 ]] || warn "only x86_64 is tested; the engine is published for linux-x64"

# ------------------------------------------------------------------ uninstall

if [[ "$UNINSTALL" == 1 ]]; then
    say "Removing PS5 PKG Tool from $PREFIX"
    rm -fv "$PREFIX/bin/ps5pkgtool" \
           "$PREFIX/share/applications/ps5pkgtool.desktop" \
           "$PREFIX/share/metainfo/io.github.pearlxcore.PS5PkgTool.metainfo.xml"
    rm -fv "$PREFIX"/share/icons/hicolor/*/apps/ps5pkgtool.png
    rm -rf "$PREFIX/lib/ps5pkgtool" && info "removed $PREFIX/lib/ps5pkgtool"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$PREFIX/share/applications" 2>/dev/null || true
    info "Your settings and library cache in ~/.local/share/PS5PKGTool and ~/.cache/PS5PKGTool were kept."
    exit 0
fi

# ------------------------------------------------------------------ 1. system packages

detect_manager() {
    for manager in apt-get dnf pacman zypper; do
        command -v "$manager" >/dev/null 2>&1 && { echo "$manager"; return; }
    done
    echo none
}

packages_for() {
    case "$1" in
        apt-get) echo build-essential cmake ninja-build curl libgl-dev \
            qt6-base-dev qt6-declarative-dev qt6-svg-dev qt6-multimedia-dev \
            qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
            qml6-module-qtquick-window qml6-module-qtquick-dialogs qml6-module-qtquick-effects \
            qml6-module-qtquick-shapes qml6-module-qtquick-templates qml6-module-qtqml-workerscript \
            qml6-module-qtmultimedia qml6-module-qtcore ;;
        dnf) echo gcc-c++ make cmake ninja-build curl mesa-libGL-devel \
            qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtsvg-devel qt6-qtmultimedia-devel ;;
        pacman) echo base-devel cmake ninja curl qt6-base qt6-declarative qt6-svg qt6-multimedia ;;
        zypper) echo gcc-c++ make cmake ninja curl Mesa-libGL-devel \
            qt6-base-devel qt6-declarative-devel qt6-svg-devel qt6-multimedia-devel \
            qt6-quickcontrols2-devel qt6-shadertools ;;
    esac
}

if [[ "$DEPS" == 1 ]]; then
    say "Step 1/4: build dependencies"
    MANAGER="$(detect_manager)"
    if [[ "$MANAGER" == none ]]; then
        warn "no supported package manager found. Install CMake, a C++ compiler and Qt 6.5+ (Base, Declarative, SVG,"
        warn "Multimedia) yourself, then run: $0 --no-deps"
        exit 1
    fi
    PACKAGES=($(packages_for "$MANAGER"))
    info "Package manager: $MANAGER"
    info "Packages: ${PACKAGES[*]}"
    if ask "Install or update these packages now (uses sudo)?"; then
        SUDO=""
        [[ "$(id -u)" != 0 ]] && SUDO="sudo"
        case "$MANAGER" in
            apt-get) $SUDO apt-get update && $SUDO apt-get install -y "${PACKAGES[@]}" ;;
            dnf) $SUDO dnf install -y "${PACKAGES[@]}" ;;
            pacman) $SUDO pacman -S --needed --noconfirm "${PACKAGES[@]}" ;;
            zypper) $SUDO zypper --non-interactive install "${PACKAGES[@]}" ;;
        esac
    else
        info "Skipped. The build will fail if something is missing."
    fi
else
    say "Step 1/4: build dependencies (skipped)"
fi

# ------------------------------------------------------------------ 2. .NET SDK

say "Step 2/4: .NET 10 SDK"
DOTNET=""
for candidate in "$(command -v dotnet 2>/dev/null || true)" "$HOME/.dotnet/dotnet"; do
    if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" --list-sdks 2>/dev/null | grep -q '^10\.'; then
        DOTNET="$candidate"
        break
    fi
done
if [[ -n "$DOTNET" ]]; then
    info "Found: $DOTNET ($("$DOTNET" --version))"
else
    info "Not found. It is only needed to build; the finished app does not need .NET."
    if ask "Install the .NET 10 SDK for your user into ~/.dotnet (no sudo)?"; then
        command -v curl >/dev/null 2>&1 || die "curl is required to download the .NET installer"
        installer="$(mktemp)"
        curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$installer"
        bash "$installer" --channel 10.0 --install-dir "$HOME/.dotnet"
        rm -f "$installer"
        DOTNET="$HOME/.dotnet/dotnet"
    else
        die "the .NET 10 SDK is required to build"
    fi
fi
export DOTNET
[[ "$DOTNET" == "$HOME/.dotnet/dotnet" ]] && export DOTNET_ROOT="$HOME/.dotnet"

# ------------------------------------------------------------------ 3. build

say "Step 3/4: building"
BUILD_ARGS=()
[[ "$APPIMAGE" == 1 ]] && BUILD_ARGS+=(--appimage)
"$ROOT/build-linux.sh" "${BUILD_ARGS[@]}"

# ------------------------------------------------------------------ 4. install

if [[ "$INSTALL" == 1 ]]; then
    say "Step 4/4: installing to $PREFIX"
    if ask "Install PS5 PKG Tool to $PREFIX (adds it to your application menu)?"; then
        if [[ -w "$PREFIX" || ( ! -e "$PREFIX" && -w "$(dirname "$PREFIX")" ) ]]; then
            mkdir -p "$PREFIX"
            cmake --install "$ROOT/build/qt" --prefix "$PREFIX" >/dev/null
            mkdir -p "$PREFIX/lib/ps5pkgtool"
            rm -rf "$PREFIX/lib/ps5pkgtool/bridge"
            cp -a "$ROOT/dist/lib/ps5pkgtool/bridge" "$PREFIX/lib/ps5pkgtool/bridge"
        else
            sudo cmake --install "$ROOT/build/qt" --prefix "$PREFIX" >/dev/null
            sudo mkdir -p "$PREFIX/lib/ps5pkgtool"
            sudo rm -rf "$PREFIX/lib/ps5pkgtool/bridge"
            sudo cp -a "$ROOT/dist/lib/ps5pkgtool/bridge" "$PREFIX/lib/ps5pkgtool/bridge"
        fi
        command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$PREFIX/share/applications" 2>/dev/null || true
        command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true
        say "Done!"
        info "Start it from your application menu (\"PS5 PKG Tool\") or run: $PREFIX/bin/ps5pkgtool"
        case ":$PATH:" in
            *":$PREFIX/bin:"*) ;;
            *) info "Tip: add $PREFIX/bin to your PATH to run \"ps5pkgtool\" from a terminal." ;;
        esac
        info "Remove it later with: $0 --uninstall$( [[ "$PREFIX" != "$HOME/.local" ]] && printf ' --prefix %q' "$PREFIX")"
        exit 0
    fi
fi

say "Done!"
info "Run it from the build folder: $ROOT/dist/bin/ps5pkgtool"
info "Try it without real games:    $ROOT/dist/bin/ps5pkgtool --demo"

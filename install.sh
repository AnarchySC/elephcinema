#!/bin/bash
# ELEPHCINEMA Installer
#
# Copyright (C) 2026 AnarchyGames.org
# SPDX-License-Identifier: GPL-3.0-or-later

set -e

PREFIX="${1:-/opt/elephcinema}"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_DIR="$HOME/.config/elephcinema"
DATA_DIR="$HOME/.local/share/elephcinema"
UDEV_RULE="/etc/udev/rules.d/99-elephcinema.rules"
CURRENT_USER="$(whoami)"

echo "=== ELEPHCINEMA Installer ==="
echo ""
echo "Install prefix: $PREFIX"
echo "Config dir:     $CONFIG_DIR"
echo "Data dir:       $DATA_DIR"
echo ""

# === DEPENDENCY CHECK ===
echo "Checking dependencies..."
MISSING=()
OPTIONAL_MISSING=()

for cmd in makemkvcon HandBrakeCLI ffprobe yad notify-send eject blockdev bc; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done

for cmd in paplay udisksctl; do
    if ! command -v "$cmd" &>/dev/null; then
        OPTIONAL_MISSING+=("$cmd")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo "ERROR: Missing required dependencies:"
    for cmd in "${MISSING[@]}"; do
        case "$cmd" in
            makemkvcon)    echo "  - makemkvcon    (MakeMKV — https://www.makemkv.com/)" ;;
            HandBrakeCLI)  echo "  - HandBrakeCLI  (sudo apt install handbrake-cli)" ;;
            ffprobe)       echo "  - ffprobe       (sudo apt install ffmpeg)" ;;
            yad)           echo "  - yad           (sudo apt install yad)" ;;
            notify-send)   echo "  - notify-send   (sudo apt install libnotify-bin)" ;;
            eject)         echo "  - eject         (sudo apt install eject)" ;;
            blockdev)      echo "  - blockdev      (sudo apt install util-linux)" ;;
            bc)            echo "  - bc            (sudo apt install bc)" ;;
        esac
    done
    echo ""
    echo "Install missing dependencies and try again."
    exit 1
fi

echo "All required dependencies found."

if [ ${#OPTIONAL_MISSING[@]} -gt 0 ]; then
    echo ""
    echo "Optional dependencies not found (non-critical):"
    for cmd in "${OPTIONAL_MISSING[@]}"; do
        case "$cmd" in
            paplay)     echo "  - paplay     — disc-detected sound alert (sudo apt install pulseaudio-utils)" ;;
            udisksctl)  echo "  - udisksctl  — auto-unmount discs (sudo apt install udisks2)" ;;
        esac
    done
fi

echo ""

# === INSTALL SCRIPTS ===
echo "Installing scripts to $PREFIX/scripts/ ..."
sudo mkdir -p "$PREFIX/scripts"
sudo cp "$SCRIPT_DIR"/scripts/* "$PREFIX/scripts/"
sudo chmod +x "$PREFIX"/scripts/*.sh "$PREFIX"/scripts/*.py

echo "Installed."

# === CONFIG ===
if [ ! -f "$CONFIG_DIR/config" ]; then
    echo "Creating config at $CONFIG_DIR/config ..."
    mkdir -p "$CONFIG_DIR"
    cp "$SCRIPT_DIR/config.example" "$CONFIG_DIR/config"
    echo "Edit $CONFIG_DIR/config to set your output directories."
else
    echo "Config already exists at $CONFIG_DIR/config — skipping."
fi

# === DATA DIR ===
mkdir -p "$DATA_DIR"

# === UDEV RULE ===
echo ""
echo "--- udev rule ---"
RULE=$(sed "s|__USER__|$CURRENT_USER|g; s|__INSTALL_PREFIX__|$PREFIX|g" "$SCRIPT_DIR/udev/99-elephcinema.rules.template")
echo "$RULE"
echo "-----------------"
echo ""

read -rp "Install udev rule to $UDEV_RULE? (auto-rip on disc insert) [y/N] " INSTALL_UDEV
if [[ "$INSTALL_UDEV" =~ ^[Yy]$ ]]; then
    echo "$RULE" | sudo tee "$UDEV_RULE" > /dev/null
    sudo udevadm control --reload-rules
    echo "udev rule installed and reloaded."
else
    echo "Skipped udev rule. You can install it manually later."
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Usage:"
echo "  Manual rip:  $PREFIX/scripts/elephcinema.sh /dev/sr0"
echo "  Force TV:    $PREFIX/scripts/elephcinema.sh /dev/sr0 --force-tv"
echo "  Tray icon:   $PREFIX/scripts/elephcinema-tray.py"
echo "  Notifier:    $PREFIX/scripts/elephcinema-notify.sh"
echo ""

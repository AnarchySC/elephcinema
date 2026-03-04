#!/bin/bash
# ELEPHCINEMA Uninstaller
#
# Copyright (C) 2026 AnarchyGames.org
# SPDX-License-Identifier: GPL-3.0-or-later

PREFIX="${1:-/opt/elephcinema}"
UDEV_RULE="/etc/udev/rules.d/99-elephcinema.rules"

echo "=== ELEPHCINEMA Uninstaller ==="
echo ""
echo "This will remove:"
echo "  - Scripts at $PREFIX/"
echo "  - udev rule at $UDEV_RULE (if present)"
echo ""
echo "This will NOT remove:"
echo "  - Config at ~/.config/elephcinema/"
echo "  - Logs at ~/.local/share/elephcinema/"
echo "  - Your ripped media files"
echo ""

read -rp "Proceed? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Remove scripts
if [ -d "$PREFIX" ]; then
    sudo rm -rf "$PREFIX"
    echo "Removed $PREFIX"
fi

# Remove udev rule
if [ -f "$UDEV_RULE" ]; then
    sudo rm -f "$UDEV_RULE"
    sudo udevadm control --reload-rules
    echo "Removed udev rule and reloaded."
fi

# Clean up temp files
rm -f /tmp/elephcinema-status /tmp/elephcinema.lock /tmp/elephcinema-dispatch.lock /tmp/elephcinema-cooldown

echo ""
echo "Uninstall complete."
echo "Config and logs preserved at ~/.config/elephcinema/ and ~/.local/share/elephcinema/"

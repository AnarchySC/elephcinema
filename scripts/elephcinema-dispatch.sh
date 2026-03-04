#!/bin/bash
# ELEPHCINEMA — Disc dispatcher
# Waits for disc, then hands off to elephcinema.sh.
# Called by udev rule. Does NOT touch MakeMKV — lets the rip script
# handle all MakeMKV calls so the drive is only opened once.
#
# Copyright (C) 2026 AnarchyGames.org
# SPDX-License-Identifier: GPL-3.0-or-later

DEVICE="${1:-auto}"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

source "$SCRIPT_DIR/elephcinema-common.sh"

# === COOLDOWN CHECK ===
# Ignore udev events within 60 seconds of last completed run (eject re-triggers)
if [ -f "$ELEPHCINEMA_COOLDOWN_FILE" ]; then
    LAST_DONE=$(cat "$ELEPHCINEMA_COOLDOWN_FILE" 2>/dev/null)
    NOW=$(date +%s)
    ELAPSED=$(( NOW - LAST_DONE ))
    if [ "$ELAPSED" -lt 60 ]; then
        log "Dispatcher: cooldown active (${ELAPSED}s since last run), ignoring"
        exit 0
    fi
fi

# === DISPATCH LOCK ===
exec 201>"$ELEPHCINEMA_DISPATCH_LOCK"
if ! flock -n 201; then
    log "Another dispatch instance already running, exiting"
    exit 0
fi
echo $$ >&201

# === STARTUP DELAY ===
sleep 5

# === DEVICE DETECTION ===
if [[ "$DEVICE" =~ ^/dev/ ]]; then
    USE_DEV_PATH="$DEVICE"
elif [ "$DEVICE" = "auto" ]; then
    for sr in /dev/sr{0..9}; do
        if [ -e "$sr" ]; then
            USE_DEV_PATH="$sr"
            break
        fi
    done
fi

if [ -z "$USE_DEV_PATH" ]; then
    log "Dispatcher: no optical device found"
    exit 0
fi

log "Dispatcher: using $USE_DEV_PATH"

unmount_discs

# === WAIT FOR DISC (kernel-level, no MakeMKV) ===
if ! wait_for_disc_ready "$USE_DEV_PATH"; then
    log "Dispatcher: disc not ready after 90 seconds, exiting"
    exit 1
fi

# === HAND OFF TO ELEPHCINEMA ===
log "Dispatcher: launching elephcinema.sh for $USE_DEV_PATH"
ELEPHCINEMA_DISPATCHED=1 "$SCRIPT_DIR/elephcinema.sh" "$USE_DEV_PATH"
EXIT_CODE=$?

# Write cooldown timestamp BEFORE ejecting (blocks re-triggers from eject event)
date +%s > "$ELEPHCINEMA_COOLDOWN_FILE"

# Eject disc while we still hold the dispatch lock
if [ -n "$USE_DEV_PATH" ]; then
    eject "$USE_DEV_PATH" 2>/dev/null
    log "Dispatcher: disc ejected"
fi

log "Dispatcher: child exited with code $EXIT_CODE"
exit $EXIT_CODE

#!/bin/bash
# ELEPHCINEMA — Desktop notification daemon
# Shows desktop notifications for progress updates.
#
# Copyright (C) 2026 AnarchyGames.org
# SPDX-License-Identifier: GPL-3.0-or-later

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/elephcinema-common.sh"

LAST=""
LAST_PCT=0

echo "ELEPHCINEMA notifier running... (Ctrl+C to stop)"

while true; do
    if [ -f "$ELEPHCINEMA_STATUS_FILE" ]; then
        STATUS=$(cat "$ELEPHCINEMA_STATUS_FILE" 2>/dev/null)

        if [ "$STATUS" != "$LAST" ]; then
            case "$STATUS" in
                scanning)
                    notify-send -i media-optical "ELEPHCINEMA" "Scanning disc..." ;;
                rip:*)
                    PCT="${STATUS#rip:}"
                    if [ "$PCT" -ge $((LAST_PCT + 25)) ] || [ "$PCT" -eq 0 ]; then
                        notify-send -i media-optical "ELEPHCINEMA" "Ripping: ${PCT}%"
                        LAST_PCT=$PCT
                    fi
                    ;;
                encode:*)
                    PCT="${STATUS#encode:}"
                    if [ "$PCT" -ge $((LAST_PCT + 25)) ] || [ "$PCT" -eq 0 ]; then
                        notify-send -i video-x-generic "ELEPHCINEMA" "Encoding: ${PCT}%"
                        LAST_PCT=$PCT
                    fi
                    ;;
                done:*)
                    MOVIE="${STATUS#done:}"
                    notify-send -u critical -i emblem-ok-symbolic "ELEPHCINEMA Complete" "$MOVIE"
                    LAST_PCT=0
                    ;;
                error:*)
                    MSG="${STATUS#error:}"
                    notify-send -u critical -i dialog-error "ELEPHCINEMA Error" "$MSG"
                    ;;
            esac
            LAST="$STATUS"
        fi
    fi
    sleep 2
done

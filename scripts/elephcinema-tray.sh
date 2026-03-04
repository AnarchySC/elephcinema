#!/bin/bash
# ELEPHCINEMA — System tray progress indicator (yad-based)
#
# Copyright (C) 2026 AnarchyGames.org
# SPDX-License-Identifier: GPL-3.0-or-later

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/elephcinema-common.sh"

PIPE="/tmp/elephcinema-tray-$$"

cleanup() {
    rm -f "$PIPE"
    exit 0
}
trap cleanup EXIT INT TERM

rm -f "$PIPE"
mkfifo "$PIPE"
exec 3<> "$PIPE"

yad --notification \
    --listen \
    --image="media-optical" \
    --text="ELEPHCINEMA" \
    --menu="View Log!xdg-open ${ELEPHCINEMA_LOG_FILE}|Quit!quit" \
    <&3 &
YAD_PID=$!

update() {
    echo "icon:$1" >&3
    echo "tooltip:$2" >&3
}

update "media-optical" "ELEPHCINEMA: Idle"

LAST=""
while kill -0 $YAD_PID 2>/dev/null; do
    if [ -f "$ELEPHCINEMA_STATUS_FILE" ]; then
        STATUS=$(cat "$ELEPHCINEMA_STATUS_FILE" 2>/dev/null)
        if [ "$STATUS" != "$LAST" ]; then
            case "$STATUS" in
                idle)
                    update "media-optical" "ELEPHCINEMA: Idle" ;;
                scanning)
                    update "media-optical-bd-rom" "ELEPHCINEMA: Scanning disc..." ;;
                rip:*)
                    PCT="${STATUS#rip:}"
                    update "media-optical-bd-rom" "ELEPHCINEMA: Ripping ${PCT}%" ;;
                encode:*)
                    PCT="${STATUS#encode:}"
                    update "video-x-generic" "ELEPHCINEMA: Encoding ${PCT}%" ;;
                done:*)
                    MOVIE="${STATUS#done:}"
                    update "emblem-ok-symbolic" "ELEPHCINEMA: Done - $MOVIE"
                    notify-send "ELEPHCINEMA Complete" "$MOVIE" -i emblem-ok-symbolic ;;
                error:*)
                    MSG="${STATUS#error:}"
                    update "dialog-error" "ELEPHCINEMA: Error - $MSG" ;;
            esac
            LAST="$STATUS"
        fi
    else
        if [ "$LAST" != "idle" ]; then
            update "media-optical" "ELEPHCINEMA: Idle"
            LAST="idle"
        fi
    fi
    sleep 1
done

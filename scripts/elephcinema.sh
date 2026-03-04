#!/bin/bash
# ELEPHCINEMA — Automated Blu-ray/DVD rip and encode pipeline
# Single MakeMKV invocation with auto TV detection, HandBrake encoding,
# and verified copy to output directory.
#
# Supports 4K UHD with LibreDrive-enabled drives (BU40N with DE firmware).
#
# Usage: elephcinema.sh [DEVICE] [--force-tv] [--force-movie]
#   DEVICE: /dev/sr0, disc index, or "auto" (default)
#   --force-tv:    skip Movie/TV dialog, go straight to TV episode flow
#   --force-movie: skip Movie/TV dialog, go straight to movie flow
#
# Copyright (C) 2026 AnarchyGames.org
# SPDX-License-Identifier: GPL-3.0-or-later

# === PARSE ARGUMENTS ===
DEVICE="auto"
FORCE_MODE=""

for arg in "$@"; do
    case "$arg" in
        --force-tv)    FORCE_MODE="tv" ;;
        --force-movie) FORCE_MODE="movie" ;;
        -*)            echo "Unknown option: $arg"; exit 1 ;;
        *)             DEVICE="$arg" ;;
    esac
done

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/elephcinema-common.sh"

TEMP_DIR="$ELEPHCINEMA_TEMP_DIR"
MOVIE_OUTPUT_DIR="$ELEPHCINEMA_MOVIE_DIR"
TV_OUTPUT_BASE="$ELEPHCINEMA_TV_DIR"
LOCK_FILE="$ELEPHCINEMA_LOCK_FILE"
KEEP_TEMP=0
DID_WORK=0

# === CLEANUP TRAP ===
cleanup() {
    if [ "$DID_WORK" -eq 0 ]; then
        return
    fi
    log "Cleaning up..."
    if [ "$KEEP_TEMP" -eq 0 ]; then
        rm -rf "$TEMP_DIR" 2>/dev/null
    else
        log "Keeping temp directory (failures occurred): $TEMP_DIR"
    fi
    rm -f "$ELEPHCINEMA_STATUS_FILE" 2>/dev/null
}
trap cleanup EXIT

# === LOCK MECHANISM ===
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Another ELEPHCINEMA instance is already running, exiting"
    exit 0
fi
echo $$ >&200

# === STARTUP DELAY ===
sleep 5

# === DEVICE DETECTION (blockdev-based, no MakeMKV) ===
if ! detect_device "$DEVICE"; then
    exit 0
fi

unmount_discs

log "=== Starting rip from $MKV_SOURCE ==="
status "ripping"
DID_WORK=1

# === RIP ALL TITLES IN A SINGLE MAKEMKV CALL ===
RIP_DIR="$TEMP_DIR/rip_all"
RIP_MARKER="$RIP_DIR/.rip-complete"

# Check for pre-ripped files ONLY if a completion marker exists.
EXISTING_COUNT=0
if [ -f "$RIP_MARKER" ]; then
    EXISTING_COUNT=$(ls "$RIP_DIR"/*.mkv 2>/dev/null | wc -l)
fi

if [ "$EXISTING_COUNT" -gt 0 ]; then
    log "Found $EXISTING_COUNT pre-ripped MKV files in $RIP_DIR (marker present), skipping rip"
else
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR" "$RIP_DIR"

    if ! check_disk_space "$TEMP_DIR"; then
        status "error:Low disk space"
        exit 1
    fi

    echo ""
    echo "######################################"
    echo "#  STEP 1: RIPPING ALL TITLES       #"
    echo "######################################"
    echo ""

    RIP_START=$(date +%s)
    status "rip:0"

    "$ELEPHCINEMA_MAKEMKVCON" mkv $MKV_SOURCE all "$RIP_DIR" --progress=-stdout -r 2>&1 | while IFS= read -r line; do
        echo "$line"
        if [[ "$line" =~ PRGV:([0-9]+),([0-9]+),([0-9]+) ]]; then
            CURRENT="${BASH_REMATCH[1]}"
            MAX="${BASH_REMATCH[3]}"
            if [ "$MAX" -gt 0 ]; then
                PCT=$((CURRENT * 100 / MAX))
                echo -ne "\r>>> Ripping: ${PCT}%   "
                status "rip:$PCT"
            fi
        fi
    done
    echo ""

    RIP_END=$(date +%s)
    RIP_ELAPSED=$(( RIP_END - RIP_START ))

    # === SANITY CHECKS ===
    MKV_COUNT=$(ls "$RIP_DIR"/*.mkv 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sb "$RIP_DIR" 2>/dev/null | cut -f1)
    TOTAL_SIZE=${TOTAL_SIZE:-0}

    if [ "$MKV_COUNT" -eq 0 ]; then
        log "ERROR: No MKV files produced (rip took ${RIP_ELAPSED}s)"
        status "error:No files ripped"
        exit 1
    fi

    if [ "$RIP_ELAPSED" -lt 120 ] && [ "$TOTAL_SIZE" -lt 1073741824 ]; then
        log "ERROR: Rip completed suspiciously fast (${RIP_ELAPSED}s, $(( TOTAL_SIZE / 1048576 ))MB) — drive may not have opened correctly"
        status "error:Rip too fast - possible drive issue"
        exit 1
    fi

    log "Ripped $MKV_COUNT titles in ${RIP_ELAPSED}s ($(( TOTAL_SIZE / 1073741824 ))GB)"
    touch "$RIP_MARKER"
fi

# === CLASSIFY DISC (ffprobe-based, sets preset/DVD detection) ===
echo ""
echo "######################################"
echo "#  STEP 2: ANALYZING CONTENT        #"
echo "######################################"
echo ""

classify_disc "$RIP_DIR"

# === DETERMINE MOVIE VS TV ===

if [ "$FORCE_MODE" = "tv" ]; then
    # --force-tv: build episode list from files in 15-65 min range
    log "Force-TV mode: skipping Movie/TV dialog"
    declare -a EPISODE_FILES=()
    for mkv in "${DISC_FILES[@]}"; do
        dur="${FILE_DURATION[$mkv]}"
        if [ "$dur" -ge 15 ] && [ "$dur" -le 65 ]; then
            EPISODE_FILES+=("$mkv")
        fi
    done
    NUM_EPISODES=${#EPISODE_FILES[@]}

    # Fallback: <3 episodes means this is probably a movie
    if [ "$NUM_EPISODES" -lt 3 ]; then
        log "Force-TV: Only $NUM_EPISODES episode-length files, falling back to movie"
        FORCE_MODE="movie"
    else
        IS_TV=1
    fi
fi

if [ "$FORCE_MODE" = "movie" ]; then
    IS_TV=0
    log "Force-Movie mode: skipping Movie/TV dialog"
elif [ -z "$FORCE_MODE" ]; then
    # === INTERACTIVE DIALOG ===
    status "dialog"

    # Set display environment for GUI (systemd-run doesn't inherit session env)
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DISPLAY="${DISPLAY:-:0}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

    if [ -z "$XAUTHORITY" ]; then
        XAUTH_FILE=$(ls "$XDG_RUNTIME_DIR"/.mutter-Xwaylandauth.* 2>/dev/null | head -1)
        [ -n "$XAUTH_FILE" ] && export XAUTHORITY="$XAUTH_FILE"
    fi

    # Build disc summary for dialog
    DISC_SUMMARY=""
    DISC_TYPE="Blu-ray"
    [ "$IS_DVD" -eq 1 ] && DISC_TYPE="DVD"
    file_idx=1
    for mkv in "${DISC_FILES[@]}"; do
        dur="${FILE_DURATION[$mkv]}"
        size_mb=$(( ${FILE_SIZE[$mkv]} / 1048576 ))
        width="${FILE_WIDTH[$mkv]}"
        DISC_SUMMARY+="Title $file_idx: ${dur} min, ${size_mb}MB, ${width}px\n"
        file_idx=$(( file_idx + 1 ))
    done

    # Alert the user
    paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null &
    notify-send -u critical "ELEPHCINEMA" "Disc detected (${DISC_TYPE}) — ${#DISC_FILES[@]} titles. Waiting for input." 2>/dev/null

    # First dialog: Movie or TV?
    yad --form \
        --title="ELEPHCINEMA — ${DISC_TYPE} Detected" \
        --text="<b>${DISC_TYPE} disc — ${#DISC_FILES[@]} titles found:</b>\n\n${DISC_SUMMARY}" \
        --width=450 --height=300 \
        --center \
        --on-top \
        --skip-taskbar \
        --sticky \
        --undecorated \
        --borders=20 \
        --button="Movie:0" \
        --button="TV Show:2" \
        2>/dev/null

    YAD_EXIT=$?

    if [ $YAD_EXIT -eq 2 ]; then
        IS_TV=1
        log "User selected: TV Show"
    else
        IS_TV=0
        log "User selected: Movie"
    fi
fi

# === TV: GET SHOW DETAILS ===
if [ "$IS_TV" -eq 1 ]; then
    if [ "$FORCE_MODE" = "tv" ]; then
        # --force-tv: need show details dialog (no way around it)
        :
    else
        # Build episode list: all files
        declare -a EPISODE_FILES=()
        for mkv in "${DISC_FILES[@]}"; do
            EPISODE_FILES+=("$mkv")
        done
        NUM_EPISODES=${#EPISODE_FILES[@]}
    fi

    if [ -z "$SHOW_NAME" ]; then
        # Set display env if not already set (force-tv mode)
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        export DISPLAY="${DISPLAY:-:0}"
        export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
        export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
        if [ -z "$XAUTHORITY" ]; then
            XAUTH_FILE=$(ls "$XDG_RUNTIME_DIR"/.mutter-Xwaylandauth.* 2>/dev/null | head -1)
            [ -n "$XAUTH_FILE" ] && export XAUTHORITY="$XAUTH_FILE"
        fi

        DIALOG_RESULT=$(yad --form \
            --title="ELEPHCINEMA — Show Details" \
            --text="<b>Enter show details:</b>" \
            --field="Show Name:TEXT" "" \
            --field="Season Number:NUM" "1!1..99!1" \
            --width=450 --height=350 \
            --center \
            --on-top \
            --skip-taskbar \
            --sticky \
            --undecorated \
            --borders=20 \
            --button="Cancel:1" \
            --button="Rip Episodes:0" \
            2>/dev/null)

        TV_EXIT=$?

        if [ $TV_EXIT -ne 0 ] || [ -z "$DIALOG_RESULT" ]; then
            log "TV: Dialog cancelled — aborting"
            status "error:Cancelled"
            exit 0
        fi

        SHOW_NAME=$(echo "$DIALOG_RESULT" | cut -d'|' -f1)
        SEASON_NUM=$(echo "$DIALOG_RESULT" | cut -d'|' -f2 | cut -d'.' -f1)

        if [ -z "$SHOW_NAME" ]; then
            log "TV: Empty show name — aborting"
            status "error:No show name"
            exit 0
        fi
    fi

    log "TV: $NUM_EPISODES titles will be encoded as episodes"
fi

# === MOVIE: GET TITLE ===
if [ "$IS_TV" -eq 0 ] && [ -z "$FORCE_MODE" ]; then
    MOVIE_RESULT=$(yad --form \
        --title="ELEPHCINEMA — Movie Title" \
        --text="<b>Enter movie title:</b>" \
        --field="Movie Title:TEXT" "" \
        --width=450 --height=200 \
        --center \
        --on-top \
        --skip-taskbar \
        --sticky \
        --undecorated \
        --borders=20 \
        --button="Cancel:1" \
        --button="Rip Movie:0" \
        2>/dev/null)

    MOVIE_EXIT=$?

    if [ $MOVIE_EXIT -ne 0 ]; then
        log "Movie: Dialog cancelled — aborting"
        status "error:Cancelled"
        exit 0
    fi

    USER_MOVIE_TITLE=$(echo "$MOVIE_RESULT" | cut -d'|' -f1)
fi

# ================================================================
#  TV EPISODE PATH
# ================================================================
if [ "$IS_TV" -eq 1 ]; then
    SEASON_NUM="${SEASON_NUM:-1}"
    SEASON_DIR=$(printf "Season %02d" "$SEASON_NUM")
    SEASON_TAG=$(printf "S%02d" "$SEASON_NUM")
    OUTPUT_DIR="$TV_OUTPUT_BASE/$SHOW_NAME/$SEASON_DIR"
    mkdir -p "$OUTPUT_DIR"

    # Delete non-episode files to reclaim space (force-tv mode)
    if [ "$FORCE_MODE" = "tv" ]; then
        for mkv in "${DISC_FILES[@]}"; do
            is_ep=0
            for ep in "${EPISODE_FILES[@]}"; do
                [ "$mkv" = "$ep" ] && is_ep=1 && break
            done
            if [ "$is_ep" -eq 0 ]; then
                log "TV: Removing non-episode: $(basename "$mkv") (${FILE_DURATION[$mkv]} min)"
                rm -f "$mkv"
            fi
        done
    fi

    # Auto-increment episode numbers from existing files
    NEXT_EPISODE=1
    if [ -d "$OUTPUT_DIR" ]; then
        HIGHEST=$(ls "$OUTPUT_DIR" 2>/dev/null | grep -oP 'E(\d+)' | grep -oP '\d+' | sort -n | tail -1)
        if [ -n "$HIGHEST" ]; then
            NEXT_EPISODE=$(( 10#$HIGHEST + 1 ))
            log "TV: Existing episodes up to E$(printf '%02d' "$HIGHEST"), starting at E$(printf '%02d' "$NEXT_EPISODE")"
        fi
    fi

    echo ""
    echo "######################################"
    echo "#  STEP 3: ENCODING $NUM_EPISODES EPISODES"
    echo "######################################"
    echo ""

    FAIL_COUNT=0

    for (( idx=0; idx<NUM_EPISODES; idx++ )); do
        EP_MKV="${EPISODE_FILES[$idx]}"
        EP_NUM=$(( NEXT_EPISODE + idx ))
        EP_TAG=$(printf "E%02d" "$EP_NUM")
        EP_LABEL="E$((idx+1))/${NUM_EPISODES}"
        FILENAME="$SHOW_NAME - ${SEASON_TAG}${EP_TAG}.mp4"
        LOCAL_MP4="$TEMP_DIR/${SHOW_NAME}_${SEASON_TAG}${EP_TAG}.mp4"
        FINAL_MP4="$OUTPUT_DIR/$FILENAME"

        MKV_SIZE=$(du -h "$EP_MKV" | cut -f1)
        log "TV: Encoding $EP_LABEL ($EP_TAG)"
        status "encode:0:$EP_LABEL"

        HandBrakeCLI -i "$EP_MKV" -o "$LOCAL_MP4" \
            --preset="$PRESET" \
            $HANDBRAKE_EXTRA_ARGS \
            --audio-lang-list "$ELEPHCINEMA_AUDIO_LANGS" \
            --all-audio \
            --subtitle-lang-list "$ELEPHCINEMA_SUB_LANGS" \
            --all-subtitles \
            --optimize \
            2>&1 | tee "$TEMP_DIR/handbrake_${EP_TAG}.log" | while IFS= read -r line; do
            if [[ "$line" =~ Encoding:.*([0-9]+\.[0-9]+)\ % ]]; then
                PCT="${BASH_REMATCH[1]%.*}"
                status "encode:$PCT:$EP_LABEL"
                echo -ne "\r>>> Encoding $EP_LABEL: ${PCT}%   "
            fi
        done
        echo ""

        # Validate & copy
        if validate_file "$LOCAL_MP4"; then
            LOCAL_SIZE=$(du -h "$LOCAL_MP4" | cut -f1)
            log "TV: Encoded $EP_TAG: $MKV_SIZE -> $LOCAL_SIZE"

            status "copying:$EP_LABEL"
            echo ">>> Copying $EP_LABEL to output..."
            cp "$LOCAL_MP4" "$FINAL_MP4"

            if [ -f "$FINAL_MP4" ]; then
                SRC_SIZE=$(stat -c%s "$LOCAL_MP4")
                DST_SIZE=$(stat -c%s "$FINAL_MP4")

                if [ "$SRC_SIZE" -eq "$DST_SIZE" ] && validate_file "$FINAL_MP4"; then
                    log "TV: $EP_TAG copied and verified"
                else
                    log "TV: ERROR: Copy verification failed for $EP_TAG"
                    rm -f "$FINAL_MP4"
                    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
                    KEEP_TEMP=1
                fi
            else
                log "TV: ERROR: Copy failed for $EP_TAG"
                FAIL_COUNT=$(( FAIL_COUNT + 1 ))
                KEEP_TEMP=1
            fi
        else
            # Encode failed — save raw MKV as fallback
            log "TV: ERROR: Encode failed for $EP_TAG, saving raw MKV"
            FALLBACK_MKV="$OUTPUT_DIR/${SHOW_NAME} - ${SEASON_TAG}${EP_TAG}.mkv"
            cp "$EP_MKV" "$FALLBACK_MKV"
            if [ $? -eq 0 ]; then
                log "TV: Saved raw MKV fallback: $FALLBACK_MKV"
            else
                log "TV: ERROR: Could not save raw MKV"
                KEEP_TEMP=1
            fi
            FAIL_COUNT=$(( FAIL_COUNT + 1 ))
        fi

        # Clean up this episode's temp files
        rm -f "$EP_MKV" "$LOCAL_MP4" "$TEMP_DIR/handbrake_${EP_TAG}.log"
    done

    # Completion message
    LAST_EP=$(( NEXT_EPISODE + NUM_EPISODES - 1 ))
    FIRST_TAG=$(printf "E%02d" "$NEXT_EPISODE")
    LAST_TAG=$(printf "E%02d" "$LAST_EP")
    DONE_MSG="$SHOW_NAME ${SEASON_TAG}${FIRST_TAG}-${LAST_TAG}"
    [ "$FAIL_COUNT" -gt 0 ] && DONE_MSG="$DONE_MSG ($FAIL_COUNT failed)"

    echo ""
    echo "######################################"
    echo "#  DONE! TV: $DONE_MSG"
    echo "######################################"

else
    # ================================================================
    #  MOVIE PATH
    # ================================================================
    OUTPUT_DIR="$MOVIE_OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"

    # Pick best movie file: largest in 60-240 min range
    BEST_MKV=""
    BEST_SIZE=0
    BEST_DUR=0

    for mkv in "${DISC_FILES[@]}"; do
        dur="${FILE_DURATION[$mkv]}"
        size="${FILE_SIZE[$mkv]}"
        if [ "$dur" -ge 60 ] && [ "$dur" -le 240 ]; then
            if [ "$size" -gt "$BEST_SIZE" ]; then
                BEST_SIZE="$size"
                BEST_MKV="$mkv"
                BEST_DUR="$dur"
            fi
        fi
    done

    # Fallback: largest file overall
    if [ -z "$BEST_MKV" ]; then
        log "No title in 60-240 min range, falling back to largest file"
        for mkv in "${DISC_FILES[@]}"; do
            size="${FILE_SIZE[$mkv]}"
            if [ "$size" -gt "$BEST_SIZE" ]; then
                BEST_SIZE="$size"
                BEST_MKV="$mkv"
                BEST_DUR="${FILE_DURATION[$mkv]}"
            fi
        done
    fi

    if [ -z "$BEST_MKV" ]; then
        log "ERROR: No suitable MKV file found"
        status "error:No suitable file"
        exit 1
    fi

    BEST_SIZE_GB=$(echo "scale=2; $BEST_SIZE / 1073741824" | bc)
    log "Selected main feature: $(basename "$BEST_MKV") (${BEST_DUR} min, ${BEST_SIZE_GB} GB)"

    # Delete non-main files to reclaim space
    for mkv in "${DISC_FILES[@]}"; do
        [ "$mkv" != "$BEST_MKV" ] && rm -f "$mkv"
    done

    MAIN_MKV="$BEST_MKV"

    # Generate filename
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    if [ -n "$USER_MOVIE_TITLE" ]; then
        BASENAME=$(echo "$USER_MOVIE_TITLE" | sed 's/[^a-zA-Z0-9 ._-]//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
        BASENAME="${BASENAME}_${TIMESTAMP}"
    else
        BASENAME=$(basename "$MAIN_MKV" .mkv | sed 's/[^a-zA-Z0-9._-]/_/g' | sed 's/_t[0-9]*$//')
        if [ -z "$BASENAME" ] || [[ "$BASENAME" =~ ^(title|disc|movie|BDMV|[A-Z0-9]{8})$ ]]; then
            BASENAME="Rip_${TIMESTAMP}"
            log "Using timestamp name: $BASENAME"
        else
            BASENAME="${BASENAME}_${TIMESTAMP}"
        fi
    fi

    log "Ripped: $BASENAME"

    MKV_SIZE=$(du -h "$MAIN_MKV" | cut -f1)
    echo ""
    echo ">>> Main feature: $BASENAME ($MKV_SIZE)"
    echo ""
    echo "######################################"
    echo "#  STEP 3: COMPRESSING              #"
    echo "######################################"
    echo ""
    echo ">>> Encoding locally then copying to output..."
    echo ""

    LOCAL_OUTPUT="$TEMP_DIR/${BASENAME}.mp4"
    FINAL_OUTPUT="$OUTPUT_DIR/${BASENAME}.mp4"

    # Never overwrite existing files
    if [ -f "$FINAL_OUTPUT" ]; then
        EXTRA_TS=$(date +%H%M%S)
        FINAL_OUTPUT="$OUTPUT_DIR/${BASENAME}_${EXTRA_TS}.mp4"
        log "File exists, will save as: $FINAL_OUTPUT"
    fi

    status "encode:0"
    log "Encoding to local temp: $LOCAL_OUTPUT"

    HandBrakeCLI -i "$MAIN_MKV" -o "$LOCAL_OUTPUT" \
        --preset="$PRESET" \
        $HANDBRAKE_EXTRA_ARGS \
        --audio-lang-list "$ELEPHCINEMA_AUDIO_LANGS" \
        --all-audio \
        --subtitle-lang-list "$ELEPHCINEMA_SUB_LANGS" \
        --all-subtitles \
        --optimize \
        2>&1 | tee "$TEMP_DIR/handbrake.log" | while IFS= read -r line; do
        if [[ "$line" =~ Encoding:.*([0-9]+\.[0-9]+)\ % ]]; then
            PCT="${BASH_REMATCH[1]%.*}"
            status "encode:$PCT"
            echo -ne "\r>>> Encoding: ${PCT}%   "
        fi
    done
    echo ""

    # Validate LOCAL output before copying
    VALID_OUTPUT=0
    if [ -f "$LOCAL_OUTPUT" ]; then
        if ffprobe -v error -show_format "$LOCAL_OUTPUT" 2>&1 | grep -q "format_name"; then
            VALID_OUTPUT=1
            LOCAL_SIZE=$(du -h "$LOCAL_OUTPUT" | cut -f1)
            log "Encoding complete and valid: $LOCAL_SIZE"
        else
            log "ERROR: Encoded file is corrupt!"
            rm -f "$LOCAL_OUTPUT"
        fi
    fi

    if [ "$VALID_OUTPUT" -eq 1 ]; then
        status "copying"
        echo ">>> Copying to output..."
        cp "$LOCAL_OUTPUT" "$FINAL_OUTPUT"

        if [ -f "$FINAL_OUTPUT" ]; then
            SRC_SIZE=$(stat -c%s "$LOCAL_OUTPUT")
            DST_SIZE=$(stat -c%s "$FINAL_OUTPUT")

            if [ "$SRC_SIZE" -eq "$DST_SIZE" ]; then
                if ffprobe -v error -show_format "$FINAL_OUTPUT" 2>&1 | grep -q "format_name"; then
                    FINAL_SIZE=$(du -h "$FINAL_OUTPUT" | cut -f1)
                    log "Compressed and copied: $FINAL_SIZE"
                    echo ""
                    echo "######################################"
                    echo "#  DONE!                            #"
                    echo "######################################"
                    echo ">>> Saved: $FINAL_OUTPUT"
                    echo ">>> Size: $MKV_SIZE -> $FINAL_SIZE"
                    rm -f "$LOCAL_OUTPUT" "$MAIN_MKV"
                else
                    log "ERROR: Output copy is corrupt! Keeping local copy."
                    echo ">>> ERROR: Output copy corrupt!"
                    echo ">>> Valid file at: $LOCAL_OUTPUT"
                    rm -f "$FINAL_OUTPUT"
                    KEEP_TEMP=1
                fi
            else
                log "ERROR: Copy size mismatch!"
                echo ">>> ERROR: Copy failed!"
                echo ">>> Valid file at: $LOCAL_OUTPUT"
                rm -f "$FINAL_OUTPUT"
                KEEP_TEMP=1
            fi
        else
            log "ERROR: Copy to output failed!"
            echo ">>> Valid file at: $LOCAL_OUTPUT"
            KEEP_TEMP=1
        fi
    else
        # Encoding failed — save raw MKV instead
        log "Encoding failed, saving raw MKV"
        MKV_OUTPUT="$OUTPUT_DIR/${BASENAME}.mkv"
        if [ -f "$MKV_OUTPUT" ]; then
            MKV_OUTPUT="$OUTPUT_DIR/${BASENAME}_$(date +%H%M%S).mkv"
        fi
        cp "$MAIN_MKV" "$MKV_OUTPUT"
        if [ $? -eq 0 ]; then
            FINAL_SIZE=$(du -h "$MKV_OUTPUT" | cut -f1)
            log "Saved raw MKV: $FINAL_SIZE"
            echo ""
            echo "######################################"
            echo "#  DONE (raw MKV)                   #"
            echo "######################################"
            echo ">>> Saved: $MKV_OUTPUT"
            echo ">>> Size: $FINAL_SIZE (encode manually later)"
            rm -f "$MAIN_MKV"
        else
            log "ERROR: Could not save to output!"
            echo ">>> ERROR: Write failed!"
            echo ">>> Source kept at: $MAIN_MKV"
            rm -f "$MKV_OUTPUT"
            KEEP_TEMP=1
        fi
    fi

    DONE_MSG="$BASENAME"
fi

# === EJECT ===
# Only eject when NOT dispatched (dispatcher handles eject + cooldown)
if [ "${ELEPHCINEMA_DISPATCHED:-0}" -ne 1 ]; then
    eject_disc
fi

log "=== Done: ${DONE_MSG:-complete} ==="
status "done:${DONE_MSG:-complete}"
notify-send "ELEPHCINEMA" "Done: ${DONE_MSG:-complete}" 2>/dev/null

sleep 30
exit 0

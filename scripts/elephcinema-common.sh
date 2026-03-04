#!/bin/bash
# ELEPHCINEMA — Shared functions and configuration
# Sourced by elephcinema.sh and elephcinema-dispatch.sh
#
# Copyright (C) 2026 AnarchyGames.org
# SPDX-License-Identifier: GPL-3.0-or-later

# === CONFIGURATION ===

load_config() {
    local config_file="${ELEPHCINEMA_CONFIG:-$HOME/.config/elephcinema/config}"
    [ -f "$config_file" ] && source "$config_file"

    ELEPHCINEMA_MOVIE_DIR="${ELEPHCINEMA_MOVIE_DIR:-$HOME/Movies}"
    ELEPHCINEMA_TV_DIR="${ELEPHCINEMA_TV_DIR:-$HOME/TV}"
    ELEPHCINEMA_TEMP_DIR="${ELEPHCINEMA_TEMP_DIR:-$HOME/.local/share/elephcinema/temp}"
    ELEPHCINEMA_LOG_FILE="${ELEPHCINEMA_LOG_FILE:-$HOME/.local/share/elephcinema/elephcinema.log}"
    ELEPHCINEMA_STATUS_FILE="${ELEPHCINEMA_STATUS_FILE:-/tmp/elephcinema-status}"
    ELEPHCINEMA_LOCK_FILE="${ELEPHCINEMA_LOCK_FILE:-/tmp/elephcinema.lock}"
    ELEPHCINEMA_DISPATCH_LOCK="${ELEPHCINEMA_DISPATCH_LOCK:-/tmp/elephcinema-dispatch.lock}"
    ELEPHCINEMA_COOLDOWN_FILE="${ELEPHCINEMA_COOLDOWN_FILE:-/tmp/elephcinema-cooldown}"
    ELEPHCINEMA_MAKEMKVCON="${ELEPHCINEMA_MAKEMKVCON:-/usr/bin/makemkvcon}"
    ELEPHCINEMA_MIN_DISK_GB="${ELEPHCINEMA_MIN_DISK_GB:-55}"
    ELEPHCINEMA_AUDIO_LANGS="${ELEPHCINEMA_AUDIO_LANGS:-eng,jpn,und}"
    ELEPHCINEMA_SUB_LANGS="${ELEPHCINEMA_SUB_LANGS:-eng}"

    # VAAPI hardware encoding settings
    ELEPHCINEMA_VAAPI_DEVICE="${ELEPHCINEMA_VAAPI_DEVICE:-/dev/dri/renderD128}"
    ELEPHCINEMA_QP_HD="${ELEPHCINEMA_QP_HD:-24}"
    ELEPHCINEMA_QP_DVD="${ELEPHCINEMA_QP_DVD:-20}"
    ELEPHCINEMA_MAX_PARALLEL="${ELEPHCINEMA_MAX_PARALLEL:-3}"

    # Ensure log directory exists
    mkdir -p "$(dirname "$ELEPHCINEMA_LOG_FILE")"
}

load_config

# === LOGGING ===

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ELEPHCINEMA_LOG_FILE"
}

status() {
    echo "$1" > "$ELEPHCINEMA_STATUS_FILE"
}

# === DEVICE DETECTION ===
# Uses blockdev (kernel-level) instead of MakeMKV to avoid opening the drive.
# Auto mode retries up to 9 times (90 seconds) for disc spin-up.
# Sets globals: MKV_SOURCE, USE_DEV_PATH, DISC_INDEX

detect_device() {
    local device="${1:-auto}"
    DISC_INDEX=""
    USE_DEV_PATH=""

    if [ "$device" = "auto" ]; then
        log "Auto-detecting optical drive..."
        for attempt in {1..9}; do
            for sr in /dev/sr{0..9}; do
                if [ -e "$sr" ]; then
                    local size
                    size=$(blockdev --getsize64 "$sr" 2>/dev/null || echo 0)
                    if [ "$size" -gt 0 ]; then
                        USE_DEV_PATH="$sr"
                        log "Found disc at $sr ($(( size / 1073741824 )) GB)"
                        break 2
                    fi
                fi
            done
            if [ "$attempt" -lt 9 ]; then
                log "No disc found, waiting... (attempt $attempt/9)"
                sleep 10
            fi
        done

        if [ -z "$USE_DEV_PATH" ]; then
            log "No disc found in any drive after 90s"
            return 1
        fi
    elif [[ "$device" =~ ^[0-9]+$ ]]; then
        DISC_INDEX="$device"
    elif [[ "$device" =~ ^/dev/ ]]; then
        USE_DEV_PATH="$device"
        log "Using device path: $device"
    fi

    if [ -n "$USE_DEV_PATH" ]; then
        MKV_SOURCE="dev:$USE_DEV_PATH"
    else
        MKV_SOURCE="disc:$DISC_INDEX"
    fi

    return 0
}

# === DISC UTILITIES ===

unmount_discs() {
    for sr in /dev/sr*; do
        if mount | grep -q "$sr"; then
            log "Unmounting $sr..."
            udisksctl unmount -b "$sr" 2>/dev/null || umount "$sr" 2>/dev/null
            sleep 1
        fi
    done
}

wait_for_disc_ready() {
    local dev="$1"
    local ready=0

    for i in {1..9}; do
        local size
        size=$(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)
        if [ "$size" -gt 0 ]; then
            ready=1
            log "Disc ready on $dev ($(( size / 1073741824 )) GB)"
            break
        fi
        log "Waiting for disc to be ready... (attempt $i/9)"
        sleep 10
    done

    return $(( ready == 0 ))
}

# === DISC CLASSIFICATION ===
# Classifies ripped MKV files as Movie or TV using ffprobe.
# Sets globals: IS_TV, IS_4K, IS_DVD, DISC_FILES[], FILE_DURATION[], FILE_SIZE[], FILE_WIDTH[]

classify_disc() {
    local rip_dir="$1"
    IS_TV=0
    IS_4K=0
    IS_DVD=0
    declare -ga DISC_FILES=()
    declare -gA FILE_DURATION=()
    declare -gA FILE_SIZE=()
    declare -gA FILE_WIDTH=()

    local ep_count=0
    local has_long=0
    local max_width=0

    for mkv in "$rip_dir"/*.mkv; do
        [ -f "$mkv" ] || continue
        DISC_FILES+=("$mkv")

        local dur_secs size width
        dur_secs=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mkv" 2>/dev/null | cut -d. -f1)
        size=$(stat -c%s "$mkv" 2>/dev/null || echo 0)
        width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$mkv" 2>/dev/null | head -1)

        dur_secs="${dur_secs:-0}"
        width="${width:-0}"

        local dur_mins=$(( dur_secs / 60 ))

        FILE_DURATION["$mkv"]=$dur_mins
        FILE_SIZE["$mkv"]=$size
        FILE_WIDTH["$mkv"]=$width

        if [ "$width" -gt "$max_width" ]; then
            max_width=$width
        fi

        # Episode range: 15-65 minutes
        if [ "$dur_mins" -ge 15 ] && [ "$dur_mins" -le 65 ]; then
            ep_count=$(( ep_count + 1 ))
        fi

        # Long file (>65 min) suggests movie
        if [ "$dur_mins" -gt 65 ]; then
            has_long=1
        fi

        # 4K detection
        if [ "$width" -ge 3800 ]; then
            IS_4K=1
        fi
    done

    # DVD detection: max width 720 or below (NTSC 720x480, PAL 720x576)
    if [ "$max_width" -gt 0 ] && [ "$max_width" -le 720 ]; then
        IS_DVD=1
    fi

    # TV: 3+ files in episode range, no file over 65 min
    if [ "$ep_count" -ge 3 ] && [ "$has_long" -eq 0 ]; then
        IS_TV=1
        log "Classified as TV: $ep_count episodes in ${#DISC_FILES[@]} total files"
    else
        log "Classified as Movie: ${#DISC_FILES[@]} files, $ep_count in episode range, has_long=$has_long"
    fi

    # Log source quality
    if [ "$IS_DVD" -eq 1 ]; then
        log "DVD detected (${max_width}px wide) — native resolution, QP $ELEPHCINEMA_QP_DVD"
    elif [ "$IS_4K" -eq 1 ]; then
        log "4K content detected — will scale to 1080p"
    fi
}

# === DISK SPACE CHECK ===

check_disk_space() {
    local dir="$1"
    local min_gb="${2:-$ELEPHCINEMA_MIN_DISK_GB}"
    local avail_kb
    avail_kb=$(df -k "$dir" | tail -1 | awk '{print $4}')
    local avail_gb=$(( avail_kb / 1048576 ))

    if [ "$avail_gb" -lt "$min_gb" ]; then
        log "ERROR: Only ${avail_gb}GB free in $dir (need ${min_gb}GB minimum)"
        return 1
    fi
    log "Disk space OK: ${avail_gb}GB free"
    return 0
}

# === FILE VALIDATION ===

validate_file() {
    local filepath="$1"
    if [ -f "$filepath" ] && ffprobe -v error -show_format "$filepath" 2>&1 | grep -q "format_name"; then
        return 0
    fi
    return 1
}

# === VAAPI HARDWARE ENCODING ===
# Encodes a video file using ffmpeg with VAAPI hardware acceleration (HEVC).
# Usage: encode_vaapi "$input" "$output" "$log_file" ["$status_prefix"]
# Uses globals: IS_DVD, IS_4K, ELEPHCINEMA_VAAPI_DEVICE, ELEPHCINEMA_QP_HD, ELEPHCINEMA_QP_DVD
# Returns: 0 on success, 1 on failure

encode_vaapi() {
    local input="$1"
    local output="$2"
    local encode_log="$3"
    local status_prefix="${4:-encode}"
    local qp="$ELEPHCINEMA_QP_HD"
    local scale_filter=""

    # DVD: higher quality (lower QP) since source is already low-res
    if [ "${IS_DVD:-0}" -eq 1 ]; then
        qp="$ELEPHCINEMA_QP_DVD"
    fi

    # 4K: scale down to 1080p
    if [ "${IS_4K:-0}" -eq 1 ]; then
        scale_filter=",scale_vaapi=w=1920:h=-2"
    fi

    # Get duration for progress calculation
    local total_us
    total_us=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$input" 2>/dev/null | sed 's/\.//' | head -1)
    total_us="${total_us:-0}"

    ffmpeg -y -vaapi_device "$ELEPHCINEMA_VAAPI_DEVICE" \
        -i "$input" \
        -vf "format=nv12,hwupload${scale_filter}" \
        -c:v hevc_vaapi -qp "$qp" -rc_mode CQP \
        -c:a copy \
        -movflags +faststart \
        -progress pipe:1 \
        "$output" \
        2>"$encode_log" | while IFS='=' read -r key val; do
        if [ "$key" = "out_time_us" ] && [ "$total_us" -gt 0 ] 2>/dev/null; then
            PCT=$(( val * 100 / total_us ))
            [ "$PCT" -gt 100 ] && PCT=100
            status "$status_prefix:$PCT"
            echo -ne "\r>>> Encoding: ${PCT}%   "
        fi
    done
    echo ""

    # Check if output was produced and is valid
    if [ ! -f "$output" ] || [ ! -s "$output" ]; then
        log "ERROR: Encode produced no output — see $encode_log"
        [ -f "$encode_log" ] && tail -10 "$encode_log" >> "$ELEPHCINEMA_LOG_FILE"
        return 1
    fi

    # Check for ffmpeg errors in log
    if grep -qiE "error|abort|signal|killed|panic" "$encode_log" 2>/dev/null; then
        # Some "error" lines are harmless — only fail if output is also invalid
        if ! validate_file "$output"; then
            log "ERROR: Encode failed with errors — see $encode_log"
            tail -10 "$encode_log" >> "$ELEPHCINEMA_LOG_FILE"
            return 1
        fi
    fi

    return 0
}

# === EJECT ===

eject_disc() {
    local eject_dev="${USE_DEV_PATH:-}"

    if [ -z "$eject_dev" ]; then
        for sr in /dev/sr{0..9}; do
            if [ -e "$sr" ]; then
                eject_dev="$sr"
                break
            fi
        done
    fi

    if [ -n "$eject_dev" ]; then
        eject "$eject_dev" 2>/dev/null
        echo ">>> Disc ejected"
    else
        echo ">>> Could not determine device to eject"
    fi
}

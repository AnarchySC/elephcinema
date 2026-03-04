<div align="center">

```
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   ███████ █      ███████ ████  █   █  ████ █ █   █ █████║
║   █       █      █       █   █ █   █ █     █ ██  █ █    ║
║   █████   █      █████   ████  █████ █     █ █ █ █ ████ ║
║   █       █      █       █     █   █ █     █ █  ██ █    ║
║   ███████ ██████ ███████ █     █   █  ████ █ █   █ █████║
║   ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░║
║   Automated Blu-ray/DVD ripping pipeline for Linux       ║
║   Insert a disc. Answer one dialog. Get an MP4.          ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

[![GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-E85D04?style=flat-square)](LICENSE)
[![Linux](https://img.shields.io/badge/platform-Linux-00d4ff?style=flat-square)]()
[![Bash](https://img.shields.io/badge/language-Bash-FAA307?style=flat-square)]()
[![AnarchyGames](https://img.shields.io/badge/by-AnarchyGames.org-E85D04?style=flat-square)](https://anarchygames.org)

*Building things that should exist.*

</div>

---

## How It Works

```
 ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
 │  INSERT   │───▸│  RIP     │───▸│ CLASSIFY │───▸│  ENCODE  │───▸│  DONE    │
 │  DISC     │    │ MakeMKV  │    │ ffprobe  │    │ HandBrake│    │  ✓ eject │
 └──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
     udev            all titles      Movie/TV?       MP4 out        verified
     trigger         one pass        auto-detect     preset match   copy
```

1. **udev** detects disc insertion and triggers the dispatcher
2. **MakeMKV** rips all titles in a single pass (avoids LibreDrive double-open bugs)
3. **ffprobe** classifies the disc as Movie or TV based on file count, duration, and resolution
4. A **yad dialog** asks you to confirm Movie/TV and enter a title
5. **HandBrake** encodes to MP4 with the appropriate preset (1080p for Blu-ray, 480p for DVD)
6. The encoded file is **copied and verified** (size + ffprobe check) to your output directory
7. The disc is **ejected** automatically

TV episodes are auto-numbered from existing files in the season folder. DVD and 4K sources are detected automatically.

## Hardware Requirements

- An optical drive supported by MakeMKV
- For 4K UHD: a **LibreDrive-compatible** drive (e.g., BU40N with DE firmware)
- ~55GB free temp disk space for a full Blu-ray rip

## Dependencies

| Dependency | Package | Required |
|---|---|---|
| makemkvcon | [MakeMKV](https://www.makemkv.com/) | Yes |
| HandBrakeCLI | `handbrake-cli` | Yes |
| ffprobe | `ffmpeg` | Yes |
| yad | `yad` | Yes |
| notify-send | `libnotify-bin` | Yes |
| eject | `eject` | Yes |
| blockdev | `util-linux` | Yes |
| bc | `bc` | Yes |
| paplay | `pulseaudio-utils` | No (sound alert) |
| udisksctl | `udisks2` | No (auto-unmount) |

**Tray indicator** (optional): `sudo apt install gir1.2-ayatanaappindicator3-0.1`

## Installation

```bash
git clone https://github.com/AnarchySC/elephcinema.git
cd elephcinema
./install.sh              # installs to /opt/elephcinema/
./install.sh /usr/local   # or choose a custom prefix
```

The installer checks all dependencies, copies scripts, creates `~/.config/elephcinema/config`, and offers to install a udev rule for auto-rip on disc insert.

## Configuration

Edit `~/.config/elephcinema/config`. All settings have sane defaults — you only need to set your output directories:

```bash
# Where to save movies and TV shows
ELEPHCINEMA_MOVIE_DIR="/mnt/nas/Media/Movies"
ELEPHCINEMA_TV_DIR="/mnt/nas/Media/Shows"

# Temp directory (needs ~55GB free for Blu-ray)
ELEPHCINEMA_TEMP_DIR="$HOME/.local/share/elephcinema/temp"
```

<details>
<summary><b>Full Configuration Reference</b></summary>

| Variable | Default | Description |
|---|---|---|
| `ELEPHCINEMA_MOVIE_DIR` | `$HOME/Movies` | Movie output directory |
| `ELEPHCINEMA_TV_DIR` | `$HOME/TV` | TV show output directory |
| `ELEPHCINEMA_TEMP_DIR` | `~/.local/share/elephcinema/temp` | Temp space for ripping/encoding |
| `ELEPHCINEMA_LOG_FILE` | `~/.local/share/elephcinema/elephcinema.log` | Log file path |
| `ELEPHCINEMA_STATUS_FILE` | `/tmp/elephcinema-status` | Status file (for tray/notifications) |
| `ELEPHCINEMA_MAKEMKVCON` | `/usr/bin/makemkvcon` | Path to makemkvcon binary |
| `ELEPHCINEMA_MIN_DISK_GB` | `55` | Minimum free space before ripping |
| `ELEPHCINEMA_PRESET_HD` | `Fast 1080p30` | HandBrake preset for HD/4K content |
| `ELEPHCINEMA_PRESET_DVD` | `Fast 480p30` | HandBrake preset for DVDs |
| `ELEPHCINEMA_AUDIO_LANGS` | `eng,jpn,und` | Audio languages to keep |
| `ELEPHCINEMA_SUB_LANGS` | `eng` | Subtitle languages to keep |

</details>

## Usage

### Automatic (udev)

Insert a disc. A dialog appears asking Movie or TV. Enter the title. Done.

### Manual

```bash
elephcinema.sh                         # auto-detect drive
elephcinema.sh /dev/sr0                # specify device
elephcinema.sh /dev/sr0 --force-tv     # skip dialog, TV mode (falls back to movie if <3 episodes)
elephcinema.sh /dev/sr0 --force-movie  # skip dialog, movie mode
```

### Tray Indicator

```bash
elephcinema-tray.py    # GTK/Ayatana AppIndicator (GNOME, Wayland)
elephcinema-tray.sh    # yad-based alternative
```

### Desktop Notifications

```bash
elephcinema-notify.sh  # notifies at 25% intervals + completion/error
```

## Troubleshooting

**"Rip too fast — possible drive issue"** — The drive didn't open properly. Common with LibreDrive on first spin-up. Eject and re-insert.

**"No MKV files produced"** — MakeMKV couldn't read the disc. Check your license key and disc condition.

**"Low disk space"** — Temp directory needs at least 55GB free (configurable). Blu-ray rips are large.

**Dialog doesn't appear** — The script needs display access. Check `yad --info --text="test"` works from your session.

**Encode failed, raw MKV saved** — HandBrake failed; raw MKV saved as fallback. Check `handbrake.log` in temp dir.

## Uninstall

```bash
./uninstall.sh              # removes /opt/elephcinema/ and udev rule
./uninstall.sh /usr/local   # custom prefix
```

Config and logs are preserved. Remove `~/.config/elephcinema/` and `~/.local/share/elephcinema/` manually if desired.

---

<div align="center">

## Support

If ELEPHCINEMA saves you time, consider buying me a coffee.

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support_ELEPHCINEMA-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/cassettefuture)

---

GPL-3.0-or-later. See [LICENSE](LICENSE).

An [AnarchyGames.org](https://anarchygames.org) project.

</div>

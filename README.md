# ELEPHCINEMA

Automated Blu-ray and DVD ripping pipeline for Linux. Insert a disc, answer one dialog, get an encoded MP4 in your library.

## How It Works

1. **udev** detects disc insertion and triggers the dispatcher
2. **MakeMKV** rips all titles in a single pass (avoids LibreDrive double-open bugs)
3. **ffprobe** classifies the disc as Movie or TV based on file count, duration, and resolution
4. A **yad dialog** asks you to confirm Movie/TV and enter a title
5. **HandBrake** encodes to MP4 with the appropriate preset (1080p for Blu-ray, 480p for DVD)
6. The encoded file is **copied and verified** (size + ffprobe check) in your output directory
7. The disc is **ejected** automatically

For TV shows, episodes are auto-numbered based on existing files in the season folder. DVD and 4K sources are detected automatically and use appropriate encoding presets.

## Hardware Requirements

- An optical drive supported by MakeMKV
- For 4K UHD: a **LibreDrive-compatible** drive (e.g., BU40N with DE firmware)
- Enough temp disk space for a full Blu-ray rip (~55GB minimum)

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

### Tray indicator (optional)

The Python tray indicator requires `gir1.2-ayatanaappindicator3-0.1`:

```bash
sudo apt install gir1.2-ayatanaappindicator3-0.1
```

## Installation

```bash
git clone https://github.com/AnarchySC/elephcinema.git
cd elephcinema
./install.sh              # installs to /opt/elephcinema/
./install.sh /usr/local   # or choose a custom prefix
```

The installer will:
- Check all dependencies
- Copy scripts to the install prefix
- Create `~/.config/elephcinema/config` from the example
- Offer to install a udev rule for auto-rip on disc insert

## Configuration

Edit `~/.config/elephcinema/config`. All settings have sane defaults — you only need to set output directories:

```bash
# Where to save movies and TV shows
ELEPHCINEMA_MOVIE_DIR="/mnt/nas/Media/Movies"
ELEPHCINEMA_TV_DIR="/mnt/nas/Media/Shows"

# Temp directory (needs ~55GB free for Blu-ray)
ELEPHCINEMA_TEMP_DIR="$HOME/.local/share/elephcinema/temp"
```

### Full Configuration Reference

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

## Usage

### Automatic (udev)

Insert a disc. A dialog appears asking if it's a Movie or TV Show. Enter the title and it handles the rest.

### Manual

```bash
# Auto-detect drive
elephcinema.sh

# Specify device
elephcinema.sh /dev/sr0

# Force TV mode (skips Movie/TV dialog, falls back to movie if <3 episodes)
elephcinema.sh /dev/sr0 --force-tv

# Force Movie mode (skips Movie/TV dialog)
elephcinema.sh /dev/sr0 --force-movie
```

### Tray Indicator

Run the tray indicator for real-time progress:

```bash
# GTK/Ayatana AppIndicator (GNOME, Wayland compatible)
elephcinema-tray.py

# yad-based alternative
elephcinema-tray.sh
```

### Desktop Notifications

```bash
elephcinema-notify.sh
```

Shows desktop notifications at 25% rip/encode progress intervals and on completion/error.

## Troubleshooting

**"Rip too fast — possible drive issue"**
The drive didn't open properly. This is common with LibreDrive on first spin-up. Eject and re-insert the disc.

**"No MKV files produced"**
MakeMKV couldn't read the disc. Check that your MakeMKV license is active and the disc isn't badly scratched.

**"Low disk space"**
The temp directory needs at least 55GB free (configurable via `ELEPHCINEMA_MIN_DISK_GB`). Blu-ray rips are large.

**Dialog doesn't appear**
The script needs access to your display session. If running via udev/systemd-run, it auto-detects Wayland/X11 env variables. Check that `yad` works: `yad --info --text="test"`

**Encode failed, raw MKV saved**
HandBrake couldn't encode the file. The raw MKV is saved as a fallback. Check the HandBrake log in the temp directory. Common cause: unsupported codec in source.

## Uninstall

```bash
./uninstall.sh              # removes /opt/elephcinema/ and udev rule
./uninstall.sh /usr/local   # if you used a custom prefix
```

Config and logs are preserved. Delete `~/.config/elephcinema/` and `~/.local/share/elephcinema/` manually if desired.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

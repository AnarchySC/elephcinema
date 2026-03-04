#!/usr/bin/python3
"""ELEPHCINEMA System Tray Indicator (Wayland/GNOME compatible)

Copyright (C) 2026 AnarchyGames.org
SPDX-License-Identifier: GPL-3.0-or-later
"""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AyatanaAppIndicator3', '0.1')

from gi.repository import Gtk, AyatanaAppIndicator3, GLib
import os

DEFAULT_STATUS_FILE = "/tmp/elephcinema-status"
DEFAULT_LOG_FILE = os.path.expanduser("~/.local/share/elephcinema/elephcinema.log")


def load_config():
    """Read KEY=VALUE config file, return dict."""
    config = {}
    config_path = os.environ.get(
        "ELEPHCINEMA_CONFIG",
        os.path.expanduser("~/.config/elephcinema/config")
    )
    if os.path.isfile(config_path):
        with open(config_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, _, value = line.partition("=")
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    # Expand $HOME / ~
                    value = os.path.expandvars(value)
                    value = os.path.expanduser(value)
                    config[key] = value
    return config


class ElephcinemaIndicator:
    def __init__(self):
        config = load_config()
        self.status_file = config.get("ELEPHCINEMA_STATUS_FILE", DEFAULT_STATUS_FILE)
        self.log_file = config.get("ELEPHCINEMA_LOG_FILE", DEFAULT_LOG_FILE)

        self.indicator = AyatanaAppIndicator3.Indicator.new(
            "elephcinema-indicator",
            "media-optical",
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS
        )
        self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title("ELEPHCINEMA")

        self.menu = Gtk.Menu()

        self.status_item = Gtk.MenuItem(label="Status: Idle")
        self.status_item.set_sensitive(False)
        self.menu.append(self.status_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        log_item = Gtk.MenuItem(label="View Log")
        log_item.connect("activate", self.view_log)
        self.menu.append(log_item)

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", self.quit)
        self.menu.append(quit_item)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

        self.last_status = ""
        GLib.timeout_add_seconds(2, self.update_status)

    def update_status(self):
        try:
            if os.path.exists(self.status_file):
                with open(self.status_file, 'r') as f:
                    status = f.read().strip()

                if status != self.last_status:
                    self.last_status = status

                    if status == "scanning":
                        self.indicator.set_icon_full("media-optical-bd-rom", "Scanning")
                        self.status_item.set_label("Scanning disc...")
                    elif status.startswith("rip:"):
                        pct = status.split(":")[1]
                        self.indicator.set_icon_full("media-optical-bd-rom", f"Ripping {pct}%")
                        self.status_item.set_label(f"Ripping: {pct}%")
                    elif status.startswith("encode:"):
                        pct = status.split(":")[1]
                        self.indicator.set_icon_full("video-x-generic", f"Encoding {pct}%")
                        self.status_item.set_label(f"Encoding: {pct}%")
                    elif status.startswith("done:"):
                        title = status.split(":", 1)[1]
                        self.indicator.set_icon_full("emblem-ok-symbolic", "Done")
                        self.status_item.set_label(f"Done: {title}")
                    elif status.startswith("error:"):
                        msg = status.split(":", 1)[1]
                        self.indicator.set_icon_full("dialog-error", "Error")
                        self.status_item.set_label(f"Error: {msg}")
            else:
                if self.last_status != "idle":
                    self.indicator.set_icon_full("media-optical", "Idle")
                    self.status_item.set_label("Status: Idle")
                    self.last_status = "idle"
        except Exception as e:
            print(f"Error: {e}")

        return True

    def view_log(self, widget):
        os.system(f"xdg-open {self.log_file} &")

    def quit(self, widget):
        Gtk.main_quit()


if __name__ == "__main__":
    indicator = ElephcinemaIndicator()
    Gtk.main()

# qs-bar :3

My quickshell config, for Hyprland. Takes on inspiration with apple dynamic island design
Feel free
---

##  Features
3 different island each with different usage

### Left Island: Hardware Monitor
* **On Idle:** RAM usage (%), CPU temperature (°C), Battery (%).
* **On Hover:** Hover to reveal more indepth info:
  * **Memory:** Exact used vs. total GB.
  * **CPU Temperature:** Show in a graph.
  * **Battery Details:** Charge percentage, live power draw in Watts, and estimated time remaining (or time to full).

### Middle Island: Clock, Media & Notifs
* Cycle through 3 different menu when click on empty space on the island. 
* On clock menu and media menu, they have different idle menu. To use either one, cycle to the menu you want to use the idle display, then move away from the island to activate
* OSD for Volume, Brightness

### Right Island: Control Center & Legion Controls
* Control for Wifi, Bluetooth, DND function, Power Options
* Legion Control Options(for Lenovo Legion Laptop, tested on Lenovo Legion Pro 5i 16IAX10)

---

## Requirements

* **Compositor:** Hyprland
* **Shell Engine:** `quickshell` (>= 0.3.0)
* **Fonts:** `inter-font` (or SF Pro), `ttf-meslo-nerd` (or any Nerd Font with Material Design icons)
* **System Tools:**
  * `networkmanager` (`nmcli`)
  * `bluez`, `bluez-utils` (`bluetoothctl`, `rfkill`)
  * `power-profiles-daemon` (`powerprofilesctl`)
  * `brightnessctl`
  * `playerctl`
  * `wireplumber` (`wpctl`)
  * `wlogout`
  * `libnotify` (`notify-send`)

---

## Quick Install

Clone the repository and run the installer:

```bash
git clone https://github.com/YOUR_USERNAME/qs-bar.git
cd qs-bar
chmod +x install.sh
./install.sh
```

The installer will:
1. Verify system packages and fonts (with prompt to install via `pacman` if on Arch Linux).
2. Backup any existing island configuration.
3. Deploy QML files to `~/.config/quickshell/island/` and helper scripts to `~/.config/hypr/scripts/`.
4. Auto-detect your touchpad's device ID and configure the touchpad toggle.

---

## Hyprland Integration

### 1. Autostart

Add to your Hyprland configuration:

**If using `uwsm`:**
```ini
exec-once = uwsm app -- qs -p ~/.config/quickshell/island
```
*(Or in `hyprland.lua`: `hl.exec_cmd("uwsm app -- qs -p " .. os.getenv("HOME") .. "/.config/quickshell/island")`)*

**If not using `uwsm`:**
```ini
exec-once = qs -p ~/.config/quickshell/island
```

### 2. Keybindings

My keybinds for media control and stuff

```ini
# Hardware volume & media controls
bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindl  = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindl  = , XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bindl  = , XF86AudioPlay, exec, playerctl play-pause
bindl  = , XF86AudioNext, exec, playerctl next
bindl  = , XF86AudioPrev, exec, playerctl previous

# Smart dual-GPU brightness control (Intel / Nvidia)
bindel = , XF86MonBrightnessUp, exec, ~/.config/hypr/scripts/backlight.sh 5%+
bindel = , XF86MonBrightnessDown, exec, ~/.config/hypr/scripts/backlight.sh 5%-

# Touchpad toggle (Fn+F10)
bindl  = , XF86TouchpadToggle, exec, ~/.config/hypr/scripts/touchpad-toggle.sh
```


# qs-bar :3

A modular, Apple-inspired Dynamic Island suite built with **[Quickshell](https://quickshell.outfoxxed.me/)** for **[Hyprland](https://hyprland.org/)**.

Designed with smooth deceleration curves (`Easing.OutCubic`), high-DPI scaling support, native PipeWire audio, and full Lenovo Legion hardware support.

---

## ✨ Features

### 1. 📊 Left Island: Hardware & Resource Monitor
* **Idle Pill:** Live RAM usage (%), CPU temperature (°C), and an Apple-style battery glyph whose inner fill and color match real charge level with a lightning bolt when charging.
* **Expanded Bar Graphs:** Hover to reveal three sideways bar graphs:
  * **Memory:** Exact used vs. total GB (e.g. `6.2 / 30.8 GB`).
  * **CPU Temperature:** Metered 0–100 °C bar graph.
  * **Battery Details:** Charge percentage, live power draw in Watts, and estimated time remaining (or time to full).

### 2. 🎵 Middle Island: Dynamic Island, Media & Notification Center
* **Idle:** Clean Apple-style clock and current workspace number.
* **Compact Media Pill:** Shown when audio is playing; features album art, a centered clock, and tinted live audio waveform bars.
* **Smart OSD Sliders:**
  * **Volume:** Appears automatically on volume change with percentage and speaker status.
  * **Brightness:** Dynamically queries whichever GPU (Intel iGPU or Nvidia dGPU) is driving the screen.
  * **Workspace Switch:** Temporary indicator dots when switching workspaces.
* **Notification System:**
  * **Non-hover Banner:** Expands with the sender app's icon, displays `"New Notification"` for 1.4s, then smoothly scrolls the notification title and message body across the pill.
  * **Direct Hover:** Hovering while a notification is active jumps straight to the Notification Center.
* **Expanded Menus (Click empty space to cycle):**
  * **Now Playing:** Full album art, title, artist, seek bar, and playback controls.
  * **Dashboard:** Large time, full date, volume controls, and clickable workspace buttons.
  * **Notification Center:** Organizes notifications into **Now**, **Today**, **Yesterday**, and **Older**, grouped by application. Supports clicking notifications to trigger actions and includes a "Clear All" button.
* **Quick Controls:** Scroll to change volume, middle-click to play/pause, right-click to mute.

### 3. 🎛️ Right Island: Control Center & Legion Controls
* **Idle (Adaptive Sizing):** Automatically expands or shrinks to fit your Wi-Fi SSID and stepped cellular-style signal bars. Dynamically expands when Bluetooth connects to show device name or count.
* **3-Tab Menu (On Hover):**
  * **Wi-Fi:** Scan and list available networks with signal strength. Clicking password-protected networks opens an inline password input.
  * **Bluetooth:** Lists connected devices at top and paired devices below. Features a search button that clears the paired view to discover new devices by friendly name.
  * **Quick Controls:**
    * Single horizontal row of 4 Apple Control Center-style squircle buttons: **Wi-Fi**, **Bluetooth**, **Do Not Disturb (Focus)**, and **Power** (`wlogout`).
    * **Legion Control Section:**
      * **Power Mode:** Cycles through Lenovo Legion thermal modes on click: 🔵 **Quiet (Blue)** ➔ ⚪ **Balanced (White)** ➔ 🔴 **Performance (Red)**.
      * **Touchpad Toggle:** Enable/disable laptop touchpad dynamically via Hyprland device API.
      * **Dual Fan Monitor:** Live RPM readout for dual cooling fans (`fan1` and `fan2`).

---

## 📦 Requirements

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

## 🚀 Quick Install

Clone the repository and run the installer:

```bash
git clone https://github.com/YOUR_USERNAME/hyprland-dynamic-island.git
cd hyprland-dynamic-island
chmod +x install.sh
./install.sh
```

The installer will:
1. Verify system packages and fonts (with prompt to install via `pacman` if on Arch Linux).
2. Backup any existing island configuration.
3. Deploy QML files to `~/.config/quickshell/island/` and helper scripts to `~/.config/hypr/scripts/`.
4. Auto-detect your touchpad's device ID and configure the touchpad toggle.

---

## ⚙️ Hyprland Integration

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

### 2. Recommended Keybindings

In your Hyprland keybinds file:

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

---

## 🎨 Customization

* **Spacing and Sizing:** Adjust `gap` and `compactH` in [Style.qml](config/quickshell/island/Style.qml).
* **Colors & Fonts:** Modify color definitions in [Style.qml](config/quickshell/island/Style.qml).
* **Animations:** Tuned using `Easing.OutCubic` with `300ms` duration in [Island.qml](config/quickshell/island/Island.qml), [StatsIsland.qml](config/quickshell/island/StatsIsland.qml), and [ControlIsland.qml](config/quickshell/island/ControlIsland.qml).

---

## 📄 License
MIT License. Feel free to use, modify, and distribute.

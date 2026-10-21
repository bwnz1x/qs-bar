#!/usr/bin/env bash
set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Dynamic Island for Hyprland - Installer          ${NC}"
echo -e "${BLUE}====================================================${NC}"

# Detect Package Manager
if command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"
else
    echo -e "${YELLOW}Warning: Non-Arch Linux system detected. Please ensure dependencies are manually installed.${NC}"
    PKG_MANAGER="unknown"
fi

# 1. Dependency List
PACKAGES=(
    "quickshell"
    "hyprland"
    "networkmanager"
    "bluez"
    "bluez-utils"
    "power-profiles-daemon"
    "brightnessctl"
    "playerctl"
    "wireplumber"
    "wlogout"
    "libnotify"
)

FONTS=(
    "inter-font"
    "ttf-meslo-nerd"
)

if [ "$PKG_MANAGER" = "pacman" ]; then
    echo -e "\n${BLUE}[1/4] Checking system dependencies...${NC}"
    MISSING_PKGS=()
    for pkg in "${PACKAGES[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null && ! pacman -Qg "$pkg" &>/dev/null; then
            MISSING_PKGS+=("$pkg")
        fi
    done

    for font in "${FONTS[@]}"; do
        if ! pacman -Qi "$font" &>/dev/null; then
            MISSING_PKGS+=("$font")
        fi
    done

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Missing packages detected: ${MISSING_PKGS[*]}${NC}"
        read -rp "Would you like to install them now with sudo pacman? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            sudo pacman -S --needed "${MISSING_PKGS[@]}"
        else
            echo -e "${YELLOW}Continuing without installing missing packages. Some features may not work.${NC}"
        fi
    else
        echo -e "${GREEN}✓ All core packages and fonts are installed.${NC}"
    fi
fi

# 2. Deploy Configuration Files
echo -e "\n${BLUE}[2/4] Deploying configuration files...${NC}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ISLAND_DIR="$HOME/.config/quickshell/island"
TARGET_SCRIPTS_DIR="$HOME/.config/hypr/scripts"

# Backup existing island config if present
if [ -d "$TARGET_ISLAND_DIR" ]; then
    BACKUP_DIR="$HOME/.config/quickshell/island.backup.$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}Existing island config found. Backing up to: $BACKUP_DIR${NC}"
    mv "$TARGET_ISLAND_DIR" "$BACKUP_DIR"
fi

mkdir -p "$TARGET_ISLAND_DIR"
mkdir -p "$TARGET_SCRIPTS_DIR"

# Copy files
cp -r "$REPO_DIR/config/quickshell/island/"* "$TARGET_ISLAND_DIR/"
cp -r "$REPO_DIR/config/hypr/scripts/"* "$TARGET_SCRIPTS_DIR/"
chmod +x "$TARGET_SCRIPTS_DIR"/*.sh

echo -e "${GREEN}✓ Config files installed to $TARGET_ISLAND_DIR${NC}"
echo -e "${GREEN}✓ Helper scripts installed to $TARGET_SCRIPTS_DIR${NC}"

# 3. Touchpad Device Auto-Detection
echo -e "\n${BLUE}[3/4] Checking laptop touchpad device...${NC}"
TOUCHPAD_SCRIPT="$TARGET_SCRIPTS_DIR/touchpad-toggle.sh"
if command -v hyprctl &>/dev/null; then
    DETECTED_TP=$(hyprctl devices -j 2>/dev/null | grep -o '"[a-zA-Z0-9_:.-]*touchpad"' | head -1 | tr -d '"' || true)
    if [ -n "$DETECTED_TP" ]; then
        echo -e "${GREEN}✓ Detected touchpad device: $DETECTED_TP${NC}"
        sed -i "s|DEV=\".*\"|DEV=\"$DETECTED_TP\"|" "$TOUCHPAD_SCRIPT"
        sed -i "s|name = \\\"[^\"]*touchpad\\\"|name = \\\"$DETECTED_TP\\\"|" "$TARGET_ISLAND_DIR/ControlIsland.qml"
    else
        echo -e "${YELLOW}Note: No active touchpad detected, keeping default device profile.${NC}"
    fi
fi

# 4. Instructions for Autostart
echo -e "\n${BLUE}[4/4] Installation Complete!${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "To start the Dynamic Island right now, run:"
echo -e "  ${YELLOW}qs -p ~/.config/quickshell/island${NC}"
echo -e ""
echo -e "To autostart on Hyprland startup:"
echo -e "  If using ${BLUE}uwsm${NC}:"
echo -e "    ${YELLOW}hl.exec_cmd(\"uwsm app -- qs -p \" .. os.getenv(\"HOME\") .. \"/.config/quickshell/island\")${NC} (Lua)"
echo -e "    or in hyprland.conf:"
echo -e "    ${YELLOW}exec-once = uwsm app -- qs -p ~/.config/quickshell/island${NC}"
echo -e "  If running standard Hyprland without uwsm:"
echo -e "    ${YELLOW}exec-once = qs -p ~/.config/quickshell/island${NC}"
echo -e "${GREEN}====================================================${NC}"

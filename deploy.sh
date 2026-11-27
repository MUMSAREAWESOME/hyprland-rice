#!/usr/bin/env bash
# deploy.sh: set up the hyprland rice on Arch Linux
set -Eeuo pipefail

REPO_URL="https://github.com/MUMSAREAWESOME/hyprland-rice"
REPO_DIR="$HOME/hyprland-rice"
CONFIG_DIR="$HOME/.config"
PICTURES_DIR="$HOME/Pictures"
SDDM_THEME="/usr/share/sddm/themes/sddm-astronaut-theme"
EVA_REPO="https://github.com/charichard08/Evangelion-archive"
EVA_DIR="$HOME/Evangelion-archive"
LOG_FILE="$HOME/deploy-$(date +%Y%m%d-%H%M%S).log"

OFFICIAL_PKGS=(
  noctalia kew superfile imagemagick bluez bluez-utils
  helix steam sddm starship fish fastfetch kitty
  gstreamer gst-plugins-good gst-plugins-bad gst-plugins-ugly
)
AUR_PKGS=(
  bibata-cursor-theme
  umbriel-git
  xdg-desktop-portal-umbriel
  librewolf
)

AUR_FAILED=()
WARNINGS=()

# Log everything to the terminal and to a file
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*"; WARNINGS+=("$*"); }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

trap 'echo "ERROR: failed at line $LINENO. Full log: $LOG_FILE" >&2' ERR

# Copy the contents of a folder into a destination, merging instead of nesting
copy_dir() {
  local src="$1" dst="$2"
  if [ ! -d "$src" ]; then
    warn "missing folder in repo: $src (skipped)"
    return 0
  fi
  mkdir -p "$dst"
  cp -r "$src"/. "$dst"/
}

# Copy a single file, skipping with a warning if it's not in the repo
copy_file() {
  local src="$1" dst="$2"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
  else
    warn "missing file in repo: $src (skipped)"
  fi
}

# Sanity checks
[ "$EUID" -ne 0 ] || die "don't run this as root. Run it as your normal user; it uses sudo where needed."
[ -f /etc/arch-release ] || die "this script is for Arch Linux only."

log "Checking sudo access..."
sudo -v

log "Getting the repo..."
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only || warn "could not update repo (local changes?). Using the existing copy."
else
  git clone "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR/pc"

log "Installing official packages..."
sudo pacman -Syu --needed "${OFFICIAL_PKGS[@]}"

log "Making sure yay is installed..."
if ! command -v yay >/dev/null; then
  sudo pacman -S --needed --noconfirm base-devel git
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si)
  rm -rf "$tmp"
fi

log "Installing AUR packages (failures won't stop the script)..."
for pkg in "${AUR_PKGS[@]}"; do
  if ! yay -S --needed "$pkg"; then
    AUR_FAILED+=("$pkg")
  fi
done

log "Copying configs..."
copy_dir noctalia  "$CONFIG_DIR/noctalia"
copy_dir umbriel   "$CONFIG_DIR/umbriel"
copy_dir fastfetch "$CONFIG_DIR/fastfetch"
copy_dir fish      "$CONFIG_DIR/fish"
copy_dir kitty     "$CONFIG_DIR/kitty"
copy_file starship.toml "$CONFIG_DIR/starship.toml"

log "Copying wallpapers..."
copy_dir Wallpaper "$PICTURES_DIR/Wallpapers"

log "Setting dark mode..."
if ! gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null; then
  warn "could not set dark mode (no dconf session). Run it from inside Hyprland if you want it."
fi

log "Setting up SDDM theme..."
if [ ! -d "$SDDM_THEME" ]; then
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/keyitdev/sddm-astronaut-theme/master/setup.sh)"
fi
if [ -f "$REPO_DIR/letsnote/hyprland_kath.conf" ]; then
  sudo cp "$REPO_DIR/letsnote/hyprland_kath.conf" "$SDDM_THEME/Themes/"
else
  warn "hyprland_kath.conf not found in letsnote/ (skipped)"
fi
if [ -f "$REPO_DIR/letsnote/asuka.mp4" ]; then
  sudo cp "$REPO_DIR/letsnote/asuka.mp4" "$SDDM_THEME/Backgrounds/"
else
  warn "asuka.mp4 not found in letsnote/ (skipped)"
fi

log "Installing Evangelion theme..."
if [ ! -d "$EVA_DIR" ]; then
  git clone "$EVA_REPO" "$EVA_DIR"
fi
# This is a third-party script. Skim it first if you're unsure: less "$EVA_DIR/install.sh"
bash "$EVA_DIR/install.sh" || warn "Evangelion installer failed"

log "Enabling services..."
sudo systemctl enable --now bluetooth.service
sudo systemctl enable -f sddm.service   # -f switches the display manager to sddm

log "Setting fish as the default shell..."
FISH_PATH="$(command -v fish)"
if ! grep -qx "$FISH_PATH" /etc/shells; then
  echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
fi
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [ "$CURRENT_SHELL" != "$FISH_PATH" ]; then
  chsh -s "$FISH_PATH"
fi

log "Summary"
if [ "${#AUR_FAILED[@]}" -gt 0 ]; then
  echo "AUR packages that failed: ${AUR_FAILED[*]}"
  echo "Usually this is a dead dependency. Check the output above."
fi
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo "Warnings:"
  printf '  - %s\n' "${WARNINGS[@]}"
fi
echo "Full log: $LOG_FILE"
echo "Done! Reboot to land in SDDM."

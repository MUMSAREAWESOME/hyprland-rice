#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/MUMSAREAWESOME/hyprland-rice"
REPO_DIR="$HOME/hyprland-rice"

OFFICIAL_PKGS=(
  noctalia kew superfile imagemagick bluez bluez-utils
  helix steam sddm starship fish fastfetch kitty
  gstreamer gst-plugins-good gst-plugins-bad gst-plugins-ugly
)
AUR_PKGS=(
  bibata-cursor-theme luciole umbriel xdg-desktop-portal-umbriel librewolf
)

log() { printf '\n==> %s\n' "$*"; }

# Copy the contents of a folder into a destination, merging instead of nesting
copy_dir() {
  mkdir -p "$2"
  cp -r "$1"/. "$2"/
}

log "Getting the repo..."
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR/pc"

log "Installing official packages..."
sudo pacman -Syu --needed "${OFFICIAL_PKGS[@]}"

log "Installing AUR packages (failures won't stop the script)..."
if ! command -v yay >/dev/null; then
  echo "yay isn't installed. Install it from the AUR first, then re-run."
  exit 1
fi
AUR_FAILED=()
for pkg in "${AUR_PKGS[@]}"; do
  if ! yay -S --needed "$pkg"; then
    AUR_FAILED+=("$pkg")
  fi
done

log "Copying configs..."
copy_dir noctalia   "$HOME/.config/noctalia"
copy_dir umbriel    "$HOME/.config/umbriel"
copy_dir fastfetch  "$HOME/.config/fastfetch"
copy_dir fish       "$HOME/.config/fish"
copy_dir kitty      "$HOME/.config/kitty"
cp starship.toml "$HOME/.config/starship.toml"

log "Copying wallpapers..."
copy_dir Wallpaper "$HOME/Pictures/Wallpapers"

log "Setting dark mode..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' \
  || echo "gsettings failed (no dconf session?), skipping"

log "Setting up SDDM theme..."
if [ ! -d /usr/share/sddm/themes/sddm-astronaut-theme ]; then
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/keyitdev/sddm-astronaut-theme/master/setup.sh)"
fi
sudo cp "$REPO_DIR/letsnote/hyprland_kath.conf" \
  /usr/share/sddm/themes/sddm-astronaut-theme/Themes/
sudo cp "$REPO_DIR/letsnote/asuka.mp4" \
  /usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds/

log "Installing Evangelion theme..."
EVA_DIR="$HOME/Evangelion-archive"
if [ ! -d "$EVA_DIR" ]; then
  git clone https://github.com/charichard08/Evangelion-archive "$EVA_DIR"
fi
bash "$EVA_DIR/install.sh"

log "Enabling services..."
sudo systemctl enable --now bluetooth.service
sudo systemctl enable sddm.service   # takes effect on reboot, doesn't kick you out now

log "Setting fish as default shell..."
FISH_PATH="$(command -v fish)"
grep -qx "$FISH_PATH" /etc/shells || echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
chsh -s "$FISH_PATH"

log "Summary"
if [ "${#AUR_FAILED[@]}" -gt 0 ]; then
  echo "These AUR packages failed to install: ${AUR_FAILED[*]}"
  echo "Check the output above. A dependency like python2-imaging is the usual cause."
  echo "The rest of the rice was still set up."
else
  echo "All AUR packages installed."
fi
echo "Done! Reboot to land in SDDM."

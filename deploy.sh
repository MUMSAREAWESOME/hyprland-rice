#!/usr/bin/env bash
# setup.sh: set up the hyprland rice on Arch Linux.
#
#   1. installs packages (pacman, then yay for AUR)
#   2. copies configs from pc/, then copies letsnote/ on top (letsnote wins on conflicts)
#   3. installs the astronaut SDDM theme with your Kath config and video
#   4. enables services and sets fish as your shell
#
#   ./setup.sh               install everything
#   ./setup.sh --no-sddm     skip the SDDM login screen
#   ./setup.sh --grub        also install the Evangelion GRUB themes (pick SEELE in the installer)
set -Eeuo pipefail

INSTALL_SDDM=1
WITH_GRUB=0
for arg in "$@"; do
  case "$arg" in
    --no-sddm) INSTALL_SDDM=0 ;;
    --grub)    WITH_GRUB=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

# ---------- settings ----------

REPO_URL="https://github.com/MUMSAREAWESOME/hyprland-rice"
REPO_DIR="$HOME/Documents/GitHub/hyprland-rice"
PC="$REPO_DIR/pc"
LETSNOTE="$REPO_DIR/letsnote"
CONF="$HOME/.config"

ASTRONAUT_URL="https://github.com/keyitdev/sddm-astronaut-theme.git"
THEME="sddm-astronaut-theme"
THEME_DIR="/usr/share/sddm/themes/$THEME"
SDDM_CONF_DIR="/etc/sddm.conf.d"

EVA_VERSION="2.1.0"
EVA_TAR="evangelion-${EVA_VERSION}.tar.gz"
EVA_URL="https://github.com/Aleph1-9012/Evangelion/releases/download/v${EVA_VERSION}"
EVA_DIR="$HOME/Evangelion-${EVA_VERSION}"

OFFICIAL_PKGS=(
  hyprland xdg-desktop-portal-hyprland
  noctalia kew superfile imagemagick bluez bluez-utils
  helix steam sddm starship fish fastfetch kitty curl git
  gstreamer gst-plugins-good gst-plugins-bad gst-plugins-ugly
  qt6-svg qt6-virtualkeyboard qt6-declarative qt6-multimedia-ffmpeg
)
AUR_PKGS=(xdg-desktop-portal-umbriel-git)

WARNINGS=()
AUR_FAILED=()

# ---------- helpers ----------

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*"; WARNINGS+=("$*"); }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
trap 'die "failed on line $LINENO"' ERR

# Copy a folder's contents into a destination, merging instead of nesting
copy_tree() {
  local src="$1" dst="$2"
  if [ ! -d "$src" ]; then warn "missing folder: $src"; return 0; fi
  mkdir -p "$dst"
  cp -r "$src"/. "$dst"/
}

# Copy one file into a destination, creating parent folders as needed
copy_file() {
  local src="$1" dst="$2"
  if [ ! -f "$src" ]; then warn "missing file: $src"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

# ---------- checks ----------

[ "$EUID" -ne 0 ] || die "don't run as root. Run it as your normal user."
[ -f /etc/arch-release ] || die "this script is for Arch Linux only."
log "Checking sudo..."
sudo -v

# ---------- repo ----------

log "Getting the rice repo..."
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only || warn "could not update the repo, using the existing copy"
else
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
fi

# ---------- packages ----------

log "Installing official packages..."
sudo pacman -Syu --needed "${OFFICIAL_PKGS[@]}"

log "Making sure yay is installed..."
if ! command -v yay >/dev/null; then
  sudo pacman -S --needed --noconfirm base-devel
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
fi

log "Installing AUR packages..."
for pkg in "${AUR_PKGS[@]}"; do
  yay -S --needed "$pkg" || AUR_FAILED+=("$pkg")
done

# ---------- configs ----------

log "Copying base configs from pc/..."
copy_tree "$PC/noctalia"  "$CONF/noctalia"
copy_tree "$PC/umbriel"   "$CONF/umbriel"
copy_tree "$PC/fastfetch" "$CONF/fastfetch"
copy_tree "$PC/fish"      "$CONF/fish"
copy_tree "$PC/kitty"     "$CONF/kitty"
copy_file "$PC/starship.toml" "$CONF/starship.toml"
copy_tree "$PC/Wallpaper" "$HOME/Pictures/Wallpapers"

log "Overlaying letsnote/ configs..."
copy_tree "$LETSNOTE/hypr"   "$CONF/hypr"
copy_tree "$LETSNOTE/helix"  "$CONF/helix"
copy_tree "$LETSNOTE/fish"   "$CONF/fish"
copy_tree "$LETSNOTE/kitty"  "$CONF/kitty"
copy_file "$LETSNOTE/starship.toml" "$CONF/starship.toml"

log "Setting dark mode..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null \
  || warn "could not set dark mode (no dconf session). Run it from inside Hyprland if you want it."

# ---------- SDDM ----------

if [ "$INSTALL_SDDM" -eq 1 ]; then
  log "Installing the astronaut SDDM theme..."
  tmp="$(mktemp -d)"
  git clone --depth 1 "$ASTRONAUT_URL" "$tmp/astronaut"
  sudo rm -rf "$THEME_DIR"
  sudo cp -r "$tmp/astronaut" "$THEME_DIR"
  rm -rf "$tmp"
  [ -f "$THEME_DIR/metadata.desktop" ] || die "theme install failed: no metadata.desktop"

  log "Installing theme fonts..."
  sudo mkdir -p /usr/share/fonts
  sudo cp -r "$THEME_DIR/Fonts/." /usr/share/fonts/

  log "Adding your Kath config and video..."
  if [ -f "$LETSNOTE/hyprland_kath.conf" ]; then
    sudo install -Dm644 "$LETSNOTE/hyprland_kath.conf" "$THEME_DIR/Themes/hyprland_kath.conf"
    sudo sed -i 's|^ConfigFile=.*|ConfigFile=Themes/hyprland_kath.conf|' "$THEME_DIR/metadata.desktop"
  else
    warn "hyprland_kath.conf not found in letsnote/"
  fi
  if [ -f "$LETSNOTE/asuka.mp4" ]; then
    sudo install -Dm644 "$LETSNOTE/asuka.mp4" "$THEME_DIR/Backgrounds/asuka.mp4"
  else
    warn "asuka.mp4 not found in letsnote/"
  fi

  log "Pointing SDDM at the theme..."
  sudo mkdir -p "$SDDM_CONF_DIR"
  printf '[Theme]\nCurrent=%s\n' "$THEME" | sudo tee "$SDDM_CONF_DIR/10-theme.conf" >/dev/null
  printf '[General]\nInputMethod=qtvirtualkeyboard\n' | sudo tee "$SDDM_CONF_DIR/virtualkbd.conf" >/dev/null
fi

# ---------- GRUB (optional) ----------

if [ "$WITH_GRUB" -eq 1 ]; then
  log "Downloading the Evangelion GRUB themes v${EVA_VERSION}..."
  mkdir -p "$EVA_DIR"
  curl -fL -o "$EVA_DIR/$EVA_TAR" "$EVA_URL/$EVA_TAR"
  curl -fL -o "$EVA_DIR/$EVA_TAR.sha256" "$EVA_URL/$EVA_TAR.sha256"

  log "Verifying the download..."
  (cd "$EVA_DIR" && sha256sum -c "$EVA_TAR.sha256") || die "checksum mismatch. Not installing."

  log "Extracting..."
  tar -xzf "$EVA_DIR/$EVA_TAR" -C "$EVA_DIR"

  log "Running the Evangelion installer. Pick SEELE and your profile when it asks."
  # This changes your bootloader config. Read it first: less "$EVA_DIR/Evangelion/install.sh"
  (cd "$EVA_DIR/Evangelion" && sudo ./install.sh) \
    || warn "Evangelion installer did not finish. Check the output above."
fi

# ---------- services and shell ----------

log "Enabling services..."
sudo systemctl enable --now bluetooth.service
if [ "$INSTALL_SDDM" -eq 1 ]; then
  sudo systemctl enable -f sddm.service
fi

log "Setting fish as your shell..."
fish_path="$(command -v fish)"
grep -qx "$fish_path" /etc/shells || echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$fish_path" ]; then
  chsh -s "$fish_path"
fi

# ---------- summary ----------

log "Summary"
if [ "${#AUR_FAILED[@]}" -gt 0 ]; then
  echo "AUR packages that failed: ${AUR_FAILED[*]}"
fi
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo "Warnings:"
  printf '  - %s\n' "${WARNINGS[@]}"
fi
echo "Done. Reboot to reach the login screen."
if [ "$INSTALL_SDDM" -eq 1 ]; then
  echo "Preview the SDDM theme without rebooting:"
  echo "  sddm-greeter-qt6 --test-mode --theme $THEME_DIR"
fi
#!/usr/bin/env bash
# rice.sh: install (default) or undo (--undo) the hyprland rice on Arch.
#
#   ./rice.sh                     install
#   ./rice.sh --undo              undo, asking before each system-level change
#   ./rice.sh --undo -y           auto-yes routine undo prompts
#                                 (never package removal or deleting clones)
#   ./rice.sh --undo --packages   also offer to uninstall packages
set -Eeuo pipefail

MODE=install
ASSUME_YES=0
REMOVE_PKGS=0
for arg in "$@"; do
  case "$arg" in
    --undo)     MODE=undo ;;
    -y|--yes)   ASSUME_YES=1 ;;
    --packages) REMOVE_PKGS=1 ;;
    -h|--help)  sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

REPO_URL="https://github.com/MUMSAREAWESOME/hyprland-rice"
REPO_DIR="$HOME/hyprland-rice"
PC="$REPO_DIR/pc"
LETSNOTE="$REPO_DIR/letsnote"
CONFIG_DIR="$HOME/.config"
PICTURES_DIR="$HOME/Pictures"
SDDM_THEME_DIR="/usr/share/sddm/themes/sddm-astronaut-theme"
SDDM_CONF="/etc/sddm.conf.d/10-theme.conf"
ASTRONAUT_REPO="https://github.com/keyitdev/sddm-astronaut-theme.git"
EVA_REPO="https://github.com/charichard08/Evangelion-archive"
EVA_DIR="$HOME/Evangelion-archive"
LOG_FILE="$HOME/rice-$MODE-$(date +%Y%m%d-%H%M%S).log"

OFFICIAL_PKGS=(
  noctalia kew superfile imagemagick bluez bluez-utils
  helix steam sddm starship fish fastfetch kitty
  gstreamer gst-plugins-good gst-plugins-bad gst-plugins-ugly
  qt6-svg qt6-virtualkeyboard qt6-declarative qt6-multimedia-ffmpeg
)
AUR_PKGS=(
  umbriel-git
  xdg-desktop-portal-umbriel-git
)

AUR_FAILED=()
WARNINGS=()

# Log everything to the terminal and to a file
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*"; WARNINGS+=("$*"); }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

trap 'printf "ERROR: failed at line %s. Full log: %s\n" "$LINENO" "$LOG_FILE" >&2' ERR

# ---------- prompts ----------

# Honors -y
confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local ans
  read -rp "$1 [y/N] " ans || true
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Never auto-yes, even with -y
confirm_always() {
  local ans
  read -rp "$1 [y/N] " ans || true
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ---------- install helpers ----------

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

# Root-owned copy, skipping with a warning if the source is missing
sudo_install_file() {
  local src="$1" dst="$2"
  if [ -f "$src" ]; then
    sudo install -Dm644 "$src" "$dst"
  else
    warn "missing file in repo: $src (skipped)"
  fi
}

# ---------- undo helpers ----------

# Delete files in $dst that match $src, then prune empty folders.
# Anything modified since deploying is kept and reported.
unuse_dir() {
  local src="$1" dst="$2"
  [ -d "$src" ] && [ -d "$dst" ] || return 0
  while IFS= read -r -d '' f; do
    if cmp -s -- "$src/$f" "$dst/$f"; then
      rm -f -- "$dst/$f"
    else
      note "kept (modified): $dst/$f"
    fi
  done < <(cd "$src" && find . -type f -print0)
  find "$dst" -depth -type d -empty -delete 2>/dev/null || true
}

# Delete one file only if it matches the repo copy (for root-owned files)
remove_same_sudo() {
  local src="$1" dst="$2"
  [ -f "$src" ] && [ -f "$dst" ] || return 0
  if cmp -s -- "$src" "$dst"; then
    sudo rm -f -- "$dst"
    note "removed: $dst"
  else
    note "kept (modified): $dst"
  fi
}

# ---------- install ----------

do_install() {
  log "Getting the repo..."
  if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --ff-only || warn "could not update repo (local changes?). Using the existing copy."
  else
    git clone "$REPO_URL" "$REPO_DIR"
  fi
  cd "$PC"

  log "Installing official packages..."
  sudo pacman -Syu --needed "${OFFICIAL_PKGS[@]}"

  log "Making sure yay is installed..."
  if ! command -v yay >/dev/null; then
    sudo pacman -S --needed --noconfirm base-devel git
    local tmp
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

  log "Installing the astronaut SDDM theme..."
  local tmp
  tmp="$(mktemp -d)"
  git clone --depth 1 "$ASTRONAUT_REPO" "$tmp/astronaut"
  sudo rm -rf "$SDDM_THEME_DIR"
  sudo cp -r "$tmp/astronaut" "$SDDM_THEME_DIR"
  rm -rf "$tmp"

  log "Pointing SDDM at the theme and your Kath config..."
  sudo mkdir -p "$(dirname "$SDDM_CONF")"
  printf '[Theme]\nCurrent=sddm-astronaut-theme\n' | sudo tee "$SDDM_CONF" >/dev/null
  sudo_install_file "$LETSNOTE/hyprland_kath.conf" "$SDDM_THEME_DIR/Themes/hyprland_kath.conf"
  sudo_install_file "$LETSNOTE/asuka.mp4" "$SDDM_THEME_DIR/Backgrounds/asuka.mp4"
  if [ -f "$SDDM_THEME_DIR/metadata.desktop" ]; then
    sudo sed -i 's|^ConfigFile=.*|ConfigFile=Themes/hyprland_kath.conf|' "$SDDM_THEME_DIR/metadata.desktop"
  else
    warn "metadata.desktop missing from the astronaut theme; the Kath config was not selected"
  fi

  log "Installing Evangelion theme..."
  if [ ! -d "$EVA_DIR" ]; then
    git clone "$EVA_REPO" "$EVA_DIR"
  fi
  # Third-party script. Read it first if you're unsure: less "$EVA_DIR/install.sh"
  bash "$EVA_DIR/install.sh" || warn "Evangelion installer failed"

  log "Enabling services..."
  sudo systemctl enable --now bluetooth.service
  sudo systemctl enable -f sddm.service   # -f switches the display manager to sddm

  log "Setting fish as the default shell..."
  local fish_path current_shell
  fish_path="$(command -v fish)"
  if ! grep -qx "$fish_path" /etc/shells; then
    echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
  fi
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [ "$current_shell" != "$fish_path" ]; then
    chsh -s "$fish_path"
  fi

  log "Summary"
  if [ "${#AUR_FAILED[@]}" -gt 0 ]; then
    echo "AUR packages that failed: ${AUR_FAILED[*]}"
    echo "Usually this is a dead dependency. Check the output above."
  fi
  print_warnings
  echo "Full log: $LOG_FILE"
  echo "Done! Reboot to land in SDDM."
}

# ---------- undo ----------

do_undo() {
  if [ ! -d "$REPO_DIR" ]; then
    warn "repo not found at $REPO_DIR, so configs can't be matched and will be left alone"
  fi

  log "Removing copied configs (only files identical to the repo's)..."
  for d in noctalia umbriel fastfetch fish kitty; do
    unuse_dir "$PC/$d" "$CONFIG_DIR/$d"
  done
  if [ -f "$PC/starship.toml" ] && [ -f "$CONFIG_DIR/starship.toml" ] \
     && cmp -s -- "$PC/starship.toml" "$CONFIG_DIR/starship.toml"; then
    rm -f -- "$CONFIG_DIR/starship.toml"
    note "removed: $CONFIG_DIR/starship.toml"
  fi
  unuse_dir "$PC/Wallpaper" "$PICTURES_DIR/Wallpapers"

  log "Restoring default shell..."
  local fish_path current_shell bash_path
  fish_path="$(command -v fish || true)"
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  bash_path="$(command -v bash)"
  if [ -n "$fish_path" ] && [ "$current_shell" = "$fish_path" ] \
     && confirm "Switch your login shell back to bash?"; then
    chsh -s "$bash_path" && note "shell set back to bash"
  fi
  note "/etc/shells still lists fish. That's harmless, so I left it alone."

  log "SDDM files..."
  remove_same_sudo "$LETSNOTE/hyprland_kath.conf" "$SDDM_THEME_DIR/Themes/hyprland_kath.conf"
  remove_same_sudo "$LETSNOTE/asuka.mp4" "$SDDM_THEME_DIR/Backgrounds/asuka.mp4"
  if [ -f "$SDDM_CONF" ] && confirm "Remove $SDDM_CONF (the file that points SDDM at the astronaut theme)?"; then
    sudo rm -f -- "$SDDM_CONF"
    note "removed: $SDDM_CONF"
  fi
  if [ -d "$SDDM_THEME_DIR" ] && confirm_always "Remove the whole sddm-astronaut-theme folder? Only say yes if you didn't have it before deploy."; then
    sudo rm -rf -- "$SDDM_THEME_DIR"
    note "removed: $SDDM_THEME_DIR"
  fi

  log "Services..."
  if confirm_always "Disable sddm? You'll boot to a TTY, so re-enable your old display manager afterward (e.g. sudo systemctl enable -f gdm)."; then
    sudo systemctl disable sddm.service && note "sddm disabled"
  fi
  if confirm_always "Disable and stop bluetooth.service?"; then
    sudo systemctl disable --now bluetooth.service && note "bluetooth disabled"
  fi

  log "Cloned repos..."
  if [ -d "$EVA_DIR" ] && confirm_always "Delete $EVA_DIR? (this doesn't undo what its install.sh changed)"; then
    rm -rf -- "$EVA_DIR"
    note "removed: $EVA_DIR"
  fi
  if [ -d "$REPO_DIR" ] && confirm_always "Delete $REPO_DIR?"; then
    rm -rf -- "$REPO_DIR"
    note "removed: $REPO_DIR"
  fi

  if [ "$REMOVE_PKGS" -eq 1 ]; then
    log "Removing packages..."
    warn "Some of these may have been installed before deploy. Removing sddm, bluez or fish can leave you without a login screen or shell."
    note "yay itself is left installed."
    if confirm_always "Uninstall the packages this script installed? pacman lists what it would remove first."; then
      sudo pacman -Rs "${OFFICIAL_PKGS[@]}" || warn "some official packages were not removed (they may not be installed)"
      yay -Rs "${AUR_PKGS[@]}" || warn "some AUR packages were not removed (they may not be installed)"
    fi
  fi

  log "Summary"
  print_warnings
  note "Full log: $LOG_FILE"
  note "Reboot if you disabled sddm or changed the shell."
}

print_warnings() {
  if [ "${#WARNINGS[@]}" -gt 0 ]; then
    echo "Warnings:"
    printf '  - %s\n' "${WARNINGS[@]}"
  fi
}

# ---------- main ----------

[ "$EUID" -ne 0 ] || die "don't run this as root. Run it as your normal user; it uses sudo where needed."
[ -f /etc/arch-release ] || die "this script is for Arch Linux only."

log "Checking sudo access..."
sudo -v

if [ "$MODE" = install ]; then
  do_install
else
  do_undo
fi
EOF_MARKER_NOT_NEEDED

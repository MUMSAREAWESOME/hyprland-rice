#!/usr/bin/env bash
# rice.sh: install (default) or undo (--undo) the umbriel rice on Arch.
#
#   ./rice.sh                      install everything
#   ./rice.sh --no-sddm            skip the SDDM login screen
#   ./rice.sh --grub               also install the Evangelion GRUB themes (pick SEELE in the installer)
#   ./rice.sh --undo               remove what this script installed (asks before anything big)
#   ./rice.sh --undo -y            auto-yes routine prompts (never package removal or deletions)
#   ./rice.sh --undo --packages    also offer to uninstall the packages
set -Eeuo pipefail

MODE=install
ASSUME_YES=0
REMOVE_PKGS=0
INSTALL_SDDM=1
WITH_GRUB=0
for arg in "$@"; do
  case "$arg" in
    --undo)     MODE=undo ;;
    -y|--yes)   ASSUME_YES=1 ;;
    --packages) REMOVE_PKGS=1 ;;
    --no-sddm)  INSTALL_SDDM=0 ;;
    --grub)     WITH_GRUB=1 ;;
    -h|--help)  sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

# ---------- settings ----------

REPO_URL="https://github.com/MUMSAREAWESOME/hyprland-rice"
REPO_DIR="$HOME/Documents/GitHub/hyprland-rice"
PC="$REPO_DIR/pc"
LETSNOTE="$REPO_DIR/letsnote"   # only used for the SDDM files
CONF="$HOME/.config"
PICTURES="$HOME/Pictures"

ASTRONAUT_URL="https://github.com/keyitdev/sddm-astronaut-theme.git"
THEME="sddm-astronaut-theme"
THEME_DIR="/usr/share/sddm/themes/$THEME"
SDDM_CONF_DIR="/etc/sddm.conf.d"

EVA_VERSION="2.1.0"
EVA_TAR="evangelion-${EVA_VERSION}.tar.gz"
EVA_URL="https://github.com/Aleph1-9012/Evangelion/releases/download/v${EVA_VERSION}"
EVA_DIR="$HOME/Evangelion-${EVA_VERSION}"

LOG_FILE="$HOME/rice-$MODE-$(date +%Y%m%d-%H%M%S).log"

# No Hyprland here: the rice runs on umbriel, so Hyprland is not installed by this script.
OFFICIAL_PKGS=(
  noctalia kew superfile imagemagick bluez bluez-utils
  helix steam sddm starship fish fastfetch kitty curl git
  gstreamer gst-plugins-good gst-plugins-bad gst-plugins-ugly
  qt6-svg qt6-virtualkeyboard qt6-declarative qt6-multimedia-ffmpeg
)
AUR_PKGS=(
  umbriel-git
  luciole-git
  xdg-desktop-portal-umbriel-git
)
# Config mapping. Each entry is: destination|source
# Everything except SDDM comes from pc/.
TREES=(
  "$CONF/noctalia|$PC/noctalia"
  "$CONF/umbriel|$PC/umbriel"
  "$CONF/fastfetch|$PC/fastfetch"
  "$CONF/fish|$PC/fish"
  "$CONF/kitty|$PC/kitty"
  "$PICTURES/Wallpapers|$PC/Wallpaper"
)
FILES=(
  "$CONF/starship.toml|$PC/starship.toml"
)

AUR_FAILED=()
WARNINGS=()

# Log everything to the terminal and to a file
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------- helpers ----------

log()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*"; WARNINGS+=("$*"); }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
trap 'die "failed on line $LINENO. Full log: $LOG_FILE"' ERR

# Routine prompt: -y answers yes
confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local ans
  read -rp "$1 [y/N] " ans || true
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Destructive prompt: -y never answers for it
confirm_always() {
  local ans
  read -rp "$1 [y/N] " ans || true
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Copy a folder's contents into a destination, merging instead of nesting
copy_tree() {
  local src="$1" dst="$2"
  if [ ! -d "$src" ]; then warn "missing folder: $src"; return 0; fi
  mkdir -p "$dst"
  cp -r "$src"/. "$dst"/
}

# Copy one file, creating parent folders as needed
copy_file() {
  local src="$1" dst="$2"
  if [ ! -f "$src" ]; then warn "missing file: $src"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

# Undo: delete files in $dst that are byte-identical to the source.
# Anything modified since install is kept and reported. Empty folders are pruned.
unuse_tree() {
  local src="$1" dst="$2"
  [ -d "$src" ] && [ -d "$dst" ] || return 0
  local rel
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    if cmp -s -- "$src/$rel" "$dst/$rel"; then
      rm -f -- "$dst/$rel"
    else
      note "kept (modified): $dst/$rel"
    fi
  done < <(cd "$src" && find . -type f -print0)
  find "$dst" -depth -type d -empty -delete 2>/dev/null || true
}

# Undo: delete one file if it's byte-identical to the source
unuse_file() {
  local src="$1" dst="$2"
  [ -f "$dst" ] || return 0
  if [ -f "$src" ] && cmp -s -- "$src" "$dst"; then
    rm -f -- "$dst"
    note "removed: $dst"
  else
    note "kept (modified): $dst"
  fi
}

print_summary() {
  log "Summary"
  if [ "${#AUR_FAILED[@]}" -gt 0 ]; then
    echo "AUR packages that failed: ${AUR_FAILED[*]}"
  fi
  if [ "${#WARNINGS[@]}" -gt 0 ]; then
    echo "Warnings:"
    printf '  - %s\n' "${WARNINGS[@]}"
  fi
  echo "Full log: $LOG_FILE"
}

# ---------- install ----------

do_install() {
  log "Getting the rice repo..."
  if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --ff-only || warn "could not update the repo, using the existing copy"
  else
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
  fi

  log "Installing official packages..."
  sudo pacman -Syu --needed "${OFFICIAL_PKGS[@]}"

  log "Making sure yay is installed..."
  if ! command -v yay >/dev/null; then
    sudo pacman -S --needed --noconfirm base-devel
    local tmp
    tmp="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
  fi

  log "Installing AUR packages..."
  local pkg
  for pkg in "${AUR_PKGS[@]}"; do
    yay -S --needed "$pkg" || AUR_FAILED+=("$pkg")
  done

  log "Copying configs from pc/..."
  local entry dst src
  for entry in "${TREES[@]}"; do
    dst="${entry%%|*}"
    src="${entry#*|}"
    copy_tree "$src" "$dst"
  done
  for entry in "${FILES[@]}"; do
    dst="${entry%%|*}"
    src="${entry#*|}"
    copy_file "$src" "$dst"
  done

  log "Setting dark mode..."
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null \
    || warn "could not set dark mode (no dconf session). Run it from inside Hyprland if you want it."

  if [ "$INSTALL_SDDM" -eq 1 ]; then
    log "Installing the astronaut SDDM theme..."
    local tmp
    tmp="$(mktemp -d)"
    git clone --depth 1 "$ASTRONAUT_URL" "$tmp/astronaut"
    sudo rm -rf "$THEME_DIR"
    sudo cp -r "$tmp/astronaut" "$THEME_DIR"
    rm -rf "$tmp"
    [ -f "$THEME_DIR/metadata.desktop" ] || die "theme install failed: no metadata.desktop"

    log "Installing theme fonts..."
    sudo mkdir -p /usr/share/fonts
    sudo cp -r "$THEME_DIR/Fonts/." /usr/share/fonts/

    log "Adding your Kath config and video from letsnote/..."
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

  log "Enabling services..."
  sudo systemctl enable --now bluetooth.service
  if [ "$INSTALL_SDDM" -eq 1 ]; then
    sudo systemctl enable -f sddm.service
  fi

  log "Setting fish as your shell..."
  local fish_path
  fish_path="$(command -v fish)"
  grep -qx "$fish_path" /etc/shells || echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
  if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$fish_path" ]; then
    chsh -s "$fish_path"
  fi

  print_summary
  echo "Done. Reboot to reach the login screen."
  if [ "$INSTALL_SDDM" -eq 1 ]; then
    echo "Preview the SDDM theme without rebooting:"
    echo "  sddm-greeter-qt6 --test-mode --theme $THEME_DIR"
  fi
}

# ---------- undo ----------

do_undo() {
  log "Removing configs (only files identical to what this script copied)..."
  local entry dst src
  for entry in "${TREES[@]}"; do
    dst="${entry%%|*}"
    src="${entry#*|}"
    unuse_tree "$src" "$dst"
  done
  for entry in "${FILES[@]}"; do
    dst="${entry%%|*}"
    src="${entry#*|}"
    unuse_file "$src" "$dst"
  done

  log "Restoring your shell..."
  local fish_path current bash_path
  fish_path="$(command -v fish || true)"
  current="$(getent passwd "$USER" | cut -d: -f7)"
  bash_path="$(command -v bash)"
  if [ -n "$fish_path" ] && [ "$current" = "$fish_path" ] \
     && confirm "Switch your login shell back to bash?"; then
    chsh -s "$bash_path" && note "shell set back to bash"
  fi
  note "/etc/shells still lists fish. That's harmless, so I left it alone."

  log "SDDM files..."
  if [ -f "$SDDM_CONF_DIR/10-theme.conf" ] || [ -f "$SDDM_CONF_DIR/virtualkbd.conf" ]; then
    if confirm "Remove the SDDM config files this script wrote?"; then
      sudo rm -f -- "$SDDM_CONF_DIR/10-theme.conf" "$SDDM_CONF_DIR/virtualkbd.conf"
      note "removed the SDDM config files"
    fi
  fi
  if [ -d "$THEME_DIR" ] && confirm_always "Remove the astronaut theme folder (includes the Kath config and video)? Only say yes if you didn't have it before."; then
    sudo rm -rf -- "$THEME_DIR"
    note "removed: $THEME_DIR"
  fi
  note "Fonts copied to /usr/share/fonts were left in place."

  log "Services..."
  if confirm_always "Disable sddm? You'll boot to a TTY, so re-enable your old display manager afterward (e.g. sudo systemctl enable -f gdm)."; then
    sudo systemctl disable sddm.service && note "sddm disabled"
  fi
  if confirm_always "Disable and stop bluetooth.service?"; then
    sudo systemctl disable --now bluetooth.service && note "bluetooth disabled"
  fi

  log "Evangelion GRUB theme..."
  if [ -f "$EVA_DIR/Evangelion/install.sh" ]; then
    if confirm_always "Uninstall the Evangelion GRUB theme? This restores your previous GRUB settings."; then
      (cd "$EVA_DIR/Evangelion" && sudo ./install.sh --uninstall) \
        || warn "Evangelion uninstaller did not finish. Check the output above."
    fi
  else
    note "no Evangelion install found, skipping"
  fi

  log "Repo folders..."
  if [ -d "$EVA_DIR" ] && confirm_always "Delete $EVA_DIR?"; then
    rm -rf -- "$EVA_DIR"
    note "removed: $EVA_DIR"
  fi
  if [ -d "$REPO_DIR" ] && confirm_always "Delete the repo at $REPO_DIR?"; then
    rm -rf -- "$REPO_DIR"
    note "removed: $REPO_DIR"
  fi

  if [ "$REMOVE_PKGS" -eq 1 ]; then
    log "Packages..."
    warn "Some packages may have been installed before this script ran. Removing sddm, bluez, fish, or git can break login, the shell, or this script."
    local -a installed_official=() installed_aur=()
    local pkg
    for pkg in "${OFFICIAL_PKGS[@]}"; do
      if pacman -Qq "$pkg" >/dev/null 2>&1; then installed_official+=("$pkg"); fi
    done
    for pkg in "${AUR_PKGS[@]}"; do
      if pacman -Qq "$pkg" >/dev/null 2>&1; then installed_aur+=("$pkg"); fi
    done
    if [ "${#installed_official[@]}" -gt 0 ] && confirm_always "Uninstall these packages: ${installed_official[*]}?"; then
      sudo pacman -Rs "${installed_official[@]}" || warn "pacman did not remove everything. Check the output above."
    fi
    if [ "${#installed_aur[@]}" -gt 0 ] && confirm_always "Uninstall these AUR packages: ${installed_aur[*]}?"; then
      yay -Rs "${installed_aur[@]}" || warn "yay did not remove everything. Check the output above."
    fi
    note "yay itself is left installed."
  fi

  print_summary
  echo "Reboot if you disabled sddm or changed the shell."
}

# ---------- main ----------

[ "$EUID" -ne 0 ] || die "don't run as root. Run it as your normal user; it uses sudo where needed."
[ -f /etc/arch-release ] || die "this script is for Arch Linux only."

log "Checking sudo..."
sudo -v

if [ "$MODE" = install ]; then
  do_install
else
  do_undo
fi
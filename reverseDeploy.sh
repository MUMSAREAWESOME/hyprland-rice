#!/usr/bin/env bash
# reverseDeploy.sh: undo what deploy.sh did.
#
# Safe by default:
#   - only deletes config files that are byte-identical to the repo copies
#   - asks before every system-level change
#
# Options:
#   -y, --yes     answer yes to routine prompts (never to package removal or deleting clones)
#   --packages    also offer to uninstall the packages deploy.sh installed
#   -h, --help    show this help
set -uo pipefail

REPO_DIR="$HOME/hyprland-rice"
PC="$REPO_DIR/pc"
LETSNOTE="$REPO_DIR/letsnote"
CONFIG_DIR="$HOME/.config"
PICTURES_DIR="$HOME/Pictures"
SDDM_THEME="/usr/share/sddm/themes/sddm-astronaut-theme"
EVA_DIR="$HOME/Evangelion-archive"
LOG_FILE="$HOME/reverseDeploy-$(date +%Y%m%d-%H%M%S).log"

OFFICIAL_PKGS=(
  noctalia kew superfile imagemagick bluez bluez-utils
  helix steam sddm starship fish fastfetch kitty
  gstreamer gst-plugins-good gst-plugins-bad gst-plugins-ugly
)
AUR_PKGS=(
  bibata-cursor-theme umbriel-git xdg-desktop-portal-umbriel librewolf
)

ASSUME_YES=0
REMOVE_PKGS=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes)   ASSUME_YES=1 ;;
    --packages) REMOVE_PKGS=1 ;;
    -h|--help)  sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Log everything to the terminal and to a file
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
WARNINGS=()
warn() { printf 'WARNING: %s\n' "$*"; WARNINGS+=("$*"); }

# Honors -y
confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local ans
  read -rp "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Never auto-yes, even with -y
confirm_always() {
  local ans
  read -rp "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Delete files in $dst that match the file in $src, then prune empty folders.
# Anything you've edited since deploying is kept and reported.
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
  find "$dst" -depth -type d -empty -delete 2>/dev/null
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

[ "$EUID" -ne 0 ] || { echo "don't run this as root."; exit 1; }

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
FISH_PATH="$(command -v fish 2>/dev/null || true)"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
BASH_PATH="$(command -v bash)"
if [ -n "$FISH_PATH" ] && [ "$CURRENT_SHELL" = "$FISH_PATH" ] \
   && confirm "Switch your login shell back to bash?"; then
  chsh -s "$BASH_PATH" && note "shell set back to bash"
fi
note "/etc/shells still lists fish. That's harmless, so I left it alone."

log "SDDM theme files..."
remove_same_sudo "$LETSNOTE/hyprland_kath.conf" "$SDDM_THEME/Themes/hyprland_kath.conf"
remove_same_sudo "$LETSNOTE/asuka.mp4" "$SDDM_THEME/Backgrounds/asuka.mp4"
if [ -d "$SDDM_THEME" ] && confirm_always "Remove the whole sddm-astronaut-theme folder? Only say yes if you didn't have it before deploy.sh."; then
  sudo rm -rf -- "$SDDM_THEME"
  note "removed: $SDDM_THEME"
fi

log "Services..."
if confirm_always "Disable sddm? (you'll boot to a TTY, so re-enable your old display manager after this, e.g. sudo systemctl enable -f gdm)"; then
  sudo systemctl disable sddm.service && note "sddm disabled"
fi
if confirm_always "Disable and stop bluetooth.service?"; then
  sudo systemctl disable --now bluetooth.service && note "bluetooth disabled"
fi

log "Cloned repos..."
if [ -d "$EVA_DIR" ] && confirm_always "Delete $EVA_DIR? (this doesn't undo what its install.sh did)"; then
  rm -rf -- "$EVA_DIR"
  note "removed: $EVA_DIR"
fi
if [ -d "$REPO_DIR" ] && confirm_always "Delete $REPO_DIR?"; then
  rm -rf -- "$REPO_DIR"
  note "removed: $REPO_DIR"
fi

if [ "$REMOVE_PKGS" -eq 1 ]; then
  log "Removing packages..."
  warn "Some of these may have been installed before deploy.sh ran. Removing sddm, bluez or fish can leave you without a login screen or shell."
  note "yay itself is left installed."
  if confirm_always "Uninstall the packages deploy.sh installed? pacman will list everything it would remove first."; then
    sudo pacman -Rs "${OFFICIAL_PKGS[@]}" || warn "some official packages were not removed (they may not be installed)"
    yay -Rs "${AUR_PKGS[@]}" || warn "some AUR packages were not removed (they may not be installed)"
  fi
fi

log "Summary"
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  printf '  - %s\n' "${WARNINGS[@]}"
fi
note "Full log: $LOG_FILE"
note "Reboot if you disabled sddm or changed the shell."

#!/usr/bin/env bash
# Reverses deploy.sh.
# Default: removes copied configs (only if identical to the repo copy), restores the shell,
# and asks before touching anything system-wide.
# Flags: -y/--yes answers yes to everything except package removal,
#        --packages also uninstalls the packages deploy.sh installed.
set -uo pipefail

REPO_DIR="$HOME/hyprland-rice"
PC="$REPO_DIR/pc"
EVA_DIR="$HOME/Evangelion-archive"
SDDM_THEME=/usr/share/sddm/themes/sddm-astronaut-theme

ASSUME_YES=0
REMOVE_PKGS=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes)   ASSUME_YES=1 ;;
    --packages) REMOVE_PKGS=1 ;;
    -h|--help)  echo "usage: $0 [-y|--yes] [--packages]"; exit 0 ;;
    *)          echo "unknown option: $arg"; exit 1 ;;
  esac
done

log()     { printf '\n==> %s\n' "$*"; }
confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  read -rp "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Remove files in $dst that are identical to the matching file in $src, then prune empty dirs.
unuse_dir() {
  local src="$1" dst="$2"
  [ -d "$src" ] && [ -d "$dst" ] || return 0
  (cd "$src" && find . -type f) | while read -r f; do
    if cmp -s -- "$src/$f" "$dst/$f"; then
      rm -f -- "$dst/$f"
    else
      echo "keeping modified file: $dst/$f"
    fi
  done
  find "$dst" -type d -empty -delete 2>/dev/null
}

log "Removing copied configs (only files identical to the repo's)..."
for d in noctalia umbriel fastfetch fish kitty; do
  unuse_dir "$PC/$d" "$HOME/.config/$d"
done
if [ -f "$PC/starship.toml" ] && cmp -s "$PC/starship.toml" "$HOME/.config/starship.toml" 2>/dev/null; then
  rm -f "$HOME/.config/starship.toml"
fi
unuse_dir "$PC/Wallpaper" "$HOME/Pictures/Wallpapers"

log "Restoring default shell..."
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [ "$CURRENT_SHELL" = "$(command -v fish 2>/dev/null)" ] && confirm "Switch login shell back to bash?"; then
  chsh -s "$(command -v bash)" && echo "Shell set back to bash."
fi

log "SDDM theme files..."
if confirm "Remove the Hyprland Kath conf and asuka.mp4 from the SDDM theme?"; then
  sudo rm -f "$SDDM_THEME/Themes/hyprland_kath.conf" "$SDDM_THEME/Backgrounds/asuka.mp4"
fi
if confirm "Remove the whole sddm-astronaut-theme folder? (only if you didn't have it before)"; then
  sudo rm -rf "$SDDM_THEME"
fi

log "Services..."
if confirm "Disable sddm? (boots to a TTY next time; re-enable your old display manager if you had one)"; then
  sudo systemctl disable sddm.service
fi
if confirm "Disable bluetooth.service?"; then
  sudo systemctl disable --now bluetooth.service
fi

log "Cloned repos..."
if confirm "Delete $EVA_DIR?"; then
  rm -rf -- "$EVA_DIR"
fi
if confirm "Delete $REPO_DIR?"; then
  rm -rf -- "$REPO_DIR"
fi

if [ "$REMOVE_PKGS" -eq 1 ]; then
  log "Removing packages (pacman -Rs keeps your config files)..."
  echo "Heads up: some of these may have been installed before deploy.sh ran,"
  echo "and removing sddm, bluez or fish can leave you without a login or shell."
  if confirm "Uninstall the packages deploy.sh installed?"; then
    sudo pacman -Rs noctalia kew superfile imagemagick bluez bluez-utils \
      helix steam sddm starship fish fastfetch kitty
    yay -Rs bibata-cursor-theme luciole umbriel xdg-desktop-portal-umbriel librewolf
  fi
fi

log "Done. Reboot if you disabled sddm or changed the shell."

#!/bin/bash
echo "Setting up packages...\n"

# Get the repo
git clone https://github.com/MUMSAREAWESOME/hyprland-rice
cd hyprland-rice/pc

# Install dependencies
sudo pacman -S noctalia kew superfile	imagemagick bluez bluez-utils helix librewolf steam
yay -S bibata-cursor-theme luciole umbriel xdg-desktop-portal-umbriel

# Add files to the right locations
cp -r noctalia/ ~/.config/noctalia/
cp -r umbriel/ ~/.config/umbriel/
cp -r fastfetch/ ~/.config/fastfetch/
cp -r fish/ ~/.config/fish/
cp -r kitty/ ~/.config/kitty/
mkdir -p Pictures
cp -r Wallpaper/ ~/Pictures/Wallpapers
cp starship.toml/ ~/.config/

# Dark mode is nice
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Enable mandatory things
sudo systemctl enable --now bluetooth.service


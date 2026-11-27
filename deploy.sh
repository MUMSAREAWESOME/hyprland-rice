#!/bin/bash
echo "Setting up packages...\n"

# Get the repo
git clone https://github.com/MUMSAREAWESOME/hyprland-rice
cd hyprland-rice/pc

# Install dependencies
sudo pacman -S noctalia kew superfile	imagemagick bluez bluez-utils helix librewolf steam sddm
yay -S bibata-cursor-theme luciole umbriel xdg-desktop-portal-umbriel

# Add files to the right locations
cp -r noctalia/ ~/.config/noctalia/
cp -r umbriel/ ~/.config/umbriel/
cp -r fastfetch/ ~/.config/fastfetch/
cp -r fish/ ~/.config/fish/
cp -r kitty/ ~/.config/kitty/
mkdir -p ~/Pictures
cp -r Wallpaper/ ~/Pictures/Wallpapers
cp starship.toml/ ~/.config/

cd ~

# Dark mode is nice
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Enable mandatory things
sudo systemctl enable --now bluetooth.service sddm

git clone https://github.com/charichard08/Evangelion-archive/tree/main/
cd Evangelion-archive

./install.sh

cd ~

bash -c "$(curl -fsSL https://raw.githubusercontent.com/keyitdev/sddm-astronaut-theme/master/setup.sh)"

cd hyprland-rice/letsnote/

sudo cp hyprland_kath.conf /usr/share/sddm/themes/sddm-astronaut-theme/Themes/hyprland_kath.conf

sudo cp asuka.mp4 sudo cp hyprland_kath.conf /usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds/asuka.mp4

cd ~

sudo reboot

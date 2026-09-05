#!/bin/bash

echo "Installing YAY"

cd ~

git clone https://aur.archlinux.org/yay.git

cd yay

makepkg -si

cd ~

echo "Adding dotfiles"

cd .config

cd ~/Downloads/hyprland-rice/.config

rm -rf ~/.config/hypr && rm -rf ~/.config/kitty

cp hypr ~/.config

cp wayle ~/.config

cp kitty ~/.config

cp helix ~/.config

cp starship.toml ~/.config

cp fuzzel ~/.config

echo "Installing dependencies"

yay -S wayle-bin

sudo pacman -S nautilus firefox fuzzel hyprlock starship helix awww

echo 'eval "$(starship init bash)"' >> ~/.bashrc

# Create the directory if it doesn't exist
sudo mkdir -p /etc/systemd/resolved.conf.d/

# Write the DNS rules using echo
echo -e "[Resolve]\nDNS=185.228.168.168 185.228.169.168\nDNSOverTLS=no" | sudo tee /etc/systemd/resolved.conf.d/cleanbrowsing.conf > /dev/null

# Restart the service
sudo systemctl restart systemd-resolved

echo "rebooting"

sudo reboot

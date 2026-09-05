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

sudo pacman -S nautilus firefox fuzzel hyprlock starship helix

echo 'eval "$(starship init bash)"' >> ~/.bashrc

echo "rebooting"

sudo reboot

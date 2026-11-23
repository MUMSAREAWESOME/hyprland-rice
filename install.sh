#!/usr/bin/env bash
# Arch install script for awesome-pc. Don't get any ideas. It's just for you. Hmph.
set -euo pipefail

DISK="/dev/nvme0n1"
EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
SWAP_PART="${DISK}p3"
HOSTNAME="awesome-pc"
USERNAME="mumsareawesome"
TIMEZONE="Australia/Brisbane"

# --- Sanity checks ---
if [[ $EUID -ne 0 ]]; then
    echo "Run this as root from the Arch live ISO. Baka."
    exit 1
fi

if [[ ! -d /sys/firmware/efi ]]; then
    echo "Not booted in UEFI mode. This script assumes UEFI. Reboot in UEFI mode."
    exit 1
fi

# --- Partitioning (interactive, optional) ---
read -rp "Open cfdisk on $DISK to partition it now? [y/N] " ans
if [[ $ans =~ ^[Yy]$ ]]; then
    cfdisk "$DISK"
fi

lsblk "$DISK"
echo
echo "WARNING: This will FORMAT $EFI_PART (EFI), $ROOT_PART (root) and $SWAP_PART (swap)."
echo "Everything on them will be destroyed."
read -rp "Type 'yes' to continue: " confirm
if [[ $confirm != "yes" ]]; then
    echo "Aborted. Nothing was touched. I wasn't worried about you or anything."
    exit 1
fi

# --- Formatting ---
mkfs.ext4 "$ROOT_PART"
mkswap "$SWAP_PART"
mkfs.fat -F 32 "$EFI_PART"

# --- Mounting ---
mount "$ROOT_PART" /mnt
swapon "$SWAP_PART"
mount --mkdir "$EFI_PART" /mnt/boot

# --- Base system ---
pacstrap -K /mnt base linux linux-firmware amd-ucode nano networkmanager git base-devel sudo
genfstab -U /mnt > /mnt/etc/fstab

# --- Chroot configuration ---
# Write the chroot script into the new system, then run it inside arch-chroot.
# It runs with a real terminal, so passwd can prompt you normally.
cat > /mnt/root/chroot-setup.sh << 'CHROOT_EOF'
#!/usr/bin/env bash
set -euo pipefail

HOSTNAME="$1"
USERNAME="$2"
TIMEZONE="$3"

# Localization
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

sed -i 's/^#\(en_AU\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen

echo "LANG=en_AU.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname

# Users & permissions
echo "Set the root password:"
passwd

if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists, skipping creation."
else
    useradd -m -G wheel "$USERNAME"
    echo "Set the password for $USERNAME:"
    passwd "$USERNAME"
fi

# Sudo for the wheel group, via a drop-in file instead of editing /etc/sudoers directly
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel

# Bootloader
pacman -S --needed --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "Chroot configuration complete."
CHROOT_EOF

chmod +x /mnt/root/chroot-setup.sh
arch-chroot /mnt /root/chroot-setup.sh "$HOSTNAME" "$USERNAME" "$TIMEZONE"
rm -f /mnt/root/chroot-setup.sh

echo
echo "Base install and bootloader done. Hmph, not bad. Don't get used to it."
echo "Still manual: desktop packages, enabling services, and the final exit/unmount."

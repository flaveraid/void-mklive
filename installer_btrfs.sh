#!/bin/bash

# Bare-bones Void Linux btrfs install (chroot method), using the running live
# system as the ROOTFS.
#
# Before running this:
#   1. Partition the disk yourself (cfdisk): an ESP (UEFI only) or a 1MiB
#      "BIOS boot" partition (BIOS + GPT), a swap partition and a btrfs partition.
#   2. Fill in the variables below.

KEYMAP=us
HOSTNAME=void
LOCALE=en_US.UTF-8
TIMEZONE=America/Los_Angeles
USERGROUPS=wheel,audio,video,floppy,cdrom,optical,kvm,users,xbuilder
USER_SHELL=/usr/bin/fish            # ex: /bin/bash login shell of the new user
DISK=/dev/vda                       # ex: /dev/sda  GRUB is installed here
ESP_PART=/dev/vda1                  # ex: /dev/sda1 UEFI only, mounted on /boot/efi
SWAP_PART=/dev/vda2                 # ex: /dev/sda2 swap
ROOT_PART=/dev/vda3                 # ex: /dev/sda3 btrfs
FORMAT_ESP=y                        # y: mkfs.vfat the ESP, n: keep it as-is
BTRFS_OPTS=compress=zstd,noatime
SNAPPER=y                           # y: snapper config for / and a first snapshot
TEXTCONSOLE=n                       # y: text console for GRUB
SERVICES="grub-btrfs"               # runit services to enable (on top of the live ones)

TARGETDIR=/mnt/target

set -e

echo "================================"
echo "Void Linux: BTRFS Chroot Install"
echo "================================"
echo
echo "This (mostly) non-interactive script will use the following variables to install Void Linux on a BTRFS filesystem with snapshots enabled."
echo
echo "User login, user name, user password, and root password are obtained interactively."
echo
echo "Disks available on this system:"
lsblk -dpno NAME,SIZE,MODEL -e 1,7,11
echo
echo "Keymap:       $KEYMAP"
echo "Hostname:     $HOSTNAME"
echo "Locale:       $LOCALE"
echo "Time zone:    $TIMEZONE"
echo "User Groups:  $USERGROUPS"
echo "User Shell:   $USER_SHELL"
echo "Disk / GRUB:  $DISK"
echo "ESP:          $ESP_PART on /boot/efi (format: $FORMAT_ESP)"
echo "Swap:         $SWAP_PART"
echo "Btrfs:        $ROOT_PART ($BTRFS_OPTS)"
echo "              @ on /, @home on /home, @snapshots on /.snapshots"
echo "Snapper:      $SNAPPER"
echo "GRUB Console: $TEXTCONSOLE"
echo "Services:     $SERVICES"
echo "              enabled in addition to currently running services"
echo
if [ "$FORMAT_ESP" = y ]; then
    echo "WARNING: everything on $ESP_PART will be ERASED."
fi
echo "WARNING: everything on $ROOT_PART and $SWAP_PART will be ERASED."
echo

read -r -p "Please confirm you have adjusted the environment variables before continuing. (y/n): " answer
case "$answer" in
    [Yy]|[Yy][Ee][Ss]) ;;
    *) echo "Aborting. Review and edit $0 first." >&2; exit 1;;
esac

[ "$(id -u)" = 0 ] || { echo "$0 must run as root" >&2; exit 1; }

read -r -p "Login name: " USERLOGIN
read -r -p "Display name: " USERNAME
while true; do
    read -r -s -p "Password for $USERLOGIN: " USERPASSWORD; echo
    read -r -s -p "Again: " PASSWORD2; echo
    [ -n "$USERPASSWORD" ] && [ "$USERPASSWORD" = "$PASSWORD2" ] && break
    echo "Passwords are empty or do not match, try again."
done
while true; do
    read -r -s -p "Root password: " ROOTPASSWORD; echo
    read -r -s -p "Again: " PASSWORD2; echo
    [ -n "$ROOTPASSWORD" ] && [ "$ROOTPASSWORD" = "$PASSWORD2" ] && break
    echo "Passwords are empty or do not match, try again."
done

if [ -e /sys/firmware/efi/systab ]; then
    EFI_SYSTEM=1
    if [ "$(cat /sys/firmware/efi/fw_platform_size)" -eq 32 ]; then
        EFI_TARGET=i386-efi
    else
        EFI_TARGET=x86_64-efi
    fi
fi

swapoff "$SWAP_PART" 2>/dev/null || true
mkswap "$SWAP_PART"
swapon "$SWAP_PART"

if [ -n "$EFI_SYSTEM" ] && [ "$FORMAT_ESP" = y ]; then
    mkfs.vfat -F32 "$ESP_PART"
fi

mkfs.btrfs -f "$ROOT_PART"
mkdir -p "$TARGETDIR"
mount "$ROOT_PART" "$TARGETDIR"
btrfs subvolume create "$TARGETDIR/@"
btrfs subvolume create "$TARGETDIR/@home"
btrfs subvolume create "$TARGETDIR/@snapshots"
umount "$TARGETDIR"

mount -o "$BTRFS_OPTS,subvol=@" "$ROOT_PART" "$TARGETDIR"
mkdir -p "$TARGETDIR/home"
mount -o "$BTRFS_OPTS,subvol=@home" "$ROOT_PART" "$TARGETDIR/home"

echo "Copying the live system (one dot is about 100MB)"
tar --create --one-file-system --xattrs -f - / 2>/dev/null | \
    tar --extract --xattrs --xattrs-include='*' --preserve-permissions \
        --checkpoint=10000 --checkpoint-action=dot -f - -C "$TARGETDIR"
echo
rmdir "$TARGETDIR/mnt/target" 2>/dev/null || true

LIVE_USER=$(. /etc/default/live.conf && echo "$USERNAME")
xchroot "$TARGETDIR" userdel -r "$LIVE_USER" || true
rm -f "$TARGETDIR/etc/sudoers.d/99-void-live"
rm -f "$TARGETDIR/etc/polkit-1/rules.d/void-live.rules"
rm -f "$TARGETDIR/etc/sddm.conf"
rm -f "$TARGETDIR/etc/motd" "$TARGETDIR/etc/issue"
rm -f "$TARGETDIR/usr/bin/void-installer" "$TARGETDIR/usr/bin/void-installer-btrfs"
sed -i "s,GETTY_ARGS=\"--noclear -a $LIVE_USER\",GETTY_ARGS=\"--noclear\",g" \
    "$TARGETDIR/etc/sv/agetty-tty1/conf"

if [ -n "$EFI_SYSTEM" ]; then
    mkdir -p "$TARGETDIR/boot/efi"
    mount "$ESP_PART" "$TARGETDIR/boot/efi"
fi

if [ "$SNAPPER" = y ]; then
    xchroot "$TARGETDIR" snapper --no-dbus -c root create-config /
    xchroot "$TARGETDIR" btrfs subvolume delete /.snapshots
fi
mkdir -p "$TARGETDIR/.snapshots"
mount -o "$BTRFS_OPTS,subvol=@snapshots" "$ROOT_PART" "$TARGETDIR/.snapshots"
chmod 750 "$TARGETDIR/.snapshots"

xgenfstab -U "$TARGETDIR" > "$TARGETDIR/etc/fstab"

if [ -f "$TARGETDIR/etc/vconsole.conf" ]; then
    sed -i -e "s|KEYMAP=.*|KEYMAP=$KEYMAP|g" "$TARGETDIR/etc/vconsole.conf"
else
    sed -i -e "s|#\?KEYMAP=.*|KEYMAP=$KEYMAP|g" "$TARGETDIR/etc/rc.conf"
fi

if [ -f "$TARGETDIR/etc/default/libc-locales" ]; then
    sed -i -e "s|LANG=.*|LANG=$LOCALE|g" "$TARGETDIR/etc/locale.conf"
    sed -i -e "/${LOCALE}/s/^\#//" "$TARGETDIR/etc/default/libc-locales"
fi

ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$TARGETDIR/etc/localtime"
echo "$HOSTNAME" > "$TARGETDIR/etc/hostname"

echo "root:$ROOTPASSWORD" | xchroot "$TARGETDIR" chpasswd -c SHA512
xchroot "$TARGETDIR" useradd -m -G "$USERGROUPS" -s "$USER_SHELL" -c "$USERNAME" "$USERLOGIN"
echo "$USERLOGIN:$USERPASSWORD" | xchroot "$TARGETDIR" chpasswd -c SHA512
cp "$TARGETDIR"/etc/skel/.[bix]* "$TARGETDIR/root"

echo "%wheel ALL=(ALL:ALL) ALL" > "$TARGETDIR/etc/sudoers.d/wheel"
chmod 440 "$TARGETDIR/etc/sudoers.d/wheel"

echo 'add_dracutmodules+=" overlayfs "' > "$TARGETDIR/etc/dracut.conf.d/grub-btrfs-overlayfs.conf"
echo 'GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"' \
    >> "$TARGETDIR/etc/default/grub-btrfs/config"

for sv in $SERVICES; do
    ln -sf "/etc/sv/$sv" "$TARGETDIR/etc/runit/runsvdir/default/$sv"
done

xchroot "$TARGETDIR" xbps-reconfigure -fa

if [ "$TEXTCONSOLE" = y ]; then
    sed -i "$TARGETDIR/etc/default/grub" \
        -e 's|#\(GRUB_TERMINAL_INPUT\).*|\1=console|' \
        -e 's|#\(GRUB_TERMINAL_OUTPUT\).*|\1=console|'
fi

if [ -n "$EFI_SYSTEM" ]; then
    mountpoint -q /sys/firmware/efi/efivars || mount -t efivarfs none /sys/firmware/efi/efivars
    xchroot "$TARGETDIR" grub-install --target="$EFI_TARGET" --efi-directory=/boot/efi \
        --bootloader-id=void_grub --recheck "$DISK"
else
    xchroot "$TARGETDIR" grub-install "$DISK"
fi
xchroot "$TARGETDIR" grub-mkconfig -o /boot/grub/grub.cfg

if [ "$SNAPPER" = y ]; then
    xchroot "$TARGETDIR" snapper --no-dbus -c root create --description "fresh install"
    xchroot "$TARGETDIR" grub-mkconfig -o /boot/grub/grub.cfg
fi

sync
swapoff "$SWAP_PART"
umount -R "$TARGETDIR"
echo "Void Linux has been installed. You can reboot now."

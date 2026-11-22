#!/bin/bash

# Bare-bones Void Linux btrfs install (chroot method), using the running live
# system as the ROOTFS.
#
# Snapshot/rollback stack (SNAPPER=y):
#   snapper          timeline + number snapshots, driven by cron (cronie)
#   snapper-rollback Arch-style rollback: renames @ and re-creates it from a snapshot
#   grub-btrfs       snapshots in the GRUB menu, booted through a dracut overlayfs
#   xbps-snap        xbps-install wrapped in a snapper pre/post pair
#
# Before running this:
#   1. Partition the disk yourself (cfdisk): an ESP (UEFI only) or a 1MiB
#      "BIOS boot" partition (BIOS + GPT), a swap partition and a btrfs partition.
#   2. Install the required packages on the live system (the script checks
#      and prints the xbps-install command if anything is missing).
#   3. Fill in the variables below.

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
TEXTCONSOLE=n                       # y: text console for GRUB

# Subvolumes kept OUT of root snapshots, so a rollback doesn't rewind logs or
# re-download packages. Format: subvolume:mountpoint
EXTRA_SUBVOLS="@var_log:/var/log @var_cache_xbps:/var/cache/xbps @var_tmp:/var/tmp"

SNAPPER=y                           # y: snapper + rollback + grub-btrfs stack
# Applied with "snapper set-config"; change to taste.
SNAPPER_SETTINGS="TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes NUMBER_CLEANUP=yes
TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=0
TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0
NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
ALLOW_GROUPS=wheel SYNC_ACL=yes"

SERVICES=""                         # extra runit services to enable (on top of the
                                    # live ones, and of dbus/cronie/grub-btrfs if SNAPPER=y)

TARGETDIR=/mnt/target

set -e

[ "$(id -u)" = 0 ] || { echo "$0 must run as root" >&2; exit 1; }

if [ -e /sys/firmware/efi/systab ]; then
    EFI_SYSTEM=1
    if [ "$(cat /sys/firmware/efi/fw_platform_size)" -eq 32 ]; then
        EFI_TARGET=i386-efi
    else
        EFI_TARGET=x86_64-efi
    fi
fi

# --- Packages the live system must have (they get copied into the target) ---
REQUIRED="btrfs-progs dosfstools xtools grub dracut"
if [ -n "$EFI_SYSTEM" ]; then
    REQUIRED="$REQUIRED grub-$EFI_TARGET"
fi
if [ "$SNAPPER" = y ]; then
    REQUIRED="$REQUIRED snapper snapper-rollback grub-btrfs cronie dbus"
    SERVICES="dbus cronie grub-btrfs $SERVICES"
fi
MISSING=""
for pkg in $REQUIRED; do
    xbps-query "$pkg" >/dev/null 2>&1 || MISSING="$MISSING $pkg"
done
if [ -n "$MISSING" ]; then
    echo "Missing on the live system:$MISSING" >&2
    echo "Install them first:  xbps-install -S$MISSING" >&2
    exit 1
fi

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
for e in $EXTRA_SUBVOLS; do
    echo "              ${e%%:*} on ${e#*:}"
done
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

# --- Filesystems ---
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
for e in $EXTRA_SUBVOLS; do
    btrfs subvolume create "$TARGETDIR/${e%%:*}"
done
umount "$TARGETDIR"

mount -o "$BTRFS_OPTS,subvol=@" "$ROOT_PART" "$TARGETDIR"
# Make @ the default subvolume (snapper-rollback also sets it after a rollback).
btrfs subvolume set-default "$TARGETDIR"
mkdir -p "$TARGETDIR/home"
mount -o "$BTRFS_OPTS,subvol=@home" "$ROOT_PART" "$TARGETDIR/home"
for e in $EXTRA_SUBVOLS; do
    mkdir -p "$TARGETDIR${e#*:}"
    mount -o "$BTRFS_OPTS,subvol=${e%%:*}" "$ROOT_PART" "$TARGETDIR${e#*:}"
done

# --- Copy the live system ---
echo "Copying the live system (one dot is about 100MB)"
tar --create --one-file-system --xattrs -f - / 2>/dev/null | \
    tar --extract --xattrs --xattrs-include='*' --preserve-permissions \
        --checkpoint=10000 --checkpoint-action=dot -f - -C "$TARGETDIR"
echo
rmdir "$TARGETDIR/mnt/target" 2>/dev/null || true
if [ -d "$TARGETDIR/var/tmp" ]; then
    chmod 1777 "$TARGETDIR/var/tmp"
fi

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

# --- Snapper ---
# snapper insists on creating its own nested .snapshots subvolume; replace it
# with the top-level @snapshots so snapshots survive a rollback of @.
if [ "$SNAPPER" = y ]; then
    xchroot "$TARGETDIR" snapper --no-dbus -c root create-config /
    xchroot "$TARGETDIR" btrfs subvolume delete /.snapshots
fi
mkdir -p "$TARGETDIR/.snapshots"
mount -o "$BTRFS_OPTS,subvol=@snapshots" "$ROOT_PART" "$TARGETDIR/.snapshots"
chmod 750 "$TARGETDIR/.snapshots"

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
SWAP_UUID=$(blkid -s UUID -o value "$SWAP_PART")

if [ "$SNAPPER" = y ]; then
    # shellcheck disable=SC2086 # word splitting of the settings is intended
    xchroot "$TARGETDIR" snapper --no-dbus -c root set-config $SNAPPER_SETTINGS

    # snapper-rollback mounts the top level (subvolid=5) here itself when
    # "dev" is set, so it doesn't need to be in fstab.
    mkdir -p "$TARGETDIR/btrfsroot"
    sed -i "s|^#\?dev = .*|dev = /dev/disk/by-uuid/$ROOT_UUID|" \
        "$TARGETDIR/etc/snapper-rollback.conf"

    # Boot read-only snapshots from GRUB through an overlayfs (dracut >= 109).
    echo 'add_dracutmodules+=" overlayfs "' > "$TARGETDIR/etc/dracut.conf.d/grub-btrfs-overlayfs.conf"
    echo 'GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"' \
        >> "$TARGETDIR/etc/default/grub-btrfs/config"

    # xbps-install wrapped in a pre/post snapshot pair.
    mkdir -p "$TARGETDIR/usr/local/bin"
    cat > "$TARGETDIR/usr/local/bin/xbps-snap" <<'EOF'
#!/bin/bash
# xbps-install inside a snapper pre/post snapshot pair.
# Usage: xbps-snap -Su   (takes any xbps-install arguments)
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
cmd=$(printf '%q ' xbps-install "$@")
exec snapper -c root create --cleanup-algorithm number \
    --description "xbps-install $*" --command "$cmd"
EOF
    chmod 755 "$TARGETDIR/usr/local/bin/xbps-snap"
fi

# --- fstab ---
# Written by hand rather than with xgenfstab: root must be mounted by
# subvol=@ (not subvolid=), or a rollback would keep booting the old @.
{
    echo "# <file system>  <dir>  <type>  <options>  <dump>  <pass>"
    echo "UUID=$ROOT_UUID  /            btrfs  $BTRFS_OPTS,subvol=@          0 0"
    echo "UUID=$ROOT_UUID  /home        btrfs  $BTRFS_OPTS,subvol=@home      0 0"
    echo "UUID=$ROOT_UUID  /.snapshots  btrfs  $BTRFS_OPTS,subvol=@snapshots 0 0"
    for e in $EXTRA_SUBVOLS; do
        echo "UUID=$ROOT_UUID  ${e#*:}  btrfs  $BTRFS_OPTS,subvol=${e%%:*}  0 0"
    done
    if [ -n "$EFI_SYSTEM" ]; then
        echo "UUID=$(blkid -s UUID -o value "$ESP_PART")  /boot/efi  vfat  defaults  0 2"
    fi
    echo "UUID=$SWAP_UUID  none  swap  defaults  0 0"
    echo "tmpfs  /tmp  tmpfs  defaults,nosuid,nodev  0 0"
} > "$TARGETDIR/etc/fstab"

# --- System config ---
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

# -n: don't follow an existing symlink copied from the live system
for sv in $SERVICES; do
    if [ -d "$TARGETDIR/etc/sv/$sv" ]; then
        ln -sfn "/etc/sv/$sv" "$TARGETDIR/etc/runit/runsvdir/default/$sv"
    else
        echo "WARNING: service $sv not found in /etc/sv, skipping" >&2
    fi
done

xchroot "$TARGETDIR" xbps-reconfigure -fa

# --- Bootloader ---
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
    xchroot "$TARGETDIR" snapper --no-dbus -c root create \
        --cleanup-algorithm number --userdata important=yes --description "fresh install"
    xchroot "$TARGETDIR" grub-mkconfig -o /boot/grub/grub.cfg
fi

sync
swapoff "$SWAP_PART"
umount -R "$TARGETDIR"
echo "Void Linux has been installed. You can reboot now."
if [ "$SNAPPER" = y ]; then
    echo
    echo "Snapshots:  snapper list   |   updates:  xbps-snap -Su"
    echo "Rollback:   snapper-rollback <N> && reboot   (then delete the old @<date> under /btrfsroot)"
fi

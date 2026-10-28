#!/bin/bash

ROOTFS="$1"

echo "=========================="
echo "Build hooks: niri-dms-base"
echo "=========================="

if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS/etc" ]; then
	echo "Error: rootfs path missing or invalid: '$ROOTFS'" >&2
	exit 1
fi

echo "Updating greeter-related permissions"
chroot "$ROOTFS" mkdir -p /var/lib/greeter /var/cache/dms-greeter
chroot "$ROOTFS" chown _greeter:_greeter /var/lib/greeter /var/cache/dms-greeter
chroot "$ROOTFS" chmod 2770 /var/cache/dms-greeter

# build the skel niri config from the package default, then append dms
echo "Generating niri config from packaged default"
NIRI_DEFAULT="$ROOTFS/usr/share/examples/niri/default-config.kdl"
NIRI_SKEL="$ROOTFS/etc/skel/.config/niri/config.kdl"
if [ ! -f "$NIRI_DEFAULT" ]; then
	echo "Error: niri default config not found: $NIRI_DEFAULT" >&2
	exit 1
fi
mkdir -p "$(dirname "$NIRI_SKEL")"
cp "$NIRI_DEFAULT" "$NIRI_SKEL"
sed -i '/^spawn-at-startup "waybar"/d' "$NIRI_SKEL"
printf '\nspawn-at-startup "dms" "run"\n' >> "$NIRI_SKEL"

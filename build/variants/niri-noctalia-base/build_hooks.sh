#!/bin/bash

ROOTFS="$1"

echo "==============================="
echo "Build hooks: niri-noctalia-base"
echo "==============================="

if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS/etc" ]; then
	echo "Error: rootfs path missing or invalid: '$ROOTFS'" >&2
	exit 1
fi

# fix ownership applied by the overlay
echo "Updating greeter-related permissions"
chroot "$ROOTFS" chown -R _greeter:_greeter /var/lib/noctalia-greeter
#chmod 755 "$ROOTFS/etc/greetd"
#chmod 644 "$ROOTFS/etc/greetd/config.toml"

# build the skel niri config from the package default, then append noctalia
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
printf '\nspawn-at-startup "noctalia"\n' >> "$NIRI_SKEL"

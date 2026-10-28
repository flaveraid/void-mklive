#!/bin/bash

ROOTFS="$1"

echo "==========================="
echo "Build hooks: mango-noctalia"
echo "==========================="

if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS/etc" ]; then
	echo "Error: rootfs path missing or invalid: '$ROOTFS'" >&2
	exit 1
fi

# fix ownership applied by the overlay
echo "Updating greeter-related permissions"
chroot "$ROOTFS" chown -R _greeter:_greeter /var/lib/noctalia-greeter
#chmod 755 "$ROOTFS/etc/greetd"
#chmod 644 "$ROOTFS/etc/greetd/config.toml"

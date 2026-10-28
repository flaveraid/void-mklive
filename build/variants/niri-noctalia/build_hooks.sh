#!/bin/bash

ROOTFS="$1"

echo "=========================="
echo "Build hooks: niri-noctalia"
echo "=========================="

if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS/etc" ]; then
	echo "Error: rootfs path missing or invalid: '$ROOTFS'" >&2
	exit 1
fi

# fix ownership applied by the overlay
echo "Updating greeter-related permissions"
chroot "$ROOTFS" chown -R _greeter:_greeter /var/lib/noctalia-greeter
chmod 755 "$ROOTFS/etc/greetd"
chmod 644 "$ROOTFS/etc/greetd/config.toml"

# set default gtk font,cursor,icons globally by rebuilding the schema
# not needed if your overlay does not include a glib-2.0 schema
# echo "Recompiling glib schemas"
# chroot "$ROOTFS" glib-compile-schemas /usr/share/glib-2.0/schemas

# add fprintd to /etc/pam.d/greetd
echo "Adding fprintd support"
PAM_GREETD="$ROOTFS/etc/pam.d/greetd"
if [ -f "$PAM_GREETD" ] && ! grep -q pam_fprintd "$PAM_GREETD"; then
    sed -i '0,/^auth/s//auth       sufficient   pam_fprintd.so\nauth/' "$PAM_GREETD"
fi

# add wlr screenshot/screencast references to /usr/share/xdg-desktop-portal/niri-portals.conf
echo "Adding xdg-portals settings to niri-portals"
cat >> "$ROOTFS/usr/share/xdg-desktop-portal/niri-portals.conf" <<EOF
org.freedesktop.impl.portal.Screenshot=wlr;gtk;
org.freedesktop.impl.portal.ScreenCast=wlr;gtk;
EOF

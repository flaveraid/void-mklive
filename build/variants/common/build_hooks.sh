#!/bin/bash

ROOTFS="$1"

echo "==================="
echo "Build hooks: common"
echo "==================="

if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS/etc" ]; then
	echo "Error: rootfs path missing or invalid: '$ROOTFS'" >&2
	exit 1
fi

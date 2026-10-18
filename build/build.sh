#!/bin/bash

set -eu

PROGNAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")
VARIANTS_DIR="$SCRIPT_DIR/variants"
COMMON_DIR="$VARIANTS_DIR/common"

VARIANT=
ARCH=$(xbps-uhelper arch 2>/dev/null || uname -m)
LIVE_SHELL=
LAYERS=()        # variant folders to combine, lowest priority first
EXTRA_ARGS=()    # anything after "--"
MKLIVE_ARGS=()   # the options we build up and hand to mkiso.sh/mklive.sh

usage() {
	cat <<-EOH
	Usage: $PROGNAME <variant> [options ...] [-- mklive options ...]

	Builds a live ISO by combining the files in build/variants/ and handing
	them to mkiso.sh. Must be run with sudo.

	Variants: $(ls "$VARIANTS_DIR" | grep -vx common | xargs)

	OPTIONS
	 -a <arch>      Set architecture (default: the host's, currently $ARCH)
	                For example x86_64, x86_64-musl
	 -h             Show this help and exit

	ENVIRONMENT
	 BINPKGS=<dir>  Directory of locally built .xbps files (for example
	                void-packages/hostdir/binpkgs) to include in the ISO

	Options after the -- are passed directly to mklive.sh.
	EOH
}

cleanup() {
    rm -rf "$WORK_DIR"
}

# print the contents of a file (packages, services) from every layer as
# one line, comments and blank lines are removed
read_lists() {
    name="$1"
    for layer in "${LAYERS[@]}"; do
        if [ -f "$layer/$name" ]; then
            cat "$layer/$name"
        fi
    done | sed 's/#.*//' | xargs
}

# load the config file from each layer
# a later layer overrides an earlier one
load_config() {
    for layer in "${LAYERS[@]}"; do
        if [ -f "$layer/config" ]; then
            . "$layer/config"
        fi
    done
}

# copy the overlay folder from each layer into one place
# a later layer overwrites files from an earlier one
stage_overlay() {
    mkdir "$WORK_DIR/overlay"
    HAVE_OVERLAY=no

    for layer in "${LAYERS[@]}"; do
        if [ -d "$layer/overlay" ]; then
            echo "Staging overlay $layer/overlay"
            cp -a "$layer/overlay/." "$WORK_DIR/overlay/"
            HAVE_OVERLAY=yes
        fi
    done

    if [ "$HAVE_OVERLAY" = yes ]; then
        # files in the ISO should be owned by root
        chown -R root:root "$WORK_DIR/overlay"
        MKLIVE_ARGS+=(-I "$WORK_DIR/overlay")
    else
        echo "No overlay found"
    fi
}

# mklive.sh only accepts one -x script, so write a small script that runs
# every layer's build_hooks.sh in order
stage_hooks() {
    WRAPPER="$WORK_DIR/build_hooks.sh"
    HOOK_COUNT=0

    printf '#!/bin/bash\nset -e\n' > "$WRAPPER"

    for layer in "${LAYERS[@]}"; do
        if [ -f "$layer/build_hooks.sh" ]; then
            echo "Adding build hook $layer/build_hooks.sh"
            printf 'bash "%s" "$@"\n' "$layer/build_hooks.sh" >> "$WRAPPER"
            HOOK_COUNT=$((HOOK_COUNT + 1))
        fi
    done

    if [ "$HOOK_COUNT" -gt 0 ]; then
        chmod +x "$WRAPPER"
        MKLIVE_ARGS+=(-x "$WRAPPER")
    else
        echo "No build hooks found"
    fi
}

# each line of a layer's repos file is one repository URL
add_repos() {
    for layer in "${LAYERS[@]}"; do
        if [ -f "$layer/repos" ]; then
            for repo in $(sed 's/#.*//' "$layer/repos"); do
                MKLIVE_ARGS+=(-r "$repo")
            done
        fi
    done
}

# optional: turn a folder of locally built packages into a repository
# this is added last, so it is preferred over the other repositories
add_local_repo() {
    if [ -n "${BINPKGS:-}" ]; then
        echo "Staging local repository $BINPKGS"
        mkdir "$WORK_DIR/localrepo"
        cp "$BINPKGS"/*.xbps "$WORK_DIR/localrepo/"
        xbps-rindex -a "$WORK_DIR"/localrepo/*.xbps
        MKLIVE_ARGS+=(-r "$WORK_DIR/localrepo")
    else
        echo "BINPKGS not set, skipping local repository"
    fi
}

# print usage if no arguments are provided
if [ $# -lt 1 ]; then
    usage >&2
    exit 1
fi

# print usage
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi

VARIANT="$1"
shift

while getopts "a:h" opt; do
case $opt in
    a) ARCH="$OPTARG";;
    h) usage; exit 0;;
    *) usage >&2; exit 1;;
esac
done
shift $((OPTIND - 1))

# whatever is left after the -- is for mklive.sh
EXTRA_ARGS=("$@")

# sanity checks
if [ -z "${SUDO_USER:-}" ]; then
    echo "Error: run with sudo, not as a root login" >&2
    exit 1
fi

if [ "$VARIANT" = "common" ]; then
    echo "Error: 'common' is not a buildable variant" >&2
    exit 1
fi

# decide which folders to combine
# common always comes first
if [ -d "$COMMON_DIR" ]; then
    LAYERS+=("$COMMON_DIR")
fi

if [ ! -d "$VARIANTS_DIR/$VARIANT" ]; then
    echo "Error: no such variant '$VARIANT'" >&2
    usage >&2
    exit 1
fi
LAYERS+=("$VARIANTS_DIR/$VARIANT")

echo "====="
echo "Build"
echo "====="
echo "Building $VARIANT ($ARCH) using: ${LAYERS[*]}"

# staged items (overlay, hooks, local repo) live in a temporary folder
# that is deleted when the script ends
WORK_DIR=$(mktemp -d /tmp/void-mklive.XXXXXX)
trap cleanup EXIT

load_config

PKGS=$(read_lists packages)
SVCS=$(read_lists services)
echo "Packages: $PKGS"
echo "Services: $SVCS"

if [ -n "$PKGS" ]; then
    MKLIVE_ARGS+=(-p "$PKGS")
fi

if [ -n "$SVCS" ]; then
    MKLIVE_ARGS+=(-S "$SVCS")
fi

if [ -n "$LIVE_SHELL" ]; then
    MKLIVE_ARGS+=(-C "live.shell=$LIVE_SHELL")
fi

stage_overlay
stage_hooks
add_repos
add_local_repo

# mkiso.sh and mklive.sh use paths relative to the repo root
echo "Launching mkiso.sh"
cd "$REPO_DIR"
./mkiso.sh -a "$ARCH" -b "$VARIANT" -- "${MKLIVE_ARGS[@]}" "${EXTRA_ARGS[@]}"

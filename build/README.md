# Build

Build a live ISO that uses a wayland window manager, shell, and greetd greeter by default.

Disclaimer: This is a work in progress. Please review the configurations before moving forward.

## Variants

- **mango-noctalia**: includes mangowc, noctalia, noctalia-greeter, and some skel files for a few programs.
- **niri-noctalia**: includes niri, noctalia, noctalia-greeter. 
- **niri-noctalia-base**: consists of mostly default settings.
- **niri-dms-base**: includes niri, dms, and dms-greeter.

**Note**: The [voiders.dev community repo](https://voiders.dev/) provides `noctalia`, `noctalia-greeter`, and `adw-gtk-theme` packages. 

## How to Build

Update host system:

```sh
sudo xbps-install -Su
```

Clone the repo:

```sh
git clone https://github.com/flaveraid/void-mklive
cd void-mklive/build
```

Review usage options:

```sh
./build.sh --help
```

Build using a base package/service lists, overlay, and hooks:

```sh
sudo ./build.sh niri-noctalia-base -- -p "alacritty nano firefox"
```

Override repo packages with locally built ones:

```sh
sudo BINPKGS=/path/to/void-packages/hostdir/binpkgs ./build.sh niri-noctalia
```

Pass additional repo to `mklive`:

```sh
sudo ./build.sh niri-noctalia -- -r "https://repo.example.com/current"
```

## Live ISO

The live ISO includes a separate installer script located at `/usr/bin/void-installer-btrfs`

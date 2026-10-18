# Build

## What is this?

I wanted to build a live ISO that uses a wayland window manager, shell, and greetd greeter by default.

### New Variants

- The `niri-noctalia-base` variant is offered as a convenience, and consists of mostly default settings.

- The `niri-noctalia` variant includes niri, noctalia, and noctalia-greeter. The [voiders.dev](https://voiders.dev/) community repo offers the noctalia and adw-gtk-theme packages. 

Disclaimer: This is a work in progress and I am still learning how some of these pieces fit together.

## How to Build

Clone the repo:

```sh
git clone https://github.com/flaveraid/void-mklive
cd void-mklive/build
```

Review usage options:

```sh
./build.sh --help
```

Build using the base package/service lists, overlay, and hooks:

```sh
sudo ./build.sh niri-noctalia-base -- -p "alacritty nano firefox"
```

Build using opinionated package/service lists, overlays, and hooks:

```sh
sudo ./build.sh niri-noctalia
```

Override repo packages with locally built ones:

```sh
sudo BINPKGS=/path/to/void-packages/hostdir/binpkgs ./build.sh niri-noctalia
```

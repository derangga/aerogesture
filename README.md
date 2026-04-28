# AeroGesture

A lightweight, CLI-based macOS daemon that detects trackpad swipe gestures and translates them into workspace-switching commands for [AeroSpace](https://github.com/nikitabobko/AeroSpace) — the tiling window manager for macOS.

## Why AeroGesture?

There are existing tools like [SwipeAeroSpace](https://github.com/MediosZ/SwipeAeroSpace) that provide gesture-based workspace switching. AeroGesture takes a different approach:

- **CLI-first, no GUI** — Runs as a pure background daemon with zero menu bar clutter. No `.app` bundle, no Dock icon, no GUI framework overhead.
- **launchd-native** — Designed to run as a macOS launchd service. The system manages its lifecycle automatically — starts on login, restarts on crash, stops on shutdown.
- **Lower resource footprint** — No GUI event loop or Cocoa application lifecycle. Just a focused process that listens for gestures and talks to AeroSpace over a Unix socket.
- **TOML-based configuration** — All settings live in a simple config file. Change behavior without rebuilding or restarting — just send a `SIGHUP` to reload.
- **Composable** — As a CLI tool, it integrates naturally with shell scripts, dotfile managers, and Nix/Homebrew workflows. No drag-and-drop installation or manual permission clicks beyond the initial accessibility grant.

## Prerequisites

- macOS 13 (Ventura) or later
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) window manager installed and running
- Accessibility permissions granted (the app will prompt on first run)

## Installation

### Homebrew

```bash
brew install derangga/formulae/aerogesture
```

### Nix Darwin (Flakes)

Add AeroGesture to your `flake.nix`:

```nix
{
  inputs = {
    aerogesture.url = "github:derangga/aerospacegesture";
  };

  outputs = { self, nixpkgs, aerogesture, ... }: {
    darwinConfigurations.myhost = nix-darwin.lib.darwinSystem {
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            aerogesture.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

### Build from Source

```bash
git clone https://github.com/derangga/aerospacegesture.git
cd aerospacegesture
swift build -c release
cp -f .build/release/aerogesture /usr/local/bin/
```

## Configuration

Create your config file at `~/.config/aerogesture/config.toml`:

```toml
[gesture]
# Number of fingers for swipe gesture (3 or 4)
fingers = 3

# Sensitivity multiplier (lower = more sensitive)
sensitivity = 1.0

# Natural (trackpad-like) direction: swipe right -> previous workspace
natural_direction = true

[workspace]
# Wrap around at the ends of the workspace list
wrap_around = false

# Skip workspaces with no windows
skip_empty = false
```

A full example is available in [`config.toml.example`](config.toml.example).

## Usage

### Run directly

```bash
aerogesture
aerogesture --config /path/to/config.toml
```

### Run as a launchd daemon

Copy the provided plist to your LaunchAgents directory:

```bash
cp -f com.aerogesture.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.aerogesture.plist
```

The daemon will start automatically on login. To stop it:

```bash
launchctl unload ~/Library/LaunchAgents/com.aerogesture.plist
```

### Reload configuration

Reload the config without restarting:

```bash
aerogesture --reload
```

### View logs

```bash
tail -f /tmp/aerogesture.stdout.log
tail -f /tmp/aerogesture.stderr.log
```

### CLI options

```
Usage: aerogesture [options]

Options:
  --config <path>  Override config file path
  --reload         Send SIGHUP to running instance to reload config
  --version        Print version and exit
  --help           Show this help
```

## License

MIT

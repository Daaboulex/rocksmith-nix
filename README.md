# rocksmith-nix

[![CI](https://github.com/Daaboulex/rocksmith-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Daaboulex/rocksmith-nix/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Daaboulex/rocksmith-nix)](./LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![Last commit](https://img.shields.io/github/last-commit/Daaboulex/rocksmith-nix)](https://github.com/Daaboulex/rocksmith-nix/commits)
[![Stars](https://img.shields.io/github/stars/Daaboulex/rocksmith-nix?style=flat)](https://github.com/Daaboulex/rocksmith-nix/stargazers)
[![Issues](https://img.shields.io/github/issues/Daaboulex/rocksmith-nix)](https://github.com/Daaboulex/rocksmith-nix/issues)

Rocksmith 2014 packaged for NixOS — WineASIO, rs-autoconnect, RS_ASIO, and declarative Home Manager module.

## Upstream

This is a **Nix-friendly fork** — credits to all upstream projects:

- **Forked from**: [re1n0/nixos-rocksmith](https://github.com/re1n0/nixos-rocksmith) — original NixOS flake (restructured here to Daaboulex Nix Packaging Standard v1.x)
- **Linux setup reference**: [nizo/linux-rocksmith](https://codeberg.org/nizo/linux-rocksmith)
- **JACK auto-connect shim (`librsshim.so`)**: [KczBen/rs-linux-autoconnect](https://github.com/KczBen/rs-linux-autoconnect)
- **WineASIO driver**: [wineasio/wineasio](https://github.com/wineasio/wineasio)
- **RS_ASIO wrapper**: [mdias/rs_asio](https://github.com/mdias/rs_asio)
- **License**: GPL-3.0 (inherited from upstream)

This repo does **not** redistribute Rocksmith 2014 itself — it ships only the audio glue + launch wrapper. You must own the game on Steam.

## What Is This?

A Nix flake that wires together every Linux component needed to play Rocksmith 2014 on NixOS:

- **Four packages** — `patch-rocksmith` shell helper, `wineasio-32` (32-bit Wine ASIO bridge), `rs-autoconnect` (JACK auto-connect shim), `rs-asio` (Rocksmith's ASIO wrapper DLL)
- **Home Manager module** — generates `RS_ASIO.ini` + `Rocksmith.ini` declaratively, deploys DLLs into the Proton prefix on every launch, exports a `rocksmith-launch` Steam wrapper that does the dance automatically
- **NixOS module** — Steam FHS injection (so 32-bit `libjack.so` is reachable inside the sandbox) + PAM realtime limits for the `@audio` group
- **Optional GoXLR Line-In routing** — WirePlumber rules wiring guitar input through GoXLR Mini/Full
- **Eval + format CI** — no upstream-tracking workflow (own code), weekly `flake.lock` maintenance only

## Packages

| Package | Arch | Description |
|---------|------|-------------|
| `patch-rocksmith` | x86_64 | Shell script to register WineASIO in a Rocksmith Proton prefix |
| `wineasio-32` | i686 | 32-bit ASIO-to-JACK driver for Wine (bridges Wine ASIO → PipeWire JACK) |
| `rs-autoconnect` | i686 | `librsshim.so` — shim library that auto-connects Rocksmith's JACK ports to PipeWire |
| `rs-asio` | x86_64 | RS_ASIO v0.7.4 DLLs — ASIO driver wrapper that intercepts Rocksmith's audio calls |

## Home Manager Module

The repo exports `homeManagerModules.default` — a full HM module that provides:

- **`rocksmith-launch`** wrapper script (set as Steam launch option)
- **RS_ASIO.dll + avrt.dll** deployed from Nix store (no network at runtime)
- **RS_ASIO.ini** generated declaratively (WineASIO driver config)
- **Rocksmith.ini** generated declaratively (game audio settings)
- **WineASIO DLLs** auto-installed into Proton prefix
- **WirePlumber rules** for GoXLR Line In → WineASIO routing (optional)
- **Environment variables** (WINEDLLOVERRIDES, LD_PRELOAD, PIPEWIRE_LATENCY)

### Options

```nix
myModules.home.rocksmith = {
  enable = true;                        # Enable Rocksmith configuration
  latencyBuffer = 2;                    # 1-4, lower = less latency (default: 2)
  pipewireLatency = "256/48000";        # quantum/rate (default: "256/48000")
  steamAppDir = "~/.steam/...";         # Auto-detected (default: standard Steam path)
  goxlr.lineInRouting = true;           # WirePlumber rules for GoXLR Line In
  goxlr.deviceName = "GoXLRMini";       # "GoXLRMini" or "GoXLR" (default: "GoXLRMini")
};
```

## Audio Chain

```
Guitar → 3.5mm cable → Audio Interface Line In
  → PipeWire/ALSA capture → PipeWire JACK → WineASIO (32-bit)
  → RS_ASIO → Rocksmith 2014
```

On Windows, Rocksmith uses a native ASIO driver (e.g., GoXLR ASIO). On Linux, `wineasio-32` bridges Wine's ASIO calls to PipeWire's JACK emulation, and `rs-autoconnect` (`librsshim.so`) handles automatic JACK port routing. RS_ASIO.dll intercepts Rocksmith's audio initialization and redirects it through WineASIO.

## Usage

### 1. Add flake input

```nix
# flake.nix
inputs.rocksmith-nix = {
  url = "github:Daaboulex/rocksmith-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Wire into host config

```nix
# In host flake-module.nix

# Overlay (provides pkgs.rs-asio, pkgs.wineasio-32, etc.)
nixpkgs.overlays = [ inputs.rocksmith-nix.overlays.default ];

# HM module
home-manager.sharedModules = [ inputs.rocksmith-nix.homeManagerModules.default ];

# NixOS module (Steam FHS injection + PAM limits)
imports = [ inputs.self.nixosModules.gaming-rocksmith ];
```

### 3. Enable in host HM config

```nix
myModules.home.rocksmith.enable = true;
myModules.home.rocksmith.goxlr.lineInRouting = true;  # if using GoXLR
```

### 4. Set Steam launch option (one-time)

```
rocksmith-launch %command%
```

That's it. Everything else is automatic on every game launch.

Optional additions to the launch option:
- `gamemoderun rocksmith-launch %command%` — enable gamemode (CPU governor + scheduling)
- `MANGOHUD=1 rocksmith-launch %command%` — enable FPS overlay

### What the launch wrapper does

On every game start, `rocksmith-launch` automatically:

1. Copies `RS_ASIO.dll` + `avrt.dll` from the Nix store into the game directory
2. Deploys generated `RS_ASIO.ini` and `Rocksmith.ini`
3. Copies `wineasio32.dll` into the Proton prefix
4. Sets environment variables:

| Variable | Value | Purpose |
|---|---|---|
| `WINEDLLOVERRIDES` | `wineasio=n,b` | Use native WineASIO DLL |
| `LD_PRELOAD` | `librsshim.so:libjack.so` | JACK auto-connect + 32-bit JACK in FHS sandbox |
| `PIPEWIRE_LATENCY` | `256/48000` | Match PipeWire quantum (configurable) |
| `WINEASIO_NUMBER_INPUTS` | `2` | Prevent enumeration crash with multi-device setups |
| `WINEASIO_FIXED_BUFFERSIZE` | `1` | Lock buffer to PipeWire quantum |
| `WINEASIO_PREFERRED_BUFFERSIZE` | `256` | Derived from `pipewireLatency` option |

## System Requirements

- **PipeWire** with JACK enabled (`services.pipewire.jack.enable = true`)
- **Low-latency audio** — 48kHz @ 256 quantum (5.3ms) recommended
- **PAM realtime limits** for the `@audio` group (memlock unlimited, rtprio 99)
- **Steam** with Proton

## Development

```bash
nix develop      # Enter dev shell (installs git hooks, provides nil LSP)
nix fmt          # Format all Nix files (nixfmt-rfc-style)
nix build        # Build default package (patch-rocksmith)
nix flake check  # Run all checks (eval + format)
```

Build individual packages:

```bash
nix build .#patch-rocksmith
nix build .#wineasio-32
nix build .#rs-autoconnect
nix build .#rs-asio
```

## CI/CD

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push/PR | Eval check, format check, build, verify |
| `maintenance.yml` | Weekly (Sunday 4 AM UTC) | Update `flake.lock`, cleanup stale branches |

All GitHub Actions are pinned to full commit SHAs for reproducibility.

## Credits

- [re1n0/nixos-rocksmith](https://github.com/re1n0/nixos-rocksmith) — original NixOS flake
- [nizo/linux-rocksmith](https://codeberg.org/nizo/linux-rocksmith) — Linux Rocksmith setup guides and patch scripts
- [KczBen/rs-linux-autoconnect](https://github.com/KczBen/rs-linux-autoconnect) — JACK auto-connect shim library
- [wineasio](https://github.com/wineasio/wineasio) — ASIO to JACK driver for Wine
- [mdias/rs_asio](https://github.com/mdias/rs_asio) — Rocksmith ASIO wrapper (RS_ASIO)

## License

GPL-3.0 (inherited from upstream)

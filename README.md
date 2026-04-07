# rocksmith-nix

Rocksmith 2014 packaged for NixOS — WineASIO, rs-autoconnect, and patch-rocksmith.

Forked from [re1n0/nixos-rocksmith](https://github.com/re1n0/nixos-rocksmith), restructured to Daaboulex Nix Packaging Standard v1.1.

## Packages

| Package | Arch | Description |
|---------|------|-------------|
| `patch-rocksmith` | x86_64 | Shell script to register WineASIO in a Rocksmith Proton prefix |
| `wineasio-32` | i686 | 32-bit ASIO-to-JACK driver for Wine (bridges Wine ASIO → PipeWire JACK) |
| `rs-autoconnect` | i686 | `librsshim.so` — shim library that auto-connects Rocksmith's JACK ports to PipeWire |

## Audio Chain

```
Guitar → 3.5mm cable → Audio Interface Line In
  → PipeWire/ALSA capture → PipeWire JACK → WineASIO (32-bit)
  → RS_ASIO → Rocksmith 2014
```

On Windows, Rocksmith uses a native ASIO driver (e.g., GoXLR ASIO). On Linux, `wineasio-32` bridges Wine's ASIO calls to PipeWire's JACK emulation, and `rs-autoconnect` (`librsshim.so`) handles automatic JACK port routing.

## Usage

### 1. Add flake input

```nix
# flake.nix
inputs.rocksmith-nix = {
  url = "github:Daaboulex/rocksmith-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Add overlay to host config

```nix
# In your nixosConfiguration
nixpkgs.overlays = [
  inputs.rocksmith-nix.overlays.default
];
```

### 3. Use packages

After the overlay is applied, the packages are available as:
- `pkgs.patch-rocksmith`
- `pkgs.wineasio-32`
- `pkgs.rs-autoconnect`

Inject them into Steam's FHS sandbox via `programs.steam.package` override:

```nix
programs.steam.package = pkgs.steam.override {
  extraLibraries = p: with p; [ pipewire.jack ];  # 32-bit libjack.so
  extraPkgs = p: with p; [ patch-rocksmith wineasio-32 rs-autoconnect ];
};
```

### 4. Steam launch options

Set in Steam UI (right-click Rocksmith 2014 → Properties → Launch Options):

```
WINEDLLOVERRIDES="wineasio=n,b" LD_PRELOAD=/usr/lib32/librsshim.so PIPEWIRE_LATENCY=256/48000 %command%
```

Or use a launch wrapper script that handles config deployment + environment setup automatically.

## System Requirements

- **PipeWire** with JACK enabled (`services.pipewire.jack.enable = true`)
- **Low-latency audio** — 48kHz @ 256 quantum (5.3ms) recommended
- **PAM realtime limits** for the `@audio` group (memlock unlimited, rtprio 99)
- **Steam** with Proton

## Development

```bash
nix develop    # Enter dev shell (installs git hooks, provides nil LSP)
nix fmt        # Format all Nix files (nixfmt-rfc-style)
nix build      # Build default package (patch-rocksmith)
nix flake check  # Run all checks (eval + format)
```

Build individual packages:

```bash
nix build .#patch-rocksmith
nix build .#wineasio-32
nix build .#rs-autoconnect
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

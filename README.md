# rocksmith-nix

Rocksmith 2014 packaged for NixOS — WineASIO, rs-autoconnect, and patch-rocksmith.

Forked from [re1n0/nixos-rocksmith](https://github.com/re1n0/nixos-rocksmith), restructured to [Daaboulex Nix Packaging Standard v1.1](https://github.com/Daaboulex).

## Packages

| Package | Description |
|---------|-------------|
| `patch-rocksmith` | Script to register WineASIO in Rocksmith's Proton prefix |
| `wineasio-32` | 32-bit ASIO-to-JACK driver for Wine |
| `rs-autoconnect` | Shim library (`librsshim.so`) for automatic PipeWire/JACK port connection |

## Usage

Add as a flake input and use the overlay:

```nix
# flake.nix
inputs.rocksmith-nix = {
  url = "github:Daaboulex/rocksmith-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

# In host config (overlay)
nixpkgs.overlays = [ inputs.rocksmith-nix.overlays.default ];
```

Then the packages are available as `pkgs.patch-rocksmith`, `pkgs.wineasio-32`, and `pkgs.rs-autoconnect`.

## Credits

- [re1n0/nixos-rocksmith](https://github.com/re1n0/nixos-rocksmith) — original NixOS flake
- [nizo/linux-rocksmith](https://codeberg.org/nizo/linux-rocksmith) — Linux Rocksmith setup guides and scripts
- [KczBen/rs-linux-autoconnect](https://github.com/KczBen/rs-linux-autoconnect) — JACK auto-connect shim

## License

GPL-3.0 (inherited from upstream)

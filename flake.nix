{
  description = "Rocksmith 2014 packaged for NixOS — WineASIO, rs-autoconnect, RS_ASIO, and launch wrapper";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.3.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };
    # Non-flake sources (upstream scripts and libs)
    linux-rocksmith = {
      url = "git+https://codeberg.org/nizo/linux-rocksmith";
      flake = false;
    };
    rs-linux-autoconnect = {
      url = "github:KczBen/rs-linux-autoconnect";
      flake = false;
    };
  };

  outputs =
    inputs@{
      flake-parts,
      self,
      linux-rocksmith,
      rs-linux-autoconnect,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      imports = [ inputs.std.flakeModules.base ];

      flake.overlays.default = _final: prev: {
        patch-rocksmith = prev.callPackage ./pkgs/patch-rocksmith { inherit linux-rocksmith; };
        wineasio-32 = prev.pkgsi686Linux.callPackage ./pkgs/wineasio-32 { };
        rs-autoconnect = prev.pkgsi686Linux.callPackage ./pkgs/rs-autoconnect {
          inherit rs-linux-autoconnect;
        };
        rs-asio = prev.callPackage ./pkgs/rs-asio { };
      };

      flake.homeManagerModules.default = import ./hm-module.nix;
      flake.homeManagerModules.rocksmith = import ./hm-module.nix;

      perSystem =
        {
          system,
          pkgs,
          self',
          ...
        }:
        {
          packages.patch-rocksmith = pkgs.callPackage ./pkgs/patch-rocksmith { inherit linux-rocksmith; };
          packages.wineasio-32 = pkgs.pkgsi686Linux.callPackage ./pkgs/wineasio-32 { };
          packages.rs-autoconnect = pkgs.pkgsi686Linux.callPackage ./pkgs/rs-autoconnect {
            inherit rs-linux-autoconnect;
          };
          packages.rs-asio = pkgs.callPackage ./pkgs/rs-asio { };
          packages.default = self'.packages.patch-rocksmith;

          checks.module-eval-hm = inputs.std.lib.homeModuleCheck {
            inherit (inputs) nixpkgs home-manager;
            inherit system;
            overlays = [ self.overlays.default ];
            module = ./hm-module.nix;
            config.myModules.home.rocksmith.enable = true;
          };
        };
    };
}

{
  description = "Rocksmith 2014 packaged for NixOS — WineASIO, rs-autoconnect, and patch-rocksmith";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
    {
      self,
      nixpkgs,
      git-hooks,
      linux-rocksmith,
      rs-linux-autoconnect,
    }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      overlays.default = final: prev: {
        patch-rocksmith = final.callPackage ./pkgs/patch-rocksmith { inherit linux-rocksmith; };
        wineasio-32 = final.pkgsi686Linux.callPackage ./pkgs/wineasio-32 { };
        rs-autoconnect = final.pkgsi686Linux.callPackage ./pkgs/rs-autoconnect {
          inherit rs-linux-autoconnect;
        };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { localSystem.system = system; };
        in
        {
          patch-rocksmith = pkgs.callPackage ./pkgs/patch-rocksmith { inherit linux-rocksmith; };
          wineasio-32 = pkgs.pkgsi686Linux.callPackage ./pkgs/wineasio-32 { };
          rs-autoconnect = pkgs.pkgsi686Linux.callPackage ./pkgs/rs-autoconnect {
            inherit rs-linux-autoconnect;
          };
          default = self.packages.${system}.patch-rocksmith;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      checks = forAllSystems (system: {
        pre-commit-check = git-hooks.lib.${system}.run {
          src = self;
          hooks.nixfmt-rfc-style.enable = true;
        };
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            inherit (self.checks.${system}.pre-commit-check) shellHook;
            buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
            packages = [ pkgs.nil ];
          };
        }
      );
    };
}

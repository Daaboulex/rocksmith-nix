{
  linux-rocksmith,
  lib,
  writeShellApplication,
  bash,
  coreutils,
  findutils,
  gawk,
  gnutar,
  unzip,
  wget,
}:
writeShellApplication {
  name = "patch-rocksmith";

  runtimeInputs = [
    bash
    coreutils
    findutils
    gawk
    gnutar
    unzip
    wget
  ];

  text = linux-rocksmith + "/scripts/patch-nixos.sh";

  meta = {
    description = "Script to patch Rocksmith 2014 for Linux (WineASIO registration)";
    homepage = "https://codeberg.org/nizo/linux-rocksmith";
    license = lib.licenses.gpl3Plus;
    mainProgram = "patch-rocksmith";
  };
}

{
  rs-linux-autoconnect,
  lib,
  stdenv,
  cmake,
  libjack2,
}:
stdenv.mkDerivation {
  pname = "rs-autoconnect";
  version = "1.1.1";

  src = rs-linux-autoconnect;

  nativeBuildInputs = [ cmake ];
  buildInputs = [ libjack2 ];

  installPhase = ''
    mkdir -p $out/lib
    cp librsshim.so $out/lib
  '';

  meta = {
    description = "Shim library to automatically connect Rocksmith 2014 to PipeWire/JACK inputs and outputs";
    homepage = "https://github.com/KczBen/rs-linux-autoconnect";
    license = lib.licenses.mit;
  };
}

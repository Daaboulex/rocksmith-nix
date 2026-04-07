{
  lib,
  fetchzip,
}:
fetchzip {
  pname = "rs-asio";
  version = "0.7.4";

  url = "https://github.com/mdias/rs_asio/releases/download/v0.7.4/release-0.7.4.zip";
  hash = "sha256-LksYh6EHgql9OZ+El0uq6mBUcWymj6EpFaHqHJSLnMA=";
  stripRoot = false;

  postFetch = ''
    mkdir -p $out/lib
    cp $out/RS_ASIO.dll $out/lib/
    cp $out/avrt.dll $out/lib/
    # Remove files from root (keep only lib/)
    rm -f $out/RS_ASIO.dll $out/avrt.dll $out/RS_ASIO.ini
  '';

  meta = {
    description = "ASIO driver wrapper for Rocksmith 2014 — redirects audio through WineASIO on Linux";
    homepage = "https://github.com/mdias/rs_asio";
    license = lib.licenses.mit;
  };
}

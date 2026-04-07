{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myModules.home.rocksmith;

  # Rocksmith App ID for Proton prefix path
  appId = "221680";
  prefixDir = "${config.home.homeDirectory}/.steam/steam/steamapps/compatdata/${appId}/pfx";

  rsAsioIni = pkgs.writeText "RS_ASIO.ini" ''
    [Config]
    EnableWasapiOutputs=0
    EnableWasapiInputs=0
    EnableAsio=1

    [Asio]
    BufferSizeMode=driver

    [Asio.Output]
    Driver=wineasio-rsasio
    BaseChannel=0
    EnableSoftwareEndpointVolumeControl=1
    EnableSoftwareMasterVolumeControl=1
    SoftwareMasterVolumePercent=100

    [Asio.Input.0]
    Driver=wineasio-rsasio
    Channel=-1
    EnableSoftwareEndpointVolumeControl=1
    EnableSoftwareMasterVolumeControl=1
    SoftwareMasterVolumePercent=100

    [Asio.Input.1]
    Driver=
    Channel=-1

    [Asio.Input.Mic]
    Driver=wineasio-rsasio
    Channel=1
    EnableSoftwareEndpointVolumeControl=1
    EnableSoftwareMasterVolumeControl=1
    SoftwareMasterVolumePercent=100
  '';

  rocksmithIni = pkgs.writeText "Rocksmith.ini" ''
    [Audio]
    EnableMicrophone=1
    ExclusiveMode=1
    LatencyBuffer=${toString cfg.latencyBuffer}
    ForceDefaultPlaybackDevice=
    ForceWDM=0
    ForceDirectXSink=0
    DumpAudioLog=0
    MaxOutputBufferSize=0
    RealToneCableOnly=0
    MonoToStereoChannel=0
    Win32UltraLowLatencyMode=1
    [Renderer.Win32]
    ShowGamepadUI=0
    ScreenWidth=0
    ScreenHeight=0
    Fullscreen=2
    VisualQuality=3
    RenderingWidth=0
    RenderingHeight=0
    EnablePostEffects=1
    EnableShadows=1
    EnableHighResScope=1
    EnableDepthOfField=0
    EnablePerPixelLighting=1
    MsaaSamples=4
    DisableBrowser=0
    [Net]
    UseProxy=1
    [Global]
    Version=1
  '';

  # Launch wrapper — fully automatic, zero manual steps
  # Set as Steam launch option: rocksmith-launch %command%
  # Runs inside Steam's FHS sandbox, so /usr/lib32 paths are available
  launchScript = pkgs.writeShellApplication {
    name = "rocksmith-launch";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
    ];
    text = ''
      GAME_DIR="${cfg.steamAppDir}"
      PREFIX="${prefixDir}"

      # --- Deploy RS_ASIO DLLs from Nix store (no network needed) ---
      if [ -d "$GAME_DIR" ]; then
        cp -f ${pkgs.rs-asio}/lib/RS_ASIO.dll "$GAME_DIR/RS_ASIO.dll"
        cp -f ${pkgs.rs-asio}/lib/avrt.dll "$GAME_DIR/avrt.dll"
      fi

      # --- Deploy config files (survives Steam updates) ---
      if [ -d "$GAME_DIR" ]; then
        cp -f ${rsAsioIni} "$GAME_DIR/RS_ASIO.ini"
        cp -f ${rocksmithIni} "$GAME_DIR/Rocksmith.ini"
      fi

      # --- Install WineASIO DLLs into Proton prefix (survives prefix recreation) ---
      if [ -d "$PREFIX" ]; then
        SYSDIR="$PREFIX/drive_c/windows/system32"
        mkdir -p "$SYSDIR"

        WINEASIO_DLL=$(find /usr/lib32 /usr/lib -name "wineasio32.dll" -print -quit 2>/dev/null || true)
        WINEASIO_SO=$(find /usr/lib32 /usr/lib -name "wineasio32.dll.so" -print -quit 2>/dev/null || true)

        if [ -n "$WINEASIO_DLL" ]; then
          cp -f "$WINEASIO_DLL" "$SYSDIR/wineasio32.dll"
        fi
        if [ -n "$WINEASIO_SO" ]; then
          cp -f "$WINEASIO_SO" "$SYSDIR/wineasio32.dll.so"
        fi
      fi

      # --- Launch with the right environment ---
      # WineASIO: native DLL override (skips regsvr32 registration)
      export WINEDLLOVERRIDES="wineasio=n,b''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
      # rs-autoconnect: auto-connect JACK ports + 32-bit libjack for WineASIO
      export LD_PRELOAD="/usr/lib32/librsshim.so:/usr/lib32/libjack.so''${LD_PRELOAD:+:$LD_PRELOAD}"
      # PipeWire quantum for this JACK client
      export PIPEWIRE_LATENCY="${cfg.pipewireLatency}"
      # Limit WineASIO input enumeration (prevents crash with multi-device setups like GoXLR)
      export WINEASIO_NUMBER_INPUTS=2
      export WINEASIO_FIXED_BUFFERSIZE=1
      export WINEASIO_PREFERRED_BUFFERSIZE=''${PIPEWIRE_LATENCY%%/*}

      exec "$@"
    '';
  };
in
{
  options.myModules.home.rocksmith = {
    enable = lib.mkEnableOption "Rocksmith 2014 configuration";
    steamAppDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.steam/steam/steamapps/common/Rocksmith2014";
      description = "Path to Rocksmith 2014 game directory";
    };
    latencyBuffer = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Rocksmith latency buffer (1-4, lower = less latency)";
    };
    pipewireLatency = lib.mkOption {
      type = lib.types.str;
      default = "256/48000";
      description = "PIPEWIRE_LATENCY value (quantum/rate)";
    };
    goxlr = {
      lineInRouting = lib.mkEnableOption "WirePlumber rules for GoXLR Line In → Rocksmith";
      deviceName = lib.mkOption {
        type = lib.types.str;
        default = "GoXLRMini";
        description = "GoXLR PipeWire device name (GoXLRMini or GoXLR)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ launchScript ];

    # WirePlumber auto-routing for GoXLR Line In
    xdg.configFile."wireplumber/wireplumber.conf.d/90-rocksmith.conf" = lib.mkIf cfg.goxlr.lineInRouting {
      text = ''
        monitor.alsa.rules = [
          {
            matches = [
              { node.name = "~wineasio*" }
            ]
            actions = {
              update-props = {
                node.target = "alsa_input.usb-TC-Helicon_${cfg.goxlr.deviceName}-00.HiFi__Line1__source"
              }
            }
          }
        ]
      '';
    };
  };
}

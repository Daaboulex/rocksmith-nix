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
    Channel=0
    EnableSoftwareEndpointVolumeControl=1
    EnableSoftwareMasterVolumeControl=1
    SoftwareMasterVolumePercent=100

    [Asio.Input.1]
    Driver=wineasio-rsasio
    Channel=1
    EnableSoftwareEndpointVolumeControl=1
    EnableSoftwareMasterVolumeControl=1
    SoftwareMasterVolumePercent=100

    [Asio.Input.Mic]
    Driver=wineasio-rsasio
    Channel=2
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

      # --- Deploy RS_ASIO DLLs + config files to game directory ---
      if [ -d "$GAME_DIR" ]; then
        cp -f ${pkgs.rs-asio}/lib/RS_ASIO.dll "$GAME_DIR/RS_ASIO.dll"
        cp -f ${pkgs.rs-asio}/lib/avrt.dll "$GAME_DIR/avrt.dll"
        cp -f ${rsAsioIni} "$GAME_DIR/RS_ASIO.ini"
        cp -f ${rocksmithIni} "$GAME_DIR/Rocksmith.ini"
      fi

      # --- Check WineASIO is installed (one-time manual step) ---
      # WineASIO must be compiled against the SAME Wine as the running Proton.
      # patch-rocksmith handles this but requires steam-run (interactive, one-time).
      if [ -d "$GAME_DIR" ] && [ ! -f "$GAME_DIR/wineasio32.dll" ]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║  WineASIO not installed — audio will not work.                  ║"
        echo "║                                                                  ║"
        echo "║  Run this ONCE in your terminal:                                 ║"
        echo "║    steam-run patch-rocksmith                                     ║"
        echo "║                                                                  ║"
        echo "║  This compiles WineASIO against your Proton version.             ║"
        echo "║  Re-run after changing Proton versions.                          ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
      fi

      # --- Launch with the right environment ---
      # CPU topology: Rocksmith crashes on 32+ logical processors (hard-coded engine bug)
      MAX=${toString cfg.maxCpus}
      CPU_LIST=$(seq -s, 0 $((MAX - 1)))
      export WINE_CPU_TOPOLOGY="$MAX:$CPU_LIST"
      # WineASIO: native DLL override (skips regsvr32 registration)
      export WINEDLLOVERRIDES="wineasio=n,b''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
      # Sniper container remaps /usr/lib32/ to /run/host/usr/lib32/ which doesn't exist.
      # Use Nix store paths directly — sniper bind-mounts /nix/store so these survive.
      export LD_LIBRARY_PATH="${pkgs.pkgsi686Linux.pipewire.jack}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      export LD_PRELOAD="${pkgs.rs-autoconnect}/lib/librsshim.so:${pkgs.pkgsi686Linux.pipewire.jack}/lib/libjack.so''${LD_PRELOAD:+:$LD_PRELOAD}"
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
    maxCpus = lib.mkOption {
      type = lib.types.int;
      default = 16;
      description = "Max CPU cores reported to Wine (Rocksmith crashes on 32+)";
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
    xdg.configFile."wireplumber/wireplumber.conf.d/90-rocksmith.conf" =
      lib.mkIf cfg.goxlr.lineInRouting
        {
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

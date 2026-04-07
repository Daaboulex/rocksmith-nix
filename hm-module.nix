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

      # --- Deploy WineASIO DLLs from Nix store ---
      # Copy wineasio32.dll to game dir + prefix (so RS_ASIO's LoadLibrary finds it)
      # Copy .dll.so to ALL known Proton i386-unix dirs (Wine needs this to execute the DLL)
      if [ -d "$GAME_DIR" ]; then
        cp -f ${pkgs.wineasio-32}/lib/wine/i386-windows/wineasio32.dll "$GAME_DIR/wineasio32.dll"
      fi
      for proton_dir in \
        "$HOME/.steam/steam/steamapps/common/Proton - Experimental" \
        "$HOME/.steam/steam/steamapps/common/Proton Hotfix" \
        "$HOME/.steam/steam/steamapps/common/Proton 10.0" \
        "$HOME/.local/share/Steam/compatibilitytools.d/Proton-CachyOS Latest"; do
        UNIX_DIR="$proton_dir/files/lib/wine/i386-unix"
        WIN_DIR="$proton_dir/files/lib/wine/i386-windows"
        if [ -d "$UNIX_DIR" ]; then
          cp -f ${pkgs.wineasio-32}/lib/wine/i386-unix/wineasio32.dll.so "$UNIX_DIR/wineasio32.dll.so"
        fi
        if [ -d "$WIN_DIR" ]; then
          cp -f ${pkgs.wineasio-32}/lib/wine/i386-windows/wineasio32.dll "$WIN_DIR/wineasio32.dll"
        fi
      done

      # --- Replace sniper container's JACK2 with PipeWire's JACK ---
      # The sniper container ships its own libjack.so.0 (JACK2) which tries to connect
      # to a native JACK server that doesn't exist (only PipeWire runs).
      # WineASIO dlopen's libjack.so.0 inside the container and gets the wrong one.
      # Fix: overwrite the container's 32-bit and 64-bit JACK2 libs with PipeWire's JACK.
      SNIPER_BASE="$HOME/.steam/steam/steamapps/common/SteamLinuxRuntime_sniper/var"
      PW_JACK32="${pkgs.pkgsi686Linux.pipewire.jack}/lib"
      PW_JACK64="${pkgs.pipewire.jack}/lib"
      for dir in "$SNIPER_BASE"/tmp-*/usr/lib/i386-linux-gnu; do
        if [ -d "$dir" ]; then
          cp -f "$PW_JACK32"/libjack.so.0.* "$dir/libjack.so.0" 2>/dev/null || true
          cp -f "$PW_JACK32"/libjackserver.so.0.* "$dir/libjackserver.so.0" 2>/dev/null || true
          cp -f "$PW_JACK32"/libjacknet.so.0.* "$dir/libjacknet.so.0" 2>/dev/null || true
        fi
      done
      for dir in "$SNIPER_BASE"/tmp-*/usr/lib/x86_64-linux-gnu; do
        if [ -d "$dir" ]; then
          cp -f "$PW_JACK64"/libjack.so.0.* "$dir/libjack.so.0" 2>/dev/null || true
          cp -f "$PW_JACK64"/libjackserver.so.0.* "$dir/libjackserver.so.0" 2>/dev/null || true
          cp -f "$PW_JACK64"/libjacknet.so.0.* "$dir/libjacknet.so.0" 2>/dev/null || true
        fi
      done

      # --- Launch with the right environment ---
      # CPU topology: Rocksmith crashes on 32+ logical processors (hard-coded engine bug)
      MAX=${toString cfg.maxCpus}
      CPU_LIST=$(seq -s, 0 $((MAX - 1)))
      export WINE_CPU_TOPOLOGY="$MAX:$CPU_LIST"
      # WineASIO: native DLL override (skips regsvr32 registration)
      export WINEDLLOVERRIDES="wineasio=n,b''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
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

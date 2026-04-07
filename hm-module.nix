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
      PREFIX="${prefixDir}"

      # --- Deploy all DLLs to game directory ---
      # RS_ASIO searches the game dir first (GetWineAsioInfo uses LoadLibrary
      # which follows Windows DLL search order: exe dir → system32 → PATH)
      if [ -d "$GAME_DIR" ]; then
        # RS_ASIO wrapper DLLs
        cp -f ${pkgs.rs-asio}/lib/RS_ASIO.dll "$GAME_DIR/RS_ASIO.dll"
        cp -f ${pkgs.rs-asio}/lib/avrt.dll "$GAME_DIR/avrt.dll"
        # WineASIO Windows-side DLL (must be findable by RS_ASIO's LoadLibrary call)
        cp -f ${pkgs.wineasio-32}/lib/wine/i386-windows/wineasio32.dll "$GAME_DIR/wineasio32.dll"
        # Config files
        cp -f ${rsAsioIni} "$GAME_DIR/RS_ASIO.ini"
        cp -f ${rocksmithIni} "$GAME_DIR/Rocksmith.ini"
      fi

      # --- Deploy WineASIO Unix-side .so into Proton's Wine lib dir ---
      # Wine needs BOTH the Windows .dll AND the Unix .dll.so to load a native DLL.
      # The .dll.so must be in Proton's own lib dir, not the prefix.
      # Discover the active Proton install by walking from the prefix.
      if [ -d "$PREFIX" ]; then
        # Also put the Windows DLL in system32 as fallback
        SYSDIR="$PREFIX/drive_c/windows/system32"
        mkdir -p "$SYSDIR"
        cp -f ${pkgs.wineasio-32}/lib/wine/i386-windows/wineasio32.dll "$SYSDIR/wineasio32.dll"

        # Find the Proton install dir from the compatdata structure
        # Steam stores it at compatdata/<appid>/../../common/<Proton>/files/lib/wine/i386-unix
        # But we can reliably find it from STEAM_COMPAT_TOOL_PATHS or by scanning common/
        STEAM_COMMON="$(dirname "$GAME_DIR")"
        for PROTON_CANDIDATE in \
          "$STEAM_COMMON/Proton - Experimental" \
          "$STEAM_COMMON/Proton Hotfix" \
          "$STEAM_COMMON/Proton 10.0" \
          "$HOME/.local/share/Steam/compatibilitytools.d/Proton-CachyOS Latest"; do
          UNIX_DIR="$PROTON_CANDIDATE/files/lib/wine/i386-unix"
          if [ -d "$UNIX_DIR" ]; then
            cp -f ${pkgs.wineasio-32}/lib/wine/i386-unix/wineasio32.dll.so "$UNIX_DIR/wineasio32.dll.so"
          fi
        done
      fi

      # --- Launch with the right environment ---
      # CPU topology: Rocksmith crashes on 32+ logical processors (hard-coded engine bug)
      # Generate WINE_CPU_TOPOLOGY dynamically from maxCpus option
      MAX=${toString cfg.maxCpus}
      CPU_LIST=$(seq -s, 0 $((MAX - 1)))
      export WINE_CPU_TOPOLOGY="$MAX:$CPU_LIST"
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

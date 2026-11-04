{ lib, pkgs, ... }:
let
  lua = lib.generators.mkLuaInline;
  bind = key: action: { _args = [ key (lua action) ]; };
  exec = key: command: bind key "hl.dsp.exec_cmd(${builtins.toJSON command})";
  workspaceKeys = (map (i: { key = toString (lib.mod i 10); workspace = i; }) (lib.range 1 10))
    ++ (map (i: { key = "F${toString i}"; workspace = 20 + i; }) (lib.range 1 4));
in

{
  home.sessionVariables = {
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";
    HYPRCURSOR_THEME = "Bibata-Modern-Classic";
    HYPRCURSOR_SIZE = "24";

    # Wayland & Qt
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";

    # NVIDIA VA-API and GLX; do not force PRIME offload for every application.
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  wayland.windowManager.hyprland.enable = true;
  wayland.windowManager.hyprland.package = pkgs.hyprland;
  # Hyprland 0.57 removed the legacy hyprland.conf parser.
  wayland.windowManager.hyprland.configType = "lua";
  # Home Manager imports the session environment and starts graphical services.
  wayland.windowManager.hyprland.systemd.enable = true;

  wayland.windowManager.hyprland.settings = {

    monitor = [
      # Use the connected display's preferred mode (the current Samsung is 60 Hz).
      { output = "HDMI-A-1"; mode = "preferred"; position = "0x0"; scale = 1; }
      { output = "DP-2"; mode = "1920x1080@60"; position = "1920x0"; scale = 1; }
    ];

    config = {
      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        force_default_wallpaper = 0; # Set to 0 to disable the anime mascot
      };

      input = {
        kb_layout = "hu";
        follow_mouse = 1;
        sensitivity = -0.167;
        accel_profile = "flat";
      };

      decoration = {
        rounding = 16;
      };

      general = {
        gaps_in = 2;
        gaps_out = 2;
        border_size = 1;

        col.active_border = "rgba(a89984ff)";
        col.inactive_border = "rgba(a89984aa)";
        resize_on_border = false;
        allow_tearing = false;
        layout = "dwindle";
      };

      animations = {
        enabled = true;
      };

      dwindle = {
        preserve_split = true;
      };
    };

    device = {
      name = "epic-mouse-v1";
      sensitivity = -0.5;
    };

    curve = [
      { _args = [ "majesticBezier" { type = "bezier"; points = [ [ 0.15 0.9 ] [ 0.25 1.05 ] ]; } ]; }
      { _args = [ "softFade" { type = "bezier"; points = [ [ 0.4 0 ] [ 0.2 1 ] ]; } ]; }
    ];
    animation = map (leaf: {
      inherit leaf;
      enabled = true;
      speed = 3;
      bezier = if leaf == "fade" then "softFade" else "majesticBezier";
    }) [ "windows" "border" "fade" "workspaces" ];

    bind = [
      (exec "CTRL + ALT + T" "kitty")
      (exec "ALT + D" "vicinae toggle")
      (exec "ALT + F" "chromium")
      (exec "ALT + E" "thunar")
      (bind "ALT + Q" "hl.dsp.window.close()")
      (bind "ALT + M" "hl.dsp.exit()")
      (bind "CTRL + SHIFT + SPACE" ''hl.dsp.window.float({ action = "toggle" })'')
      (bind "ALT + SHIFT + F" "hl.dsp.window.fullscreen()")
      (bind "ALT + P" "hl.dsp.window.pseudo()")
      (bind "CTRL + ALT + left" ''hl.dsp.focus({ direction = "left" })'')
      (bind "CTRL + ALT + right" ''hl.dsp.focus({ direction = "right" })'')
      (bind "CTRL + ALT + up" ''hl.dsp.focus({ direction = "up" })'')
      (bind "CTRL + ALT + down" ''hl.dsp.focus({ direction = "down" })'')
      (bind "ALT + mouse_down" ''hl.dsp.focus({ workspace = "e+1" })'')
      (bind "ALT + mouse_up" ''hl.dsp.focus({ workspace = "e-1" })'')
      (exec "ALT + SHIFT + S" "grimblast --freeze copysave area ~/Pictures/$(date +%Y-%m-%d_%H-%m-%s).png")
      (exec "ALT + A" "kitty -e reca")
      { _args = [ "ALT + mouse:272" (lua "hl.dsp.window.drag()") { mouse = true; } ]; }
      { _args = [ "ALT + mouse:273" (lua "hl.dsp.window.resize()") { mouse = true; } ]; }
    ] ++ lib.concatMap ({ key, workspace }: [
      (bind "ALT + ${key}" "hl.dsp.focus({ workspace = ${toString workspace} })")
      (bind "ALT + SHIFT + ${key}" "hl.dsp.window.move({ workspace = ${toString workspace} })")
    ]) workspaceKeys;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-hyprland ];
  };
}

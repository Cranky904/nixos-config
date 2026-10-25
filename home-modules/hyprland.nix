{ pkgs, ... }:

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
  wayland.windowManager.hyprland.configType = "hyprlang";
  # Home Manager imports the session environment and starts graphical services.
  wayland.windowManager.hyprland.systemd.enable = true;

  wayland.windowManager.hyprland.settings = {

    monitor = [
      "HDMI-A-1, 1920x1080@100, 0x0, 1"
      "DP-2, 1920x1080@60, 1920x0, 1"
    ];

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

    device = {
      name = "epic-mouse-v1";
      sensitivity = -0.5;
      };

    decoration = {
      rounding = 16;
    };

    general = {
      gaps_in = 2;
      gaps_out = 2;
      border_size = 1;

      "col.active_border" = "rgba(a89984ff)";
      "col.inactive_border" = "rgba(a89984aa)";
      resize_on_border = false;
      allow_tearing = false;
      layout = "dwindle";
    };

    "$mainMod" = "MOD1";
    "$terminal" = "kitty";
    "$applaunch" = "vicinae toggle";
    "$browser" = "chromium";
    "$fileManager" = "thunar";

    animations = {
      enabled = true;
      bezier = [
        "majesticBezier, 0.15, 0.9, 0.25, 1.05"
        "softFade, 0.4, 0, 0.2, 1"
      ];
      animation = [
        "windows, 1, 3, majesticBezier"
        "border, 1, 3, majesticBezier"
        "fade, 1, 3, softFade"
        "workspaces, 1, 3, majesticBezier"
      ];
    };

    dwindle = {
      preserve_split = true;
    };

    bind = [
      "CTRL ALT, T, exec, $terminal"
      "$mainMod, D, exec, $applaunch"
      "$mainMod, F, exec, $browser"
      "$mainMod, Q, killactive"
      "$mainMod, M, exit"
      "$mainMod, E, exec, $fileManager"
      "CTRL SHIFT, SPACE, togglefloating"
      "$mainMod SHIFT, F, fullscreen"
      "$mainMod, P, pseudo"

      "CTRL $mainMod, left, movefocus, l"
      "CTRL $mainMod, right, movefocus, r"
      "CTRL $mainMod, up, movefocus, u"
      "CTRL $mainMod, down, movefocus, d"

      "$mainMod, 1, workspace, 1"
      "$mainMod, 2, workspace, 2"
      "$mainMod, 3, workspace, 3"
      "$mainMod, 4, workspace, 4"
      "$mainMod, 5, workspace, 5"
      "$mainMod, 6, workspace, 6"
      "$mainMod, 7, workspace, 7"
      "$mainMod, 8, workspace, 8"
      "$mainMod, 9, workspace, 9"
      "$mainMod, 0, workspace, 10"
      "$mainMod, F1, workspace, 21"
      "$mainMod, F2, workspace, 22"
      "$mainMod, F3, workspace, 23"
      "$mainMod, F4, workspace, 24"

      "$mainMod SHIFT, 1, movetoworkspace, 1"
      "$mainMod SHIFT, 2, movetoworkspace, 2"
      "$mainMod SHIFT, 3, movetoworkspace, 3"
      "$mainMod SHIFT, 4, movetoworkspace, 4"
      "$mainMod SHIFT, 5, movetoworkspace, 5"
      "$mainMod SHIFT, 6, movetoworkspace, 6"
      "$mainMod SHIFT, 7, movetoworkspace, 7"
      "$mainMod SHIFT, 8, movetoworkspace, 8"
      "$mainMod SHIFT, 9, movetoworkspace, 9"
      "$mainMod SHIFT, 0, movetoworkspace, 10"
      "$mainMod SHIFT, F1, movetoworkspace, 21"
      "$mainMod SHIFT, F2, movetoworkspace, 22"
      "$mainMod SHIFT, F3, movetoworkspace, 23"
      "$mainMod SHIFT, F4, movetoworkspace, 24"

      "$mainMod, mouse_down, workspace, e+1"
      "$mainMod, mouse_up, workspace, e-1"

      "$mainMod SHIFT, S, exec, grimblast --freeze copysave area ~/Pictures/$(date +%Y-%m-%d_%H-%m-%s).png"

      "$mainMod, A, exec, kitty -e reca"
    ];

    bindm = [
      "$mainMod, mouse:272, movewindow"
      "$mainMod, mouse:273, resizewindow"
    ];
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-hyprland ];
  };
}

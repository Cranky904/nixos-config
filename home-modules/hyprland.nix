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

    # --- NVIDIA SPECIAL SAUCE ---
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __VK_LAYER_NV_optimus = "NVIDIA_only";
    WLR_NO_HARDWARE_CURSORS = "1";
    WLR_RENDERER_ALLOW_SOFTWARE = "1"; # fallback for some setups
    WLR_DRM_NO_ATOMIC = "1"; # sometimes needed for older drivers
  };

  wayland.windowManager.hyprland.enable = true;
  wayland.windowManager.hyprland.package = pkgs.hyprland; # make sure it’s from nixpkgs-unstable

  wayland.windowManager.hyprland.settings = {
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
      rounding = 0;
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

    exec-once = [
      "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
      "waybar"
      "hyprpaper"
    ];

    "$mainMod" = "MOD1";
    "$terminal" = "kitty";
    "$applaunch" = "rofi -show drun";
    "$browser" = "librewolf";
    "$fileManager" = "thunar";

    animations = {
      enabled = false;
      bezier = [
        "majesticBezier, 0.15, 0.9, 0.25, 1.05"
        "softFade, 0.4, 0, 0.2, 1"
      ];
      animation = [
        "windows, 1, 7, majesticBezier"
        "border, 1, 5, majesticBezier"
        "fade, 1, 5, softFade"
        "workspaces, 1, 6, majesticBezier"
      ];
    };

    dwindle = {
      pseudotile = true;
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

      "CTRL SHIFT, left, movefocus, l"
      "CTRL SHIFT, right, movefocus, r"
      "CTRL SHIFT, up, movefocus, u"
      "CTRL SHIFT, down, movefocus, d"

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

      "$mainMod, mouse_down, workspace, e+1"
      "$mainMod, mouse_up, workspace, e-1"

      "$mainMod SHIFT, S, exec, grimblast --freeze copysave area ~/Pictures/$(date +%Y-%m-%d_%H-%m-%s).png"
    ];

    bindm = [
      "$mainMod, mouse:272, movewindow"
      "$mainMod, mouse:273, resizewindow"
    ];

    windowrulev2 = [
      "suppressevent maximize, class:.*"
    ];
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-hyprland ];
  };
}

{ pkgs, ... }:

{
  services.hyprpaper.enable = true;

  # The wildcard covers hotplugged outputs and avoids empty-key parsing issues.
  xdg.configFile."hypr/hyprpaper.conf".text = ''
    wallpaper {
      monitor = *
      path = ${../wallpaper/wallpaper.png}
    }
  '';
}

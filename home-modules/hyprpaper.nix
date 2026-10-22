{ pkgs, ... }:

{
  services.hyprpaper.enable = true;

  xdg.configFile."hypr/hyprpaper.conf".text = ''
    wallpaper {
      monitor = HDMI-A-1
      path = ${../wallpaper/wallpaper.png}
    }
  '';
}

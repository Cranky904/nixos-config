{ pkgs, ... }:

{
  services.hyprpaper.enable = true;

  services.hyprpaper.settings = {
    preload = [ "/home/cranky/nixos-config/wallpaper/wallpaper.png" ];

    wallpaper = [
      "HDMI-A-1,/home/cranky/nixos-config/wallpaper/wallpaper.png"
    ];
  };
}

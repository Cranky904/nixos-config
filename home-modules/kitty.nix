{ pkgs, ... }:

{
  programs.kitty.enable = true;
  programs.kitty.themeFile = "Jellybeans";

  programs.kitty.font.name = "0xProto Nerd Font Mono";
  programs.kitty.font.package = pkgs.nerd-fonts._0xproto;
  programs.kitty.font.size = 11;

  programs.kitty.settings = {
    background_opacity = 0.85;
    background_blur = 1;
  };
}

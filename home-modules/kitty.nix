{ pkgs, ... }:

{
  programs.kitty.enable = true;

  programs.kitty.theme = "Gruvbox Dark";

  programs.kitty.font.name = "0xProto Nerd Font Mono";
  programs.kitty.font.package = pkgs.nerd-fonts._0xproto;
  programs.kitty.font.size = 13;

  programs.kitty.settings = {
    background_opacity = 0.85;
    background_blur = 1;
  };
}

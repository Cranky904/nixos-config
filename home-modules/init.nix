{ config, pkgs, ... }:

{
  home.username = "cranky";
  home.homeDirectory = "/home/cranky";

  imports = [
    ./env.nix
    ./packages.nix
    ./nixvim.nix
    ./hyprland.nix
    ./kitty.nix
    ./vesktop.nix
    ./waybar.nix
    ./rofi.nix
    ./hyprpaper.nix
    ./gtk.nix
    ./qt.nix
    ./fish.nix
    ./git.nix
  ];

  home.stateVersion = "25.05";
}

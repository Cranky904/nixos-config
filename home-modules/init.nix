{ config, pkgs, ... }:

{
  home.username = "cranky";
  home.homeDirectory = "/home/cranky";
  # RECA is developed and installed with Cargo outside this flake.
  home.sessionPath = [ "${config.home.homeDirectory}/.cargo/bin" ];

  programs.home-manager.enable = true;

  imports = [
    ./env.nix
    ./packages.nix
    ./nixvim.nix
    ./hyprland.nix
    ./kitty.nix
    ./vesktop.nix
    ./vicinae.nix
    ./hyprpaper.nix
    ./gtk.nix
    ./qt.nix
    ./fish.nix
    ./git.nix
    ./swaync.nix
    ./chromium.nix
    ./quickshell.nix
  ];

  home.stateVersion = "25.05";
}

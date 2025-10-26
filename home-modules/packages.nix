{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    # User packages
    fastfetch
    ripgrep
    fd
    eza
    bat
    feh
    mpv

    pgcli

    gpu-screen-recorder

    gnumake

    obsidian

    rustc
    cargo

    yarn

    btop

    pavucontrol

    nodejs

    home-manager

    go
    rustfmt
    rust-analyzer
    zig

    # Terminal
    kitty
    fzf
    starship
    grc

    # Hyprland ecosystem
    wl-clipboard
    waybar
    rofi
    mako
    swaylock-effects
    swaybg
    dunst
    grimblast
    nil
    hyprpaper
    networkmanagerapplet
    btop
    ddcutil
    
    # HyprPanel
    wireplumber
    libgtop
    upower
    gtksourceview3
    # *optional
    hyprpicker
    hyprsunset

    # QT stuff
    libsForQt5.qt5ct

    # Theming
    vimix-icon-theme
    bibata-cursors
    gruvbox-gtk-theme
    # Fonts
    mplus-outline-fonts.githubRelease

    mangohud

    # PGP
    gnupg
    pinentry-all

    element-desktop

    gamemode

    librewolf

    # Jellyfin
    jellyfin
    jellyfin-ffmpeg
    jellyfin-web
    jellyfin-rpc

    aerc

    heroic
  ];
}

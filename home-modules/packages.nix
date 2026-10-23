{ config, pkgs, ... }:

let
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin";
    hash = "sha256-kh5M+Ghv3Zk9zQgaXaW2w2W/3hFi5ysI11rHUomSCx8=";
  };

  aagl-gtk-on-nix = import (
    builtins.fetchTarball {
      url = "https://github.com/ezKEa/aagl-gtk-on-nix/archive/d82d6d6f66caf4b63fb154e62fad83c627874127.tar.gz";
      sha256 = "10f8g8ywkhh1cdid5ksng5zfviqycfiwkdc8qhs0l75dc249j7ws";
    }
  );
in

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
    whisper-cpp

    pgcli

    gpu-screen-recorder

    gnumake

    obsidian

    grim

    rustc
    cargo
    libc

    gcc

    codex
    t3code
    gh

    yarn

    pavucontrol

    nodejs

    go
    rustfmt
    rust-analyzer
    zig

    thunar

    playerctl
    keepassxc

    pixelorama

    # T3 Dependencies

    nspr
    nss
    atk
    at-spi2-atk
    at-spi2-core
    xorg.libXcomposite
    xorg.libX11
    xorg.libXext
    xorg.libXfixes
    xorg.libXdamage
    xorg.libXrandr
    xorg.libxcb
    glib
    dbus
    cups
    libdrm
    libgbm
    libxkbcommon
    pango
    cairo
    alsa-lib

    # T3 artifact dependencies
    poppler-utils
    libreoffice

    (python3.withPackages (ps: with ps; [
      pillow
      playwright
      reportlab
      pypdf
      python-docx
      openpyxl
    ]))

    # Games
    prismlauncher

    aagl-gtk-on-nix.honkers-railway-launcher

    # Terminal
    fzf
    grc

    mumble

    # Torrent
    qbittorrent

    # Hyprland ecosystem
    wl-clipboard
    swaylock-effects
    swaybg
    grimblast
    nil
    networkmanagerapplet
    btop
    ddcutil
    ffmpeg

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
    gruvbox-dark-gtk
    # Fonts
    mplus-outline-fonts.githubRelease

    mangohud

    # PGP
    gnupg
    pinentry-all

    gamemode
    gamescope

    # Discord rich presence; independent of the removed Jellyfin server.
    jellyfin-rpc

    aerc
    unzip
    unrar
  ];

  xdg.dataFile."reca/models/ggml-tiny.en.bin".source = whisperModel;

  home.sessionVariables = {
    RECA_PW_RECORD = "${pkgs.pipewire}/bin/pw-record";
    RECA_FFMPEG = "${pkgs.ffmpeg}/bin/ffmpeg";
    RECA_WHISPER_CLI = "${pkgs.whisper-cpp}/bin/whisper-cli";
    RECA_WHISPER_MODEL = "${whisperModel}";
  };
}

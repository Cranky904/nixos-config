{ config, pkgs, ... }:

{
  programs.chromium = {
    enable = true;

    commandLineArgs = [
      "--ozone-platform=wayland"
      "--enable-features=WaylandWindowDecorations"
    ];

    dictionaries = [
      pkgs.hunspellDictsChromium.en_US
    ];

    extensions = [
      # uBlock Origin Lite
      { id = "ddkjiahejlhfcafbddmgiahcphecmpfh"; }
      # Dark Reader
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; }
      # gruvbox slate
      { id = "giokfhncgfjkoamdbhfhfhgpikaioccc"; }
    ];
  };
}

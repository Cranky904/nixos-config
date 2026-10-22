{
  config,
  lib,
  pkgs,
  ...
}:

let
  runtimePath = lib.makeBinPath [
    pkgs.nodejs
    pkgs.yt-dlp
  ];

  ytDlpExtension = config.lib.vicinae.mkExtension {
    name = "yt-dlp";
    src = pkgs.fetchFromGitHub {
      owner = "PhrolovaMoe";
      repo = "vicinae-yt-dlp";
      rev = "45d86e6454b8d8a481830be66c7ce476c53fc7b9";
      hash = "sha256-9B3asegtExA8sb+wQF+cTpJkERQncwoTfFdnehtu9qg=";
    };
    npmDepsHash = "sha256-6pbUB89RilhlneFCX+MT8gpBgPQL8LAO64odZzjvvWA=";
  };
in
{
  programs.vicinae = {
    enable = true;
    systemd.enable = true;

    settings = {
      close_on_focus_loss = true;
      pop_to_root_on_close = true;

      font.normal = {
        family = "0xProto Nerd Font Mono";
        size = 13;
      };

      theme = {
        light.name = "quickshell-gruvbox-dark";
        dark.name = "quickshell-gruvbox-dark";
      };

      launcher_window = {
        opacity = 0.96;
        rounding = 16;
        client_side_decorations.border_width = 1;
      };
    };

    themes.quickshell-gruvbox-dark = {
      meta = {
        version = 1;
        name = "Quickshell Gruvbox Dark";
        description = "Vicinae theme matching the Quickshell desktop shell";
        variant = "dark";
        inherits = "vicinae-dark";
      };

      colors = {
        core = {
          background = "#151515";
          foreground = "#ebdbb2";
          secondary_background = "#262626";
          border = "#343434";
          accent = "#ebdbb2";
          accent_foreground = "#151515";
        };

        main_window.border = "#343434";
        settings_window.border = "#343434";
        shortcut.border = "#343434";

        text = {
          default = "#ebdbb2";
          muted = "#a89984";
          placeholder = "#a89984";
          selection = {
            background = "#ebdbb2";
            foreground = "#151515";
          };
        };

        input = {
          border = "#343434";
          border_focus = "#ebdbb2";
        };

        list.item = {
          hover.background = "#262626";
          selection = {
            background = "#ebdbb2";
            foreground = "#151515";
            secondary_background = "#ebdbb2";
            secondary_foreground = "#151515";
          };
        };

        grid.item = {
          background = "#262626";
          hover.outline = "#343434";
          selection.outline = "#ebdbb2";
        };

        accents = {
          blue = "#83a598";
          green = "#b8bb26";
          magenta = "#d3869b";
          orange = "#d65d0e";
          purple = "#b16286";
          red = "#cc241d";
          yellow = "#fabd2f";
          cyan = "#8ec07c";
        };
      };
    };

    extensions = [ ytDlpExtension ];
  };

  home.packages = [
    pkgs.nodejs
    pkgs.yt-dlp
  ];

  systemd.user.services.vicinae.Service.Environment =
    "PATH=${runtimePath}:${config.home.profileDirectory}/bin:/run/current-system/sw/bin";
}

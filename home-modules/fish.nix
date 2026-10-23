

{ pkgs, config, ... }:

let
  mkPrompt = {
    userBg,
    dirBg,
    gitBg,
    nixBg,
    arrowColor
  }: {
    add_newline = true;

    format =
      "[](fg:${userBg})"
      + "$nix_shell"
      + "$username"
      + "[](fg:${userBg} bg:${dirBg})"
      + "$directory"
      + "$git_branch"
      + "$git_status"
      + "$nix_shell"
      + "[](fg:prev_bg)"
      + "$line_break"
      + "$character";
    
    username = {
      show_always = true;
      style_user = "fg:#11111b bg:${userBg} bold";
      style_root = "fg:#f38ba8 bg:${userBg} bold";
      format = "[ $user ]($style)";
    };

    directory = {
      style = "fg:#11111b bg:${dirBg} bold";
      format = "[ $path ]($style)";
      truncation_length = 4;
      truncation_symbol = "…/";
      home_symbol = "~";
      read_only = " ";
    };

    git_branch = {
      symbol = " ";
      style = "fg:#11111b bg:${gitBg} bold";

      format =
        "[](fg:prev_bg bg:${gitBg})"
        + "[ $symbol$branch ]($style)";
    };

    git_status = {
      style = "fg:#11111b bg:${gitBg}";
      format = "([ $all_status$ahead_behind]($style))";

      conflicted = "=";
      ahead = "⇡";
      behind = "⇣";
      diverged = "⇕";
      untracked = "?";
      stashed = "$";
      modified = "!";
      staged = "+";
      renamed = "»";
      deleted = "✘";
    };

    nix_shell = {
      style = "fg:#11111b bg:${nixBg} bold";
      format =
        "[](fg:prev_bg bg:${nixBg})"
        + "[  nix-shell ]($style)";
    };

    character = {
      success_symbol = "[❯](bold ${arrowColor})";
      error_symbol = "[❯](bold #f38ba8)";
    };
  };

in
{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set -U fish_greeting ""

      if set -q IN_NIX_SHELL
        set -gx STARSHIP_CONFIG "${config.xdg.configHome}/starship-nix.toml"
      end
    '';

    shellAliases = {
      ls = "eza --icons";
      tree = "eza --icons --tree";
      cat = "bat";
      ".." = "cd ..";
      "..." = "cd ../..";
    };

    functions = {
      mkcd = {
        description = "Create a directory and enter it.";
        body = ''
          mkdir -p "$argv[1]"; and cd "$argv[1]"
        '';
      };
    };

    plugins = [
      { name = "z"; src = pkgs.fishPlugins.z.src; }
      { name = "fzf-fish"; src = pkgs.fishPlugins.fzf-fish.src; }
      { name = "grc"; src = pkgs.fishPlugins.grc.src; }
    ];
  };

  # Keep Fish inside nix-shell and nix develop
  programs.nix-your-shell = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    # Normal blue -> purple theme
    settings = mkPrompt {
      userBg = "#74c7ec";
      dirBg = "#3b82f6";
      gitBg = "#cba6f7";
      nixBg = "#f5c06d";
      arrowColor = "#74c7ec";
    };
  };

  # Alternative theme activated inside Nix shells
  xdg.configFile."starship-nix.toml".source =
    (pkgs.formats.toml { }).generate "starship-nix.toml"
      (mkPrompt {
        userBg = "#a6e3a1";
        dirBg = "#d9f99d";
        gitBg = "#f9e2af";
        nixBg = "#f5c06d";
        arrowColor = "#a6e3a1";
      });
}


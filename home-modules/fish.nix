{ pkgs, ... }:

{
  programs.fish = {
    enable = true;

    interactiveShellInit = "set -U fish_greeting ''";

    shellAliases = {
      ls = "eza --icons";
      tree = "eza --icons --tree";
      cat = "bat";
      ".." = "cd ..";
      "..." = "cd ../..";
    };

    functions = {
      mkcd = ''
        mkdir -p "$argv[1]"
    cd "$argv[1]"
      '';
      description = "Create a directory and change into it.";
    };

    plugins = [
      { name = "z"; src = pkgs.fishPlugins.z.src; }
      { name = "fzf-fish"; src = pkgs.fishPlugins.fzf-fish.src; }
      { name = "grc"; src = pkgs.fishPlugins.grc.src; }
    ];
  };

  programs.starship = {
    enable = true;

    enableFishIntegration = true;

    settings = {
      add_newline = true;

      directory = {
        style = "blue bold";
    truncation_length = 4;
    truncation_symbol = "…/";
      };

      git_branch = {
        symbol = " ";
    style = "mauve bold";
      };

      git_status = {
        style = "peach bold";
    conflicted = "= ";
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
        symbol = " ";
        style = "sky bold";
        format = "via [$symbol$state( \($name\))]($style) ";
      };
    };
  };
}

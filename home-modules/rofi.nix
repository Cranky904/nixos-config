{ pkgs, ... }:

{
  programs.rofi.enable = true;

  xdg.configFile."rofi/config.rasi".text = ''
    configuration {
      modi:                  "drun,run,window";
      show-icons:            true;
      terminal:              "kitty";
      drun-display-format:   "{name}";
      font:                  "0xProto Nerd Font Mono 14";
      icon-theme:            "Vimix";
    }

    * {
      bg:           #282828;
      bg-alt:       #3c3836;
      fg:           #ebdbb2;
      accent:       #8ec07c;
      subtle:       #928374;

      background-color: transparent;
      text-color:       @fg;
    }

    window {
      location:         center;
      anchor:           center;
      width:            650px;
      border:           2px;
      border-color:     @subtle;
      border-radius:    15px;
      padding:          15px;
      background-color: @bg;
    }

    mainbox {
      children: [ "inputbar", "listview" ];
      spacing:  15px;
    }

    inputbar {
      children:      [ "prompt", "entry" ];
      padding:       12px;
      border-radius: 10px;
      background-color: @bg-alt;
    }

    prompt {
      enabled:          true;
      padding:          0px 8px 0px 0px;
      background-color: inherit;
      text-color:       @accent;
    }

    entry {
      placeholder:       "Search...";
      placeholder-color: @subtle;
      padding:           0px;
      background-color:  inherit;
    }

    listview {
      lines:    8;
      columns:  1;
      spacing:  8px;
      cycle:    true;
      dynamic:  true;
      layout:   vertical;
    }

    element {
      padding:       10px;
      border-radius: 8px;
    }

    element.normal.normal {
      background-color: @bg;
      text-color:       @fg;
    }

    element.alternate.normal {
      background-color: @bg;
      text-color:       @fg;
    }

    element.selected.normal {
      background-color: @accent;
      text-color:       @bg;
    }

    element-text, element-icon {
      vertical-align: 0.5;
    }

    element-icon {
      size: 1.5em;
      padding: 0 15px 0 5px;
    }
  '';
}

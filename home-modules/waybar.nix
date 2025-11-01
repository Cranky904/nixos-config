{ pkgs, ... }:

{
  programs.waybar.enable = true;

  programs.waybar.settings = {
    mainBar = {
      layer = "top";
      position = "bottom";
      height = 38;
      spacing = 0;

      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "hyprland/window" ];
      modules-right = [ "tray" "custom/brightness" "pulseaudio" "network" "cpu" "memory" "clock" ];

      "hyprland/workspaces" = {
        format = "{icon}";
        format-icons = {
          "1" = "󰈹";
          "2" = "";
          "3" = "";
          "4" = "";
          "5" = "󱤙";
          "6" = "";
          "7" = "";
          "urgent" = "󱢇";
          "default" = "󱣀";
        };
        on-scroll-up = "hyprlandmsg dispatch workspace e+1";
        on-scroll-down = "hyprlandmsg dispatch workspace e-1";
      };

      "hyprland/window" = {
        format = "{}";
        max-length = 35;
        separate-outputs = true;
      };

      "tray" = {
        icon-size = 18;
        spacing = 10;
      };

      "clock" = {
        format = " {:%H:%M}";
        format-alt = " {:%A, %d %B}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt>{calendar}</tt>";
        on-click = "mode";
      };

      "custom/brightness" = {
        exec = "ddcutil --bus 14 getvcp 10 | awk -F 'current value = |, ' '{print $2}'";
        format = "󰃠 {}%";
        interval = 10;
        on-scroll-up = "ddcutil --bus 14 setvcp 10 + 5";
        on-scroll-down = "ddcutil --bus 14 setvcp 10 - 5";
        tooltip = true;
      };

      "cpu" = {
        format = " {usage}%";
        tooltip = true;
        interval = 1;
        on-click = "${pkgs.btop}/bin/btop";
      };

      "memory" = {
        format = "󰍛 {used:0.1f}G";
        interval = 1;
        on-click = "${pkgs.btop}/bin/btop";
      };

      "network" = {
        format-wifi = "  {essid}";
        format-ethernet = "󰈀 {ifname}";
        format-disconnected = "󰖪 Disconnected";
        tooltip-format = "{ifname} via {gwaddr} ";
        on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
      };

      "pulseaudio" = {
        format = "{icon} {volume}%";
        format-muted = "󰖁 Muted";
        format-icons = {
          headphone = "";
          hands-free = "";
          headset = "";
          phone = "";
          portable = "";
          car = "";
          default = ["" "" ""];
        };
        on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
        on-scroll-up = "pactl set-sink-volume @DEFAULT_SINK@ +5%";
        on-scroll-down = "pactl set-sink-volume @DEFAULT_SINK@ -5%";
      };
    };
  };

  programs.waybar.style = ''
    @define-color bg #1d2021;
    @define-color bg-alt #32302f;
    @define-color fg #ebdbb2;
    @define-color red #cc241d;
    @define-color green #98971a;
    @define-color yellow #d79921;
    @define-color blue #458588;
    @define-color purple #b16286;
    @define-color aqua #689d6a;
    @define-color gray #a89984;
    @define-color orange #d65d0e;
    @define-color white #dadada;

    * {
      border: none;
      border-radius: 0;
      font-family: "0xProto Nerd Font Mono", monospace;
      font-size: 14px;
      min-height: 0;
      margin-left: 1px;
      margin-right: 1px;
    }

    window#waybar {
      background: transparent;
      color: @fg;
    }

    #workspaces,
    #window,
    #clock,
    #custom-brightness,
    #cpu,
    #memory,
    #network,
    #pulseaudio,
    #tray {
      background-color: @bg-alt;
      padding: 5px 15px;
      margin: 4px 0px;
      border: 1px solid @gray;
    }

    #workspaces, #window { margin-right: 8px; }
    #memory { margin-right: 8px; }
    #cpu { margin-right: 8px; }
    #network { margin-right: 8px; }
    #pulseaudio { margin-right: 8px; }
    #custom-brightness { margin-right: 8px; }

    #workspaces {
      padding-left: 10px;
      padding-right: 5px;
      background-color: @bg;
    }
    #workspaces button {
      padding: 0 5px;
      color: @gray;
      transition: all 0.3s ease;
    }
    #workspaces button:hover {
      color: @fg;
      background-color: @bg-alt;
    }
    #workspaces button.active {
      color: @blue;
      font-weight: bold;
    }
    #workspaces button.urgent {
      color: @red;
    }

    #clock { color: @white; font-weight: bold; }
    #custom-brightness { color: @yellow; }
    #pulseaudio { color: @aqua; }
    #network { color: @blue; }
    #cpu { color: @yellow; }
    #memory { color: @aqua; }

    tooltip {
      background-color: @bg;
      border: 1px solid @purple;
    }
    tooltip label {
      color: @fg;
    }
  '';
}


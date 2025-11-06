{ config, pkgs, ... }: {
  services.swaync = {
    enable = true;
    
    settings = {
      positionX = "right";
      positionY = "top";
      layer = "overlay";
      control-center-layer = "overlay";
      layer-shell = true;
      css-priority = "user";
      
      # Control center margins
      "control-center-margin-top" = 0;
      "control-center-margin-bottom" = 0;
      "control-center-margin-left" = 0;
      "control-center-margin-right" = 0;
      
      # Notification settings
      "notification-2fa-action" = true;
      "notification-inline-replies" = false;
      "notification-icon-size" = 64;
      "notification-body-image-height" = 100;
      "notification-body-image-width" = 200;
      timeout = 10;
      "timeout-low" = 5;
      "timeout-critical" = 0;
      
      # Control center sizing
      "control-center-width" = 400;
      "control-center-height" = 600;
      "notification-window-width" = 400;
      
      # Keyboard shortcuts
      "keyboard-shortcuts" = true;
      "image-visibility" = "when-available";
      
      # Widget configuration
      widgets = [
        "title"
        "dnd"
        "notifications"
      ];
      
      # Widget configs
      "widget-config" = {
        "title" = {
          "text" = "Notifications";
          "clear-all-button" = true;
        };
        "dnd" = {
          "text" = "Do Not Disturb";
        };
        "notifications" = {
          "clear-all-button" = true;
        };
      };
    };

    style = ''
      /* Gruvbox Dark Color Scheme */
      @define-color bg_h #1d2021;
      @define-color bg #282828;
      @define-color bg_s #32302f;
      @define-color bg1 #3c3836;
      @define-color bg2 #504945;
      @define-color bg3 #665c54;
      @define-color bg4 #7c6f64;

      @define-color fg #ebdbb2;
      @define-color fg1 #fbf1c7;
      @define-color fg2 #d5c4a1;
      @define-color fg3 #bdae93;
      @define-color fg4 #a89984;

      @define-color red #fb4934;
      @define-color green #b8bb26;
      @define-color yellow #fabd2f;
      @define-color blue #83a598;
      @define-color purple #d3869b;
      @define-color aqua #8ec07c;
      @define-color orange #fe8019;
      @define-color gray #928374;

      * {
        all: unset;
        font-family: "Fira Code", "JetBrainsMono Nerd Font", "Font Awesome 6 Free";
        font-size: 13px;
      }

      /* Control Center */
      .control-center {
        background: @bg;
        border: 2px solid @bg2;
        border-radius: 12px;
        padding: 8px;
        box-shadow: 0 0 20px 0 rgba(0, 0, 0, 0.6);
      }

      /* Widgets */
      .widget-title {
        color: @fg1;
        font-size: 16px;
        font-weight: bold;
        margin: 8px 4px;
      }

      .widget-title > button {
        background: @bg2;
        color: @fg;
        border-radius: 8px;
        padding: 6px 12px;
        font-size: 12px;
      }

      .widget-title > button:hover {
        background: @bg3;
      }

      .widget-dnd {
        background: @bg1;
        border-radius: 8px;
        padding: 8px;
        margin: 4px 0;
      }

      .widget-dnd > switch {
        background: @bg3;
        border-radius: 12px;
        min-width: 40px;
        min-height: 20px;
      }

      .widget-dnd > switch:checked {
        background: @green;
      }

      .widget-dnd > switch slider {
        background: @fg;
        border-radius: 50%;
        min-width: 16px;
        min-height: 16px;
        margin: 2px;
      }

      /* Notifications */
      .notification {
        background: @bg1;
        border: 1px solid @bg2;
        border-radius: 10px;
        margin: 6px 0;
        padding: 0;
        box-shadow: 0 2px 8px 0 rgba(0, 0, 0, 0.3);
      }

      .notification-content {
        background: transparent;
        padding: 12px;
        border-radius: 10px;
      }

      .notification-default-action {
        border-radius: 10px;
      }

      .notification-default-action:hover {
        background: alpha(@bg2, 0.3);
      }

      /* Notification Header */
      .notification-header {
        margin-bottom: 6px;
      }

      .notification-app-name {
        color: @blue;
        font-weight: bold;
        font-size: 12px;
      }

      .notification-time {
        color: @gray;
        font-size: 11px;
      }

      /* Notification Body */
      .notification-body {
        color: @fg;
        margin: 4px 0;
      }

      .notification-body image {
        border-radius: 6px;
        border: 1px solid @bg3;
      }

      /* Notification Actions */
      .notification-actions {
        margin-top: 8px;
        border-top: 1px solid @bg2;
        padding-top: 8px;
      }

      .notification-action {
        background: @bg2;
        color: @fg;
        border-radius: 6px;
        padding: 6px 12px;
        margin: 2px;
        font-size: 12px;
      }

      .notification-action:hover {
        background: @bg3;
        color: @fg1;
      }

      .notification-action:active {
        background: @blue;
      }

      /* Close Button */
      .close-button {
        background: @red;
        color: @bg;
        border-radius: 50%;
        min-width: 20px;
        min-height: 20px;
        margin: 4px;
        font-weight: bold;
      }

      .close-button:hover {
        background: shade(@red, 1.2);
      }

      /* Scrollbar */
      scrollbar {
        background: @bg2;
        border-radius: 6px;
      }

      scrollbar slider {
        background: @bg4;
        border-radius: 6px;
        min-width: 8px;
      }

      scrollbar slider:hover {
        background: @fg4;
      }

      /* Progress bar */
      progressbar {
        background: @bg2;
        border-radius: 4px;
        min-height: 6px;
      }

      progressbar progress {
        background: @blue;
        border-radius: 4px;
      }

      /* Urgency Levels */
      .notification.critical {
        border-left: 3px solid @red;
      }

      .notification.normal {
        border-left: 3px solid @blue;
      }

      .notification.low {
        border-left: 3px solid @gray;
      }
    '';
  };
}

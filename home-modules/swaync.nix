{ config, pkgs, ... }: {
  # ... other config ...
  
  # Enable swaync
  services.swaync.enable = true;
  
  # Swaync configuration
  xdg.configFile."swaync/config.json".text = builtins.toJSON {
    "$schema" = "/etc/xdg/swaync/configSchema.json";
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
    "timeout" = 10;
    "timeout-low" = 5;
    "timeout-critical" = 0;
    
    # Control center sizing
    "control-center-width" = 500;
    "control-center-height" = 600;
    
    # Notification sizing
    "notification-window-width" = 500;
    
    # Keyboard shortcuts
    "keyboard-shortcuts" = true;
    "image-visibility" = "when-available";
    
    # Widget configuration
    "widgets" = [
      "inhibitors"
      "title"
      "dnd"
      "notifications"
      "mpris"
    ];
    
    # Widget configs
    "widget-config" = {
      "inhibitors" = {
        "text" = "Inhibitors";
        "button-text" = "Clear All";
        "clear-all-button" = true;
      };
      "title" = {
        "text" = "Notifications";
        "clear-all-button" = true;
        "button-text" = "Clear All";
      };
      "dnd" = {
        "text" = "Do Not Disturb";
      };
      "label" = {
        "max-lines" = 5;
        "text" = "Label Text";
      };
      "mpris" = {
        "image-size" = 96;
        "image-radius" = 12;
      };
    };
  };

  # Optional: CSS styling
  xdg.configFile."swaync/style.css".text = ''
    * {
      all: unset;
      font-family: "Fira Sans Semibold";
      font-size: 12px;
    }
    
    .notification-row {
      outline: none;
    }
    
    .notification {
      border-radius: 12px;
      margin: 6px 12px;
      box-shadow: 0 0 8px 0 rgba(0, 0, 0, 0.8);
      padding: 0;
    }
    
    .notification-content {
      background: transparent;
      padding: 6px;
      border-radius: 12px;
    }
    
    .close-button {
      background: rgba(255, 0, 0, 0.7);
      color: white;
      text-shadow: none;
      padding: 4px;
      border-radius: 6px;
    }
    
    .close-button:hover {
      background: rgba(255, 0, 0, 0.9);
    }
    
    .notification-default-action {
      border-radius: 12px;
    }
    
    .control-center {
      background: rgba(40, 40, 40, 0.9);
      border: 2px solid rgba(255, 255, 255, 0.1);
    }
  '';
  
  # Autostart with Hyprland
  wayland.windowManager.hyprland.settings.exec-once = [ "swaync" ];
}

{ pkgs, ... }:

{
  xdg.desktopEntries.vesktop = {
    name = "Vesktop (Wayland)";
    genericName = "Vesktop";
    comment = "Discord client with Vencord, using Wayland support";
    exec = "env XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland vesktop --ozone-platform=wayland --UseOzonePlatform";
    icon = "vesktop";
    terminal = false;
    categories = [ "Network" "InstantMessaging" ];
  };

  programs.vesktop.enable = true;

  programs.vesktop.settings = {
    appBadge = false;
    arRPC = true;
    checkUpdates = false;
    customTitleBar = false;
    disableMinSize = true;
    minimizeToTray = true;
    tray = false;
    splashBackground = "#000000";
    splashColor = "#ffffff";
    splashTheming = true;
    staticTitle = true;
    hardwareAcceleration = true;
    discordBranch = "stable";
  };

  programs.vesktop.vencord.themes = { 
    "gruvbox-dark.theme.css" = ../themes/vesktop/gruvbox-dark.theme.css;
  };

  programs.vesktop.vencord.settings = {
    autoUpdate = true;
    autoUpdateNotification = true;
    notifyAboutUpdates = true;
    useQuickCss = true;
    disableMinSize = true;
    enabledThemes = "gruvbox-dark.theme.css";
    plugins = {
      MessageLogger = {
        enabled = true;
        ignoreSelf = true;
      };
      FakeNitro.enabled = true;
      CallTimer.enabled = true;
      CopyUserURLs.enabled = true;
      CopyFileContents.enabled = true;
      FixYoutubeEmbeds.enabled = true;
      FriendsSince.enabled = true;
      Translate.enabled = true;
    };
  };
}

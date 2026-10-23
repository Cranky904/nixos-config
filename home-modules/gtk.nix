{ config, pkgs, ... }:

{
  gtk = {
    enable = true;
    theme = {
      name = "gruvbox-dark";
      package = pkgs.gruvbox-dark-gtk;
    };
    # Preserve GTK 4 theming explicitly across Home Manager default changes.
    gtk4.theme = config.gtk.theme;
    iconTheme = {
      name = "Vimix";
      package = pkgs.vimix-icon-theme;
    };
    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
    };
  };
}

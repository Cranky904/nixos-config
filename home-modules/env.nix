{ pkgs, ... }:

{
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";

    NIXPKGS_ALLOW_UNFREE = "1";

    EDITOR = "nvim";
  };
}

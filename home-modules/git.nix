{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Bálint Fejes";
    userEmail = "crankyartist904@gmail.com";
  };
}

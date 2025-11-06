{ config, pkgs, ... }:

{
  imports =
    [ 
      ./hardware-configuration.nix
    ];


  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/nvme0n1";
  boot.loader.grub.useOSProber = true;

  networking = {
    hostName = "nixos";
    networkmanager.enable = true;
  
    extraHosts = ''
      0.0.0.0 hkrpg-log-upload-os.hoyoverse.com
      0.0.0.0 log-upload-os.hoyoverse.com
      0.0.0.0 sg-public-data-api.hoyoverse.com
        0.0.0.0 overseauspider.yuanshen.com
      0.0.0.0 apm-log-upload-os.hoyoverse.com
      0.0.0.0 zzz-log-upload-os.hoyoverse.com
    '';
  };

  time.timeZone = "Europe/Budapest";

  i18n = {
    defaultLocale = "en_US.UTF-8";

    extraLocaleSettings = {
      LC_ADDRESS = "hu_HU.UTF-8";
      LC_IDENTIFICATION = "hu_HU.UTF-8";
      LC_MEASUREMENT = "hu_HU.UTF-8";
      LC_MONETARY = "hu_HU.UTF-8";
      LC_NAME = "hu_HU.UTF-8";
      LC_NUMERIC = "hu_HU.UTF-8";
      LC_PAPER = "hu_HU.UTF-8";
      LC_TELEPHONE = "hu_HU.UTF-8";
      LC_TIME = "hu_HU.UTF-8";
    };
  };

  services.xserver.enable = true;
  services.xserver.desktopManager.runXdgAutostartIfNone = true;

  services.xserver.xkb = {
    layout = "hu";
    variant = "";
  };

  services.displayManager.ly.enable = true;

  programs.hyprland = {
    enable = true;
    withUWSM = false;
    xwayland.enable = true;
  };

  console.keyMap = "hu";

  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans
    nerd-fonts._0xproto
  ];

  fonts.fontconfig.defaultFonts = {
    serif = [ "Noto Serif CJK JP" ];
    sansSerif = [ "Noto Sans CJK JP" ];
    monospace = [ "Noto Sans Mono CJK JP" ];
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.groups.i2c = {};

  programs.fish.enable = true;

  users.users.cranky = {
    shell = pkgs.fish;
    isNormalUser = true;
    description = "Cranky";
    extraGroups = [ "networkmanager" "wheel" "i2c" "docker" "input" ];
    initialPassword = "asdasdasd";
  };

  boot.kernelModules = ["i2c-dev"];
  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
  '';

  nixpkgs.config.allowUnfree = true;

  networking.firewall.allowedTCPPorts = [ 8096 ];
  networking.firewall.allowedUDPPorts = [ 8096 ];

  environment.systemPackages = with pkgs; [
    docker# Did you read the comment?
    docker-compose
  ];

  services.pcscd.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  services.openssh.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      vulkan-loader
      vulkan-extension-layer
    ]; 
  };



  services.xserver.videoDrivers = [ "nvidia" ];
  
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user="cranky";
  };

  fileSystems."/home/cranky/mounts/sdrive" = {
    device = "/dev/disk/by-uuid/4c0497c0-422a-4391-8791-08e6ada56f82";
    fsType = "ext4";
  };

  services.flatpak.enable = true;

  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  virtualisation.docker.enable = true;

  system.stateVersion = "25.05"; 
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}

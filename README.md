# Cranky's NixOS configuration

The system and home environment use the same `flake.lock`, with two entry points:

- `./rebuild.sh`: update all flake inputs, stage the repository (including the
  updated lockfile), rebuild and activate both NixOS and Home Manager, then
  commit the staged changes and push the current branch to `origin` only after
  a successful rebuild.
- `./home.sh`: build and activate just Home Manager for frequent configuration
  testing, without rebuilding the system or updating inputs.

Both entry points share the same home modules and back up conflicting unmanaged
files with the `.backup` extension. The pinned Home Manager CLI is available from
the system profile so `home.sh` remains usable after a full rebuild.

`rebuild.sh` runs `nix flake update` before rebuilding, so it can pick up newer
packages. `home.sh` uses the versions already pinned in the shared lockfile,
keeping frequent home configuration tests fast. A full `./rebuild.sh` applies
updated user packages and desktop configuration too; a separate `./home.sh` run
is not required. Most applications, including `gh`, are Home Manager packages.

To update the home environment without rebuilding the system, run
`nix flake update` followed by `./home.sh`.

Rebuild commits are named `Rebuild iteration #1`, `Rebuild iteration #2`, etc.
The next number is one above the highest matching commit subject in local Git
history, including other branches and remote-tracking refs. A rebuild without
staged changes skips the commit but still attempts the push, allowing a failed
push to be retried. An input-update failure stops before rebuilding. Rebuild
failures leave files staged without committing or pushing them; push failures
keep the local commit for retrying.

The push uses Git with the existing SSH remote. The `gh` CLI is installed by
Home Manager for other GitHub operations.

Existing account passwords are managed outside this repository. A fresh
installation must provision its user password separately.

The desktop uses Hyprland, Quickshell, Vicinae, Hyprpaper, and SwayNC. Home Manager
owns their session services; Hyprpaper and SwayNC are not also launched through
Hyprland's `exec-once`.

## Hardware

Both graphics cards use NVIDIA's proprietary 580 legacy driver: a GTX 1060 6GB
at `01:00.0` and a GTX 1050 Ti at `04:00.0`. The connected HDMI display is on
the GTX 1060. There is no Intel/AMD GPU in this configuration, so the NixOS
hybrid Intel/AMD–NVIDIA PRIME configuration is not enabled. Hyprland uses
Aquamarine, so the old `WLR_*` environment overrides are not used.

The existing Hyprland software cursor workaround is retained. Any future manual
GPU selection should follow the current Aquamarine documentation, including its
requirements for stable device paths.

## Local development dependency

The `Alt+A` binding launches `reca`, currently installed manually in
`~/.cargo/bin` from the separate `~/Development/RECA` project. Its speech tools
and model are managed here; its development executable is not packaged by this
flake. Home Manager includes that Cargo bin directory in the session PATH.

## References

- [NixOS NVIDIA configuration](https://wiki.nixos.org/wiki/NVIDIA)
- [Hyprland NVIDIA setup](https://wiki.hypr.land/Nvidia/)
- [Hyprland multiple GPUs](https://wiki.hypr.land/configuring/extra/multi-gpu/)
- [Standalone Home Manager with flakes](https://nix-community.github.io/home-manager/nix-flakes/standalone.html)
- [Home Manager's NixOS integration](https://nix-community.github.io/home-manager/nix-flakes/nixos.html)
- [Home Manager file backups](https://nix-community.github.io/home-manager/usage/dotfiles.html)
- [Nixvim extra plugins](https://nix-community.github.io/nixvim/user-guide/faq.html)

The Minecraft syntax plugin is pinned directly because it has no Nixvim module
or nixpkgs package in this lockfile's revisions. Its upstream last changed in
2023, so support for newer Minecraft commands may be incomplete.

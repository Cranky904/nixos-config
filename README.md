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

## Rebuild progress

Run `./rebuild` (or `./rebuild.sh`) for a compact terminal display with blue
Nerd Font spinners, green completion checks, and gray elapsed times. Sudo
authentication happens before updating inputs. SSH passphrase and Git credential
prompts remain interactive when pushing.

Spinner frames update only changed terminal lines in one synchronized write;
completed lines stay still. The display does not erase and redraw the whole
screen on each tick.

Progress follows Nix's structured activity events: source fetching, lockfile
updates, configuration evaluation, dependency downloads, and package builds.
During builds, the current package and its unpack/configure/build/install phase
appear beside the spinner. Activation also shows the GRUB menu, `/etc`, system
and user services, and Home Manager when those steps are reported. Git push
progress separates preparing, compressing, and uploading objects. Cached or
unneeded steps are omitted, and overlapping downloads/builds can have two active
spinners.

Build/download totals are shown when Nix reports them. Each command's exit
status and elapsed time are recorded in the log. After switching, the runner
checks that `/run/current-system` matches the configuration reported by
`nixos-rebuild` before committing or pushing.

Real warnings appear in yellow; repeated identical warnings are shown once.
Compiler/package-build warnings are counted in one yellow row per package,
with their full text in the log, so a driver build cannot flood the display.
The expected dirty Git tree notice stays in the log. Errors turn the active
steps red and show the diagnostic message or the last output lines. Failed
updates/builds still stop before committing or pushing; a failed push preserves
the successful rebuild's local commit.

Full output is saved with private file permissions under
`${XDG_STATE_HOME:-~/.local/state}/nixos-rebuild/`, with the path printed at the
end. Password input is never logged. Logs are kept until you remove them.

- `./rebuild --demo`: preview representative progress without running commands
  or changing the configuration.
- `./rebuild --plain`: use plain text without animation, colors, or special
  glyphs. Redirected output automatically uses this format; `NO_COLOR` disables
  colors in an interactive terminal.
- `python3 -m unittest discover -s tests`: exercise the parser, failure handling,
  interactive prompts, and workflow using fake commands; no system rebuilds.

The runner uses Python's standard library and the tools already installed by
this configuration. `home.sh` remains the standalone Home Manager entry point.

Existing account passwords are managed outside this repository. A fresh
installation must provision its user password separately.

`nix-ld` is enabled for downloaded dynamically linked Linux binaries, using the
NixOS module's default libraries. Additional binary-specific dependencies belong
in `programs.nix-ld.libraries`.

See [the optimization audit](OPTIMIZATIONS.md) for measured disk usage and
suggested maintenance changes.

The desktop uses Hyprland, Quickshell, Vicinae, Hyprpaper, and SwayNC. Home Manager
owns their session services; Hyprpaper and SwayNC are not also launched through
Hyprland's `exec-once`.

## Quickshell compact clock

Phase 1 displays only the local time in 24-hour `HH:mm` format on the main
monitor (`HDMI-A-1`).
The centered white text keeps the previous clock's 12 px regular
0xProto Nerd Font Mono. Its borderless capsule follows the rounded reference:
10 px horizontal and 6 px vertical padding, a radius of half its height, and
8 px clearance from the top and left screen edges. At scale 1 it measures
58 × 31 px; dimensions follow the font metrics.

The frosted surface uses a `#151515` tint at 75% opacity (`#bf151515`) and
[native compositor blur](https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/BackgroundEffect/)
clipped to its rounded shape. It sits on the overlay layer above ordinary
windows, reserves no desktop space, and passes pointer
input through without taking keyboard focus. The old shell toggle bindings
are removed. Expanded mode is reserved for a later phase.

The clock starts hidden and appears after five seconds without input, on a
workspace switch, or when the pointer enters the main monitor's top-left
8 × 8 px corner. Further input dismisses it; corner movement deliberately keeps
it revealed, while a key or click with a stationary pointer dismisses it.
The workspace shortcut has a 150 ms grace period so its own input does not
immediately dismiss the reveal. Leaving the corner hides its reveal too.

Fullscreen on either monitor's active workspace overrides every reveal trigger.
Hyprland fades the whole surface, including its glass, using the existing fade
timing (300 ms). Hidden mode unmaps the window entirely, leaving no text, glass,
or input surface. Disabling Hyprland animations also disables these fades.

`python3 -m unittest discover -s tests -p 'test_quickshell_visibility.py'`
checks the QML visibility controller without changing the desktop session.

## Hardware

The RTX 3060 at `01:00.0` uses NVIDIA's stable driver with open kernel modules,
DRM modesetting, and video-memory preservation during suspend. NixOS supplies
the graphics drivers, including Vulkan, 32-bit support, and VA-API acceleration.
PRIME is not needed for this single-GPU desktop. The old forced GBM backend and
software cursor workaround are removed.

Hyprland keeps the main HDMI display at `1920x1080@100`, position `0x0`, and the
secondary DP display at `1920x1080@60`, position `1920x0`, both at scale 1.
Hyprpaper uses the existing wallpaper as a fallback for all connected displays,
including hotplugged monitors.

`edrive` and `tdrive` mount under `/home/cranky/mounts/` as Btrfs with `rw` and
`nofail`. `edrive` uses the Kingston SSD's stable hardware ID because filesystem
probing does not create its UUID link, although its Btrfs superblocks contain the
expected UUID. `tdrive` uses its filesystem UUID. The NVMe root filesystem and
`sdrive` declarations are unchanged.

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

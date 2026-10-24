# Optimization audit — 2026-10-24

The NVMe filesystem has about 198 GiB used and 25 GiB available (90% full).
Only `programs.nix-ld.enable = true` was changed. No system activation, package
removal, generation expiration, or cache cleanup was performed.

## Highest-value changes to consider

1. **Retire old Nix profiles deliberately.** There are 49 generation links across
   the system, standalone Home Manager, and user package profiles. Their combined
   closures contain **52.1 GiB of NAR contents outside the current system and
   current user/Home Manager profile closures**. This is an upper bound on a
   cleanup opportunity, not a predicted disk saving: store hardlinks reduce
   physical usage and other GC roots can retain the same paths. The standalone
   Home Manager profile still has a generation from August. Review both root and
   user profiles, including standalone Home Manager, before expiring generations.
   Keep recent working rollbacks. Plain GC currently finds only 430 unreachable
   paths, totaling approximately **0.83 GiB in NAR size**.

2. **Review Trash: 4.8 GiB.** Empty it through the file manager after checking
   whether anything needs restoring.

3. **Restrict Vicinae file indexing.** Its file-indexer database occupies about
   **4.7 GiB**. Review which directories are indexed, especially mounted drives,
   backups, game libraries, and generated build directories. Narrow the scope
   before rebuilding the index; deleting the database alone lets it grow back.
   The exact preferences for the installed version need checking in Vicinae's
   settings; this audit does not introduce guessed configuration keys.

4. **Review Flatpak runtimes: 8.0 GiB total installation.** Four NVIDIA 580 driver
   runtime versions are installed, roughly 0.9 GB each as reported by Flatpak,
   alongside several platform versions. Start with `flatpak uninstall --unused`
   and review its proposed removals. The full installation size is not all
   reclaimable; retain runtimes needed by installed apps. If old NVIDIA runtimes
   remain, compare them with the running driver before removing any explicitly.

5. **Bound journal growth: 2.6 GiB on disk.** No explicit journal size cap is
   configured. For this pinned nixpkgs, a possible limit is
   `services.journald.settings.Journal.SystemMaxUse = "512M";`. This reduces log
   history. The agent environment's `journalctl` cannot read all the journal
   formats present, so this figure comes from `du`, not `journalctl --disk-usage`.

6. **Move game data if the NVMe needs more space.** Steam uses **37 GiB** and
   PrismLauncher uses **14 GiB** under `~/.local/share`. `tdrive` has about
   **913 GiB available**. Use the launchers' library/instance migration features
   and preserve saves. `tdrive` is a rotational disk, so this trades load speed
   for NVMe capacity; these directories are not disposable caches.

## Preventing repeated growth

- Store deduplication (`nix.optimise.automatic`) and SSD trimming
  (`services.fstrim.enable`) are already enabled. Adding another optimisation
  mechanism is unlikely to be the first useful change.
- Automatic garbage collection is disabled. Weekly GC without generation
  expiration preserves existing rollbacks:

  ```nix
  nix.gc = {
    automatic = true;
    dates = "weekly";
  };
  ```

  Adding `options = "--delete-older-than 30d";` also retires older generations
  in profiles managed by that invocation. Account for the separate user and
  standalone Home Manager profiles rather than assuming the root timer covers
  all profiles. Home Manager also provides `services.home-manager.autoExpire`.
- `rebuild.sh` updates all flake inputs on every rebuild. Batching updates while
  allowing configuration-only rebuilds against existing pins would reduce
  downloads, version churn, and retained older dependencies. This would change
  the previously requested workflow, so it remains a proposal.
- Docker reports **930 MB of reclaimable images** and **271 MB of build cache**;
  its automatic pruning is disabled. Review unused images first; do not
  automatically prune volumes that may hold persistent application data.
- User caches total about **11 GiB**, including Vicinae above, Codex runtimes
  (1.8 GiB), Chromium (1.1 GiB), and NVIDIA shaders (0.96 GiB). Avoid indiscriminate
  removal of active runtimes or shader caches; rebuilding them costs time.

## Configuration and runtime improvements

- Both Plasma 6/X11 and Hyprland are enabled. If Plasma is no longer used as a
  fallback, disabling it is a potential package/service reduction. Confirm that
  requirement first; simply removing repeated package-list entries generally
  saves no space when they resolve to the same store path.
- Home Manager evaluates its own nixpkgs because `home-manager.useGlobalPkgs`
  is false. Sharing the system package set can reduce evaluation work. That
  requires relocating the home module's `nixpkgs.config.allowUnfree` so the
  standalone entry point still works. This is primarily an evaluation
  improvement, not a guaranteed store-size reduction.
- Quickshell launches shell commands every second for CPU, memory, and thermal
  readings. Consolidating reads and only polling hidden details while their
  popup is open would reduce process launches. CPU and memory readings shown
  on the bar still need updates. PipeWire event-based volume updates would
  also keep the displayed volume in sync with changes made outside Quickshell.
- `~/.rustup/toolchains` occupies **3.0 GiB**, while Rust tools are also declared
  through Nix. Check whether any projects still require those toolchains before
  removing them. Project development shells could reduce the globally retained
  language tooling, at the cost of changing the development workflow.
- The manually listed T3 shared libraries in `home.packages` do not by
  themselves populate the library search path for downloaded binaries. If a
  binary reports missing libraries after enabling nix-ld, add its actual
  dependencies to `programs.nix-ld.libraries`. The default module already supplies
  common C/C++, compression, TLS, and system libraries.

## Validation and references

The complete NixOS system derivation evaluated successfully, and the NixOS,
integrated Home Manager, and standalone Home Manager assertions passed with
import-from-derivation disabled. The evaluated nix-ld option is true and its
loader resolves to the pinned nix-ld package. No flake inputs were updated.

- [Nix garbage collection and profile retention](https://nixos.org/manual/nixos/stable/#sec-nix-gc)
- [Read-only GC inspection](https://nix.dev/manual/nix/2.34/command-ref/nix-store/gc.html)
- [Flatpak unused runtime cleanup](https://docs.flatpak.org/en/latest/using-flatpak.html#troubleshooting)
- [nix-ld usage and library configuration](https://github.com/nix-community/nix-ld)

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

The compact clock displays local time in 24-hour `HH:mm` format on the main
monitor (`HDMI-A-1`).
The centered white text keeps the previous clock's 12 px regular
0xProto Nerd Font Mono. Its capsule follows the rounded reference:
10 px horizontal and 6 px vertical padding, a radius of half its height, and
8 px clearance from the top and left screen edges. At scale 1 it measures
58 × 31 px; dimensions follow the font metrics.

The colon blinks with 500 ms on/off phases. At a minute change, unchanged digits
briefly dim to `#888888`, while each changing white digit rolls independently:
the old digit moves 6 px up and fades, and the new one enters from 6 px below
over 280 ms. All digits return to white after the roll, with a short color fade.
The clock keeps its size throughout. Hidden clocks stop blinking and update
without replaying rolls on reveal. Disabling Hyprland animations in the
configuration also keeps the colon steady and makes digit updates immediate.

Switching workspaces reveals the clock for a protected 2.5 seconds and expands
it to show the current workspace's Nerd Font icon on the right. Key releases
and pointer movement do not dismiss the peek. Repeated switches update the
icon and restart the timer. If a workspace icon is already visible, changing
it rolls the old icon 6 px upward as it fades, while the new icon enters from
6 px below, using the clock's 280 ms ease-out motion. The first reveal only
expands the capsule; hidden updates and reduced motion change icons immediately.
The original icon map is restored in the
`workspaceBadgeQml` section of `home-modules/quickshell.nix`; unknown workspaces
use a dot.

The time stays in place while the capsule expands from 58 to 84 px wide,
with a 10 px gap before the 16 px icon and a fixed 31 px height. Expansion uses
300 ms ease-out motion and collapse uses 220 ms. Glass, hover bounds, and the
fully closed inset outline follow the animated width. After the workspace
timer expires, the badge collapses before the clock hides, or leaves the plain
clock visible if another reveal trigger is active. Icon width and spacing
determine the expansion size, so larger future additions remain contained.

Hovering the clock draws a fully closed white inset outline. Its upper and lower
strokes meet on both sides. The 1.5 px strokes sit 3 px inside the glass, leaving
a thin dark rim outside and space around the text. Rounded caps follow
the moving tips throughout the left-to-right draw and right-to-left retraction.
Both use ease-out motion: 300 ms in, 220 ms out.

Inside the expanded menu, the collapsed clock button instead draws that outline
around small white sun/moon Nerd Font icons. Their approximate sky positions
use Budapest's coordinates (shared with weather) and the current instant, using
[SunCalc's solar/lunar formulas](https://github.com/mourner/suncalc/tree/v1.9.0).
Above-horizon bodies follow the upper half, below-horizon bodies the lower half;
rising is left and setting is right. The moon follows its own orbit. UTC-based
calculations handle Europe/Budapest's daylight-saving changes without a fixed
clock offset. Icons appear as the drawing reaches them, and the line stops and
resumes with clear space around each glyph. Near conjunction, the glyphs spread
slightly along the rim to avoid overlapping. This treatment is limited to the
clock button in the expanded module stack; opening the calendar removes it.

The clock separately lingers for 2.5 seconds after hover ends, even though the
outline has already retracted; it then fades away unless another reveal trigger
is active. Re-entry cancels the pending hide and reverses the outline smoothly.
`HoverOutline.qml` exposes inset, thickness, radius, and animation timings;
its vector paths and the hover bounds follow the container size for future
additions. Disabled animations settle the outline instantly; the clock's linger
timer remains independent.

The frosted surface uses a `#151515` tint at 75% opacity (`#bf151515`) and
[native compositor blur](https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/BackgroundEffect/)
clipped to its rounded shape. It sits on the overlay layer above ordinary
windows and reserves no desktop space. Only the clock accepts pointer input
in compact mode, so it can be clicked to open the calendar. The surrounding
desktop receives input normally; the compact clock takes no keyboard focus.

The clock starts hidden and appears after five seconds without input, on a
workspace switch, or when the pointer enters the main monitor's top-left
80 × 48 px area, covering the corner and the clock's normal position. Hovering
there keeps it revealed, including while the mouse pushes against the screen
edge. Outside that area, further input dismisses it.
Workspace switches and hover use independent timers with the same 2.5-second
duration. Leaving the corner clears that reveal; a clock
that was hovered keeps its separate linger timer.

Fullscreen on either monitor's active workspace overrides compact reveal triggers.
Hyprland fades the whole surface, including its glass, using the existing fade
timing (300 ms). Hidden mode unmaps the window entirely, leaving no text, glass,
or input surface. Disabling Hyprland animations also disables these fades.

`python3 -m unittest discover -s tests -p 'test_quickshell_visibility.py'`
checks visibility, workspace icons and protected linger, expansion, outline
scaling and reversal, blinking, digit rollovers, expanded-module selection,
calendar date calculations, weather parsing, sky positions and icon gaps,
media spectrum frames, and reduced motion without
changing the desktop session or making weather requests.

## Quickshell expanded modules

Press either Windows key to open the menu on `HDMI-A-1`, with the active-window
panel at the top and Clock, Media and Usage capsules in a horizontal row below.
Click the clock to expand it into a calendar with `HH:mm:ss`
time and Budapest weather alongside it. Clicking the compact clock directly
also opens the stack with the calendar selected. Windows closes the menu;
clicking beyond 40% of the main screen's width also closes it and consumes
that click. Clicking blank menu background collapses the selected widget and
keeps the main menu open; widget contents retain their own input handling.
Once the closing
animation finishes, the compact clock remains visible for two seconds,
independently of idle and hover. Fullscreen still suppresses compact reveals.

The active-window panel slides in first from offscreen left, followed by Clock,
Media and Usage with overlapping 65 ms delays and 360 ms OutCubic motion.
Opening directly through the desktop clock skips its horizontal entrance as it
moves down and morphs into the calendar. The header and other capsules still
enter in sequence. Three bottom-left 46 px frosted circles
continue the stagger horizontally: power, restart, rebuild, using 24 px white
Nerd Font icons and the shared inset hover outline. Closing cancels pending
entrances; disabling animations removes delays and translation.

Clicking a capsule moves that same surface out of the row and grows it into a
panel below, easing left into alignment with the header. It disappears from the
row because it is now the expanded panel; the remaining capsules slide together
to close its slot. Collapsing reverses the movement, shrinks the panel and returns
the original capsule to its slot. Opening uses 360 ms OutCubic, closing 280 ms
InCubic. The compact glyph fades early and panel content appears after the shape
has begun expanding. The shared ModuleDeck finishes retracting an outgoing panel
before opening the latest requested module, so their contents never overlap;
reopening the same panel reverses from its current frame. Glass samples, rounded
backdrop cutouts, and input follow the actual capsule through its parent change.

Power and restart show “Are you sure?” in a frosted confirmation panel, with
cancel/back and confirm icons. Only confirmation dispatches `systemctl poweroff`
or `systemctl reboot`; clicking away or closing the menu cancels the request.
Rebuild opens Kitty in `~/nixos-config` and runs `~/nixos-config/./rebuild.sh`.
Command requests are separate from process dispatch so tests can inspect them
without shutting down, restarting, or rebuilding the machine.

The 600 × 220 px active-window panel stays visible throughout the open menu,
independently of the selected widget, and disappears when the menu closes.
Its live uniform blur has a horizontal tint gradient: the subdued icon-derived
color at the left fades into the normal `#bf151515` module tint at the right.
It shows the icon, window title, four recent-window buttons, elapsed window
lifetime, application volume, and three read-only CPU/RAM/GPU wave meters.
The meters use the buttons' `#bf222222` frosted glass without outlines, with
white fill below each animated wave; zero and unavailable readings stay empty.
Recent buttons retain their outline animation while their icons tilt 30°
clockwise and enlarge on hover. Closing targets the displayed window; recent
buttons focus their window. Only these buttons use a hand cursor; the volume
slider uses a horizontal resize cursor, and the meters remain read-only.

Window lifetimes are tracked from first observation, including while the menu
is closed, and cached privately for the current compositor session. Windows
already open before tracking begins start at first observation; process uptime
is not substituted for their window age. CPU is the application's process-tree
share of total CPU capacity; RAM is proportional memory (RSS fallback when
restricted), shown as a share of system RAM. GPU uses NVIDIA per-process SM
utilization. Shared browser processes and audio services can cover multiple
windows of the same application. Missing measurements show an em dash.
Application volume adjusts its matched PipeWire playback streams, preserving
mute and other applications' volumes. A window without a playback stream has
a disabled slider. On an empty workspace the panel uses the Nix logo, overall
desktop CPU/RAM/GPU readings and system volume. Process telemetry runs only
while the menu is open; lifetime tracking remains event driven when closed.

Chromium windows use their active tab's favicon for the large icon, recent-window
icon and glass tint. A bundled Manifest V3 extension reads the active page's icon
links and web app manifest icons, then fetches the original artwork, preferring
SVGs over raster images.
Self-contained SVGs remain vector files; raster icons retain their original
resolution up to 512px. The panel renders vectors at its physical display size,
including HiDPI screens. Chromium's cached PNG is the fallback when originals
are unavailable or unsupported. Sites that only provide tiny raster icons will
still have limited detail.

The extension uses `tabs`, `favicon`, `nativeMessaging`, `scripting` and HTTP/HTTPS
host access to read icon links in active tabs and fetch their image files. It
does not install persistent content scripts and excludes incognito windows.
The local host accepts bounded PNGs and static SVGs without scripts or external
resources. Only current active-tab titles,
window geometry and images are kept in a private runtime directory, removed
when the host exits. No tab URLs or browsing history are written there.

Quickshell matches the browser process, window title and (when needed) geometry,
so separate Chromium windows keep their own icons. Missing icons, internal
browser pages, ambiguous matches and a stopped bridge fall back to the normal
application icon. Updates are read on the window panel's existing one-second
telemetry cadence. Home Manager installs the extension, its restricted native
host manifest and the Chromium launch argument. After `./home.sh`, fully restart
Chromium once to load it; no manual extension installation is needed. When
changing the extension in future, bump its manifest version. The worker filename
also contains a hash of its source: Chromium can retain old unpacked worker code
across a Home Manager symlink update and browser restart, so each source change
must get a new worker URL. The bridge uses Chromium's
[Favicon API](https://developer.chrome.com/docs/extensions/how-to/ui/favicons),
[script injection](https://developer.chrome.com/docs/extensions/reference/api/scripting),
[extension image fetching](https://developer.chrome.com/docs/extensions/develop/concepts/network-requests)
and [native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).

The calendar uses a Monday-first, six-week grid, highlights today, supports
previous/next months and selecting a day, and returns to today through its
date footer. Current weather comes from
[Open-Meteo](https://open-meteo.com/en/docs) for Budapest (47.4979, 19.0402), in
Celsius and km/h. It refreshes when the calendar opens if its cache is older
than ten minutes, and every ten minutes while shown. Loading, retry, and stale
states are explicit; unavailable weather never displays a fabricated value.

Media and Audio share one 58 × 31 px compact control below the clock/calendar,
with a centered white 18 px Nerd Font speaker icon for muted, low, medium, or
high output volume. Scrolling up/down changes the default system output by
five percentage points per notch, including accumulated high-resolution wheel
steps. Volume stays within 0–100%; scrolling preserves mute. External volume,
mute, and default-output changes are followed through native PipeWire bindings.

Hovering or keyboard-focusing the media control reveals 16 white dots/bars
around its complete capsule, inset 3 px. Both halves draw left-to-right in
300 ms and retract right-to-left in 220 ms with OutCubic easing, matching the
clock. Round-capped bars grow as the drawing reaches them, without opacity
fading or a continuous hover line. Each bar represents a
frequency band from the same live desktop-audio spectrum, with bass, mids,
and treble updating together. [CAVA](https://github.com/karlstav/cava) performs
the FFT at 30 frames per second, explicitly capturing the current output's
PipeWire monitor. Volume controls the speaker icon and scrolling behavior.

Bars grow equally inward and outward from the rail, up to 10 px total length,
with round caps and 8 px of canvas overdraw to prevent clipping outside the
glass. The inset keeps their inward ends clear of the speaker icon. Leaving
hover retracts them and releases capture once the drawing is gone. The open
media widget keeps the same FFT stream for its volume slider. Monitoring stops
when neither view needs it, muted, at zero volume, or with reduced motion.
Silence leaves still dots. Default-output changes restart the output monitor.

The expanded media widget is 600 × 420 px, scaling with the existing module
layout and keeping its uniform frosted glass. Left: 252 × 164 px artwork,
a two-line title overlapping its lower edge, 26 px previous/next icons and a
30 px play/pause icon, a seekable playback progress bar with elapsed/duration
timestamps, then a waveform system-volume slider with a percentage. Expanded
buttons, track rows and playlist editors crop the live uniform backdrop blur
independently, with translucent #151515/dark-gray tints rather than flat gray
fills. Icons are centered without style padding, and hover tooltips are disabled.
The slider uses white bars before its handle and gray bars after it. Playback
controls follow the current desktop MPRIS player or the shell's local playlist
player. Clicking a local track pauses the external player before starting it.
Local music and downloads continue when the expanded menu closes.

Right: icon-only Download, Choose and Modify actions. Download expands across
the action row into a YouTube playlist URL field; Enter starts the job and an
outside click dismisses the field. Choose and Modify expand across
the actions and playlist area, using the same 360 ms OutCubic opening and
280 ms InCubic return as the modules. Both close when clicking outside their
box, with no corner close button. Track rows are 68 px tall with 64 × 46 px
artwork, show title and artist horizontally, use the existing inset hover
outline, and play when clicked. Each playlist has a separate scrollbar in a
14 px gutter beside its rows, hidden when scrolling is unnecessary. Compact
buttons and actionable controls use pointing-hand cursors; blank expanded
space uses the normal arrow, sliders use horizontal resize cursors, and the
playlist scrollbar uses a vertical resize cursor.
During downloads, each row shows its own percentage/progress line or failure.
Stable row identities keep progress updates from resetting scrolling/hover.

Audio-only playlists are saved under `~/Music/Playlists/<title> [<playlist-id>]/`.
[yt-dlp](https://github.com/yt-dlp/yt-dlp) downloads and extracts Opus with FFmpeg,
retaining thumbnails and metadata; Node supplies its YouTube JavaScript runtime.
Choose lists these folders and existing folders containing local audio files.
Modify offers update, exclusion of the current track, and recoverable deletion
through the desktop Trash; clicking its track rows toggles exclusions too.
Hovering or keyboard-focusing an editable row blurs its thumbnail and text
behind a centered “Exclude from playing” action (or the inclusion action for an
excluded track), replacing the separate icon on the right.
Excluded tracks are dimmed/struck through, skipped by playback, and preserved
when updating the playlist. Editing exclusions while paused keeps playback
paused. Updates retain downloaded tracks and fetch missing/new entries.
Cancellation preserves partial files for a later retry/update.

The Python library helper and headless [mpv](https://mpv.io/manual/stable/#json-ipc)
player start on demand. The helper owns its child processes and stops them when
Quickshell exits; it never invokes a shell for URLs. Playlist paths and symlinks
are checked before playback, writes or Trash operations. Tests use temporary
libraries and silent audio output. `python3 -m unittest discover -s tests -p 'test_quickshell*.py'` covers the QML controls and playlist backend.

Usage replaces System. Its compact hover keeps the curved ends white and
uses a yellow (`#ead178`) CPU segment on the top straight edge and a green
(`#9acb92`) RAM segment on the bottom. The colored lengths track 0–100%
usage along the straight edges, with 3 px gaps separating their rounded ends
from the white portions. They draw left-to-right with the shared
300/220 ms hover animation, and ease between samples over 280 ms.

The 600 × 420 px Usage panel follows the media widget's two-column frosted
layout. CPU total, package temperature and per-core percentages sit left;
RAM used/total/percentage, GPU utilization, VRAM used/total, and download/upload
rates sit right. Core readouts retain their identity between samples, with an
external scrollbar if needed. All changing numbers reuse the clock's 280 ms
digit roll, temporarily dim unchanged digits, and settle back to white.
The clock's blink is disabled for numeric readouts. There are no graphs.

The read-only Python collector runs only while the expanded menu is mounted,
at one-second intervals after a short initial baseline. CPU and core rates use
`/proc/stat` deltas (without double-counting guest time); RAM uses `MemAvailable`
to account for reclaimable cache. CPU package temperature comes from CPU hwmon
sensors. Physical active network interfaces provide byte-counter deltas over
actual elapsed time, excluding loopback/VPN/bridge duplication; units adapt
from B/s through GiB/s. NVIDIA GPU utilization and VRAM come from the active
driver's `nvidia-smi`, queried while Usage is expanded or the window panel is
showing desktop statistics. Missing or warming
readings show an em dash rather than fabricated zeroes. Closing stops the
collector. Tests use isolated proc/sys fixtures plus native read-only checks.

Modules open over 360 ms with OutCubic easing and close over 280 ms with
InCubic easing. The calendar is 600 × 310 px with 24 px corners, scaling down
to fit within the left 40% of smaller screens. The existing `#bf151515` glass
follows each module's animated shape. No desktop space is
reserved. Calendar seconds and weather polling run only for the open calendar;
the window-lifetime clock ticks only while the main menu is open.

The backdrop uses live compositor exports of visible application windows,
composited over the configured wallpaper in their screen positions and stacking
order. Video and changing window contents update while the menu stays open;
workspace switches replace the visible sources immediately. Capturing individual
application surfaces excludes Quickshell itself, preventing recursive blur.
Only visible windows near the faded area are streamed. Hidden windows release
their capture sources; all streams stop when the expanded menu closes.

The scene is blurred at full screen size before any cropping or fading.
Modules sample this uniform blur at their actual positions, clipped to their
rounded shape beneath the unchanged glass tint. The wide backdrop separately
fades to zero at 50% of the display width; the menu dismissal boundary remains
at 40%. Its cutouts follow modules, footer buttons and the confirmation panel. Circular
cutouts match the module corners, with blur extending 1 px beneath their rims
to prevent sharp background pixels leaking through antialiasing seams. Its fade
therefore cannot change the blur inside a module, and there is no rectangular
spill when a module expands. Compact mode retains native compositor blur.
No snapshots or recordings are saved. Closing fades away the backdrop.
Disabling Hyprland animations makes
module and backdrop transitions immediate. Notifications and further compact
hide refinements remain for a later phase.

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

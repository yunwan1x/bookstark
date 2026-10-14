# Retro Player HTML article

Published admin article: blog ID `229`, share
`https://books.vs2010wy.top/shares/share-1791881159144926372`.

Single-page BookStark HTML article using Nostalgist.js 0.23.0 and fflate 0.8.2.
Public runtime resources live in built-in WebDAV under `retro-player/v1/`, served
at `/dav-public/admin/retro-player/v1/`. The article loads no emulator until Start.
Core ZIPs are pinned to `arianrhodsandlot/retroarch-emscripten-build@v1.22.2-1`.

Supported core selections: fceumm (NES), gambatte (GB/GBC), mgba (GBA), snes9x
(SNES), genesis_plus_gx (MD), pcsx_rearmed (PS1), mame2003_plus and fbneo (arcade).
Core ZIPs are fetched on demand and cached via Cache Storage when available.
All eight archives have been checked with `WebAssembly.validate`.

Games are selected from a read-only WebDAV browser or imported locally; BIOS
can be selected locally. Nothing is uploaded. Explicit `fileName` and
`fileContent` preserve filenames, which arcade sets and CUE files require.
PS1 CUE files are sorted before BIN tracks and checked for missing references.
Game state export/import is local, requires the same core and ROM, and depends
on the core/game supporting save states. No automatic save persistence is implied.

The UI supports Chinese/English, keyboard, gamepads and pointer-based touch
buttons with pointer capture and release on blur. Emulator canvas must retain
the `canvas` ID used by Nostalgist/RetroArch. Startup has cancellation, a timeout,
and user-facing resource/content errors.

The player fills the article viewport, including before launch. Setup is a
translucent card inside the screen; it disappears during gameplay. The overlay
menu contains pause, fullscreen, states, controls, language, help and stopping.
Opening the menu pauses a running game; closing resumes it only if the menu
paused it (not after manual pause or hiding the page). Desktop touch controls
default off; coarse-pointer devices default on. Touch controls overlay the screen
in both orientations. Fullscreen targets the entire player, with an in-frame fallback.
The dark pixel-style menu is a 32px muted button (40px touch hit area). It dims
after 2.5 idle seconds without becoming inaccessible. The right-side panel uses
grouped input rows and P1–P4 tabs. The persistent top-left player HUD is removed.

Fit to window recalculates the render size from the stage, capped at 1920px per
edge without changing its aspect ratio. ResizeObserver also handles window,
orientation and fullscreen changes. RetroArch 1.22.2 is configured with
`aspect_ratio_index=22` (core-provided ratio), `video_force_aspect=true`, integer
scaling off and overscan crop off. CSS does not crop or stretch the game. The
old fixed 640x480 initialization is removed. Black bars are expected. Layout QA
covers desktop, 390x844 portrait, 844x390 landscape, fullscreen and English.

Robby Roto, downloaded from https://www.mamedev.org/roms/robby/, is used only for
local non-commercial QA. MAME's site restricts redistribution, so neither it nor
Gridlee is included in the public WebDAV resources or repository. The article
links to the original Robby Roto download page. Select MAME 2003 Plus to test it.

Robby Roto has been exercised with actual rendered game frames, on-screen coin
and start buttons, pause/resume, state export/import, and a 390px mobile layout.
For headless Chromium QA use its default graphics backend with
`--enable-unsafe-swiftshader`; explicitly forcing `--use-gl=angle` together with
`--use-angle=swiftshader` produced black captures on the test host.
Other cores have binary validation, not a full compatibility test of every game.

## WebDAV game library

Public games uses `/dav-public/admin/retro-player/library/games.json`, a manifest
of game ZIPs, their core, and required BIOS/parent ZIP filenames. This public
source sends no credentials. Download stores the game and all listed dependencies
in one local record; Start honors its specified core instead of the user's generic
arcade default. Public games is the initial source when the browser has no local
games. The external WebDAV configuration remains available in Settings.

User-supplied Metal Slug archives and Neo Geo BIOS are hosted in this WebDAV
folder, not in Git. `cheats.zip` is stored there as a separate resource; it is not
a ROM and these legacy DAT files are not automatically enabled as cheats.
These 16 games select FBNeo: the supplied archive names are incompatible with
MAME 2003 Plus. The supplied first Metal Slug game and Neo Geo BIOS were tested
with a real headless browser and rendered successfully; the other games have
not each been tested individually.

Settings accepts an HTTPS WebDAV folder URL, username and password. URL,
username and default arcade core are stored in localStorage; the password stays
in this page's memory and must be entered again after reload. Use BookStark's
dedicated WebDAV password, not the normal login password. External servers must
allow CORS for PROPFIND/GET, Authorization, Content-Type and Depth. Redirects
are rejected; configure the final directory URL. Requests omit browser cookies.
Only PROPFIND and GET are sent. Directory hrefs outside the configured origin
or root are rejected; all names are rendered as text.

Select a game → Download locally → Start. Browser OPFS stores game files and
IndexedDB stores metadata; browsers without OPFS use IndexedDB blobs. Local
copies survive refresh but can be evicted by browser storage policies. The local
library works without reconnecting WebDAV. Deleting a local copy never deletes
the server file. Runtime/core downloads still require network on first use.

Core detection uses NES/GB/GBC/GBA/SFC/SMC/MD/GEN/SMD/CHD/PBP/CUE extensions.
ZIP is treated as arcade (default MAME 2003 Plus, configurable as FBNeo).
Console ZIPs must be extracted first. CUE downloads include same-directory BIN
references automatically; nested references are rejected. Parent arcade ZIPs
and BIOS can be supplied through the additional-files input. Multi-disc M3U
libraries and recursive folder indexing are not implemented. Downloads have a
512 MiB per-game cap, cancellation and a five-minute timeout. Metadata is only
committed after files have been stored successfully. Remote changes do not
silently replace a local copy; delete that local copy and download again.

Offline browser regressions:
`webdav-library.test.cjs` covers auth header, credential non-persistence,
out-of-scope href rejection, OPFS, CUE dependencies, cached reload/start,
local-only deletion, mobile layout, English and failure messages.

## Controller mapping

Menu → Controllers configures P1–P4, before or during a game. Click
a keyboard/gamepad binding then press an input. Escape cancels; Backspace/Delete
clears. Duplicate explicit bindings are cleared from their previous action.
Changes apply immediately and persist under `bookstark-retro-controls-v2` in
localStorage, per core, player and physical-controller ID/mapping. Existing v1
P1 key/pad profiles are imported when a core is first used. Restore defaults
resets the current player's keyboard and selected controller mappings. Storage failure
is shown and leaves settings usable for the session. ROMs/states are unaffected.

P1 keyboard defaults: arrows, B/A=Z/X, Y/X=A/S, L/R=Q/W, L2/R2=E/R,
L3/R3=D/F, Start=Enter, Select/Coin=right Shift. Physical controllers are selected
from the browser Gamepad API; connect via USB/Bluetooth and press a button to
make the device visible. Standard pads receive a default RetroPad mapping;
non-standard pads require manual binding. Stick directions can be bound as
digital actions (not analog PS1 sticks); deadzone/hysteresis prevents jitter.
P2–P4 start with unbound keyboards; a duplicate key is unbound from its prior
action across all players. Pads can be automatic, explicitly selected, or off.
A physical pad only controls one player. Identical models are distinguished by
browser slot; if the OS changes slots, reselect the device. Automatic assignment
preserves connected players when another controller disconnects. The touch pad
can target P1–P4 using the menu selector or its P badge.

Four input ports do not make a two-player game four-player. Arcade ROM revisions
and core support determine the limit. Console multitaps are not automatically
enabled; rumble, analog-stick output and pad-driven menu navigation are not
implemented. A gamepad may require embedding/HTTPS permissions.

All sources use one player-aware pressDown/pressUp router; 64 distinct supported
internal key codes cover four players. F13–F18 are deliberately excluded because
the pinned core normalizes them to unbound. Frontend hotkeys require an unused
modifier so internal key codes do not accidentally trigger shortcuts.
RetroArch's native joypad bindings
and auto-configuration are disabled to prevent duplicate/default mappings (the
web build otherwise falls back to rwebpad even for a null driver). Keyboard events are
captured before core listeners. Recording/settings do not send inputs to the
game. Input holds are merged across keyboard, pad and touch, and released on
pause, blur, disconnect, rebinding and stopping.

Offline regression tests (no ROM or network required):
`PLAYWRIGHT_MODULE=/path/to/playwright CHROMIUM_PATH=/path/to/chrome node integrations/retro-player/controller-settings.test.cjs`.
These inject a fake emulator and Gamepad API for four simultaneous players,
identical pads, exclusive device assignment, persistence, cross-player key
conflicts, platform isolation, axes, disconnects, input-source overlap, touch P4,
capture isolation, fullscreen, resize, reset, English and mobile layout. A real
MAME core is also checked for all 64 internal bindings and render resizing.
Physical hardware testing
is still needed for each user's controller/browser combination.

Deploy article content and WebDAV resources through BookStark APIs. This content
deployment needs no application rebuild or service restart. Preserve unrelated
working-tree changes; never commit credentials, ROMs, BIOS, or downloaded binaries.

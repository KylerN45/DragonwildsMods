# Dragonwilds Mods

This repository contains mods for RuneScape: Dragonwilds.

Each mod is in the `mods` directory.

## Chest Item Placeholder

Chest Item Placeholder keeps a configured amount of each item in a player-built chest.

Version 1.0.0 supports RuneScape: Dragonwilds 1.0.
It uses the current server-authoritative inventory transfer functions.
It does not remove an item from the player or create a replacement item after a transfer.

Build and test it with these commands:

```powershell
.\scripts\Test-ChestItemPlaceholder.ps1
.\scripts\Build-ChestItemPlaceholder.ps1
```

The release package is written to the `dist` directory.
See `mods\ChestItemPlaceholder\instructions.txt` for installation, use, and configuration information.

## Expanded Quick Access

Expanded Quick Access adds inventory pages to the quick-access radial menu.

The first page is the standard eight-slot quick-access bar. The next three pages contain the 24 main-inventory slots. The mod does not move items between slots.

## Controls

1. Hold the standard quick-access radial button.
2. Press the left trigger or the right trigger to change the page.
3. Select an item with the standard radial control.

You can also use `Q` and `E` to change the page while the radial menu is open.

The page order is:

1. Quick access
2. Inventory row 1
3. Inventory row 2
4. Inventory row 3

Page changes wrap at each end.

## Requirements

- RuneScape: Dragonwilds for Windows
- UE4SS 3.0.1 Beta 0, build `f6d5f942`
- The Microsoft Visual C++ Redistributable for Visual Studio 2015-2022

## Installation

1. Build the package with `scripts\Build.ps1`, or use a release package.
2. Copy the `ExpandedQuickAccess` folder to the UE4SS `Mods` folder.
3. Restart the game.

The installed structure must be:

```text
ue4ss\Mods\ExpandedQuickAccess\
├── enabled.txt
├── config.txt
├── Scripts\
│   └── main.lua
└── dlls\
    └── main.dll
```

For the standard Steam installation used during development, the destination is:

```text
F:\SteamLibrary\steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64\ue4ss\Mods\ExpandedQuickAccess
```

## Configuration

Edit `config.txt` before you start the game.

- `PollMilliseconds` sets the input polling interval.
- `PageChangeCooldownMilliseconds` sets the minimum time between page changes.
- `TriggerThreshold` sets the analog trigger activation point.
- `LeftKeyboardKey` and `RightKeyboardKey` set the keyboard page controls.
- `ShowPageLabel` shows the page name in the radial item-name field after a page change.
- `DebugLogging` adds diagnostic messages to `UE4SS.log`.

Set a keyboard key to `none` to disable it.

## Uninstallation

1. Close the game.
2. Delete the installed `ExpandedQuickAccess` folder.

The mod does not change save data. It changes only live UI state and routes item use through the game's inventory API.

## Technical design

The Lua component changes the eight visible radial slices. It writes the inventory index and inventory type to each slice payload.

The native component changes one direct game call in the quick-access radial selection function. It reads the selected slice payload. It then calls the standard inventory API with that payload. The component restores the original call when UE4SS unloads the mod.

The native component uses unique code signatures. It does not apply the change if the signatures do not match the installed game build.

The native component writes its status to `ExpandedQuickAccess.log` in the installed mod folder. Check this file if page selection stays on the quick-access item.

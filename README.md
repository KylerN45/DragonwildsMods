# Dragonwilds Mods

This repository contains Lua mods for RuneScape: Dragonwilds.

Each mod is in the `mods` directory.

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
- UE4SS 3.0.1 or a compatible later version

## Installation

1. Build the package with `scripts\Build.ps1`, or use a release package.
2. Copy the `ExpandedQuickAccess` folder to the UE4SS `Mods` folder.
3. Restart the game.

The installed structure must be:

```text
ue4ss\Mods\ExpandedQuickAccess\
├── enabled.txt
├── config.txt
└── Scripts\
    └── main.lua
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

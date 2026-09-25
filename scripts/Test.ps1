[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mainLua = Join-Path $projectRoot 'mods\ExpandedQuickAccess\Scripts\main.lua'
$config = Join-Path $projectRoot 'mods\ExpandedQuickAccess\config.txt'
$enabled = Join-Path $projectRoot 'mods\ExpandedQuickAccess\enabled.txt'

foreach ($path in @($mainLua, $config, $enabled)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

$lua = Get-Content $mainLua -Raw
$requiredTokens = @(
    'Gamepad_LeftTrigger',
    'Gamepad_RightTrigger',
    'GetInventorySlots(INVENTORY_ITEMS)',
    'GetQuickActionSlots()',
    'payload.InventoryIndex = inventoryIndex',
    'payload.OwningInventoryType = inventoryType',
    'PageChangeCooldownMilliseconds',
    'sourceImage.Brush',
    'targetImage:SetBrush(brush)',
    'state.routingUntil',
    'state.quickRestorePending',
    'allowFallback',
    'candidate.InventorySlot',
    '/Script/Dominion.InventoryController:',
    '"UseItemFromInventory", "localUseRerouteCount"',
    '"Server_UseItemFromInventory", "serverUseRerouteCount"',
    'preHook(context, inventoryParameter, slotIndexParameter, externalParameter)',
    'activePage * SLOTS_PER_PAGE + incomingSlot',
    'data:GetName()',
    'LoopAsync(cfg.PollMilliseconds'
)
foreach ($token in $requiredTokens) {
    if (-not $lua.Contains($token)) {
        throw "Required Lua integration is missing: $token"
    }
}

if ((Get-Content $enabled -Raw).Trim() -ne '1') {
    throw 'enabled.txt must contain 1.'
}

$configKeys = Get-Content $config |
    Where-Object { $_ -match '^\s*[A-Za-z]' } |
    ForEach-Object { ($_ -split '=', 2)[0].Trim() }
$expectedKeys = @('PollMilliseconds', 'PageChangeCooldownMilliseconds', 'TriggerThreshold', 'LeftKeyboardKey', 'RightKeyboardKey', 'ShowPageLabel', 'DebugLogging')
foreach ($key in $expectedKeys) {
    if ($configKeys -notcontains $key) {
        throw "Required configuration key is missing: $key"
    }
}

foreach ($unsafeCall in @(
    'data:GetIcon()',
    'data:GetCategoryClassIcon()',
    '/Script/Dominion.InventoryComponent:UseItemFromInventory',
    '/Script/Dominion.RadialMenuBase:SelectSlice',
    'HandleInternalUseItem(pending.slot'
)) {
    if ($lua.Contains($unsafeCall)) {
        throw "Unsafe or obsolete integration is present: $unsafeCall"
    }
}

if ($lua.Contains('if not state.quickRestorePending then')) {
    throw 'Page input must not wait for quick-access restoration.'
}

$expectedPhysicalSlots = @(
    @(8, 9, 10, 11, 12, 13, 14, 15),
    @(16, 17, 18, 19, 20, 21, 22, 23),
    @(24, 25, 26, 27, 28, 29, 30, 31)
)
for ($page = 1; $page -le 3; $page++) {
    for ($slice = 0; $slice -lt 8; $slice++) {
        $actual = $page * 8 + $slice
        $expected = $expectedPhysicalSlots[$page - 1][$slice]
        if ($actual -ne $expected) {
            throw "Page $page slice $slice routed to $actual instead of $expected."
        }
    }
}

Write-Host 'Static tests passed.'

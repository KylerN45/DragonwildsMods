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
    'HandleInternalUseItem',
    'payload.InventoryIndex = inventoryIndex',
    'payload.OwningInventoryType = inventoryType',
    'PageChangeCooldownMilliseconds',
    'sourceImage.Brush',
    'targetImage:SetBrush(brush)',
    'local incomingType = parameterValue(slotTypeParameter)',
    'state.routingUntil',
    'state.quickRestorePending',
    'allowFallback',
    'candidate.InventorySlot',
    '/Script/Dominion.InventoryComponent:UseItemFromInventory',
    '/Script/Dominion.InventoryComponent:Server_UseItemFromInventory',
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
    '/Script/Dominion.RadialMenuBase:SelectSlice',
    'pending.api:HandleInternalUseItem'
)) {
    if ($lua.Contains($unsafeCall)) {
        throw "Unsafe UE4SS soft-object read is present: $unsafeCall"
    }
}

if ($lua.Contains('if not state.quickRestorePending then')) {
    throw 'Page input must not wait for quick-access restoration.'
}

Write-Host 'Static tests passed.'

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mainLua = Join-Path $projectRoot 'mods\ExpandedQuickAccess\Scripts\main.lua'
$config = Join-Path $projectRoot 'mods\ExpandedQuickAccess\config.txt'
$enabled = Join-Path $projectRoot 'mods\ExpandedQuickAccess\enabled.txt'
$nativeMain = Join-Path $projectRoot 'native\ExpandedQuickAccess\main.cpp'
$routeLayout = Join-Path $projectRoot 'native\ExpandedQuickAccess\route_layout.hpp'
$routingTests = Join-Path $projectRoot 'native\ExpandedQuickAccess\routing_tests.cpp'
$moduleDefinition = Join-Path $projectRoot 'native\ExpandedQuickAccess\UE4SS.def'

foreach ($path in @(
    $mainLua,
    $config,
    $enabled,
    $nativeMain,
    $routeLayout,
    $routingTests,
    $moduleDefinition
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

$lua = Get-Content -LiteralPath $mainLua -Raw
$requiredLuaTokens = @(
    'MOD_VERSION = "0.2.0"',
    'Gamepad_LeftTrigger',
    'Gamepad_RightTrigger',
    'GetInventorySlots(INVENTORY_ITEMS)',
    'GetQuickActionSlots()',
    'payload.InventoryIndex = inventoryIndex',
    'payload.OwningInventoryType = inventoryType',
    'PageChangeCooldownMilliseconds',
    'sourceImage.Brush',
    'targetImage:SetBrush(brush)',
    'state.quickRestorePending',
    'allowFallback',
    'candidate.InventorySlot',
    'data:GetName()',
    'LoopAsync(cfg.PollMilliseconds'
)
foreach ($token in $requiredLuaTokens) {
    if (-not $lua.Contains($token)) {
        throw "Required Lua integration is missing: $token"
    }
}

foreach ($obsoleteLuaToken in @(
    'RegisterHook',
    'InventoryController:',
    'HandleInternalUseItem',
    'routingUntil',
    'rerouteCount',
    'data:GetIcon()',
    'data:GetCategoryClassIcon()'
)) {
    if ($lua.Contains($obsoleteLuaToken)) {
        throw "Unsafe or obsolete Lua integration is present: $obsoleteLuaToken"
    }
}

$native = Get-Content -LiteralPath $nativeMain -Raw
$requiredNativeTokens = @(
    'MOD_VERSION = L"0.2.0"',
    'SELECTION_CALLSITE_BYTES',
    'HANDLE_INTERNAL_USE_ITEM_BYTES',
    'callsite_matches.size() != 1',
    'target_matches.size() != 1',
    'resolved_target != target_matches.front()',
    '0x4C, 0x8B, 0xCB',
    'VirtualAlloc(',
    'PAGE_EXECUTE_READ',
    'FlushInstructionCache(',
    'resolve_inventory_route(',
    'g_handle_internal_use_item(inventory_api, inventory_index, inventory_type)',
    'g_selection_patch.replacement',
    'restore_selection_patch()',
    'VirtualFree('
)
foreach ($token in $requiredNativeTokens) {
    if (-not $native.Contains($token)) {
        throw "Required native integration is missing: $token"
    }
}

$layout = Get-Content -LiteralPath $routeLayout -Raw
$requiredLayoutTokens = @(
    'QUICK_ACCESS_RADIAL_SLICES_OFFSET = 0x5A8',
    'QUICK_ACCESS_RADIAL_SLICE_COUNT_OFFSET = 0x5B0',
    'QUICK_ACCESS_SLICE_SLOT_OFFSET = 0x428',
    'SLOT_PAYLOAD_OFFSET = 0x1860',
    'INVENTORY_INDEX_OFFSET = 0x40',
    'OWNING_INVENTORY_TYPE_OFFSET = 0x44',
    'candidate_type != INVENTORY_ITEMS',
    'candidate_index >= MAIN_INVENTORY_SLOT_COUNT',
    '__except (EXCEPTION_EXECUTE_HANDLER)'
)
foreach ($token in $requiredLayoutTokens) {
    if (-not $layout.Contains($token)) {
        throw "Required native layout guard is missing: $token"
    }
}

$nativeTestText = Get-Content -LiteralPath $routingTests -Raw
foreach ($case in @(
    'first main slot was not routed',
    'last main slot was not routed',
    'quick slot was rerouted',
    'out-of-range inventory slot was routed',
    'out-of-range slice was routed',
    'null radial was routed',
    'wrong slice count was routed'
)) {
    if (-not $nativeTestText.Contains($case)) {
        throw "Required native routing test is missing: $case"
    }
}

if ((Get-Content -LiteralPath $enabled -Raw).Trim() -ne '1') {
    throw 'enabled.txt must contain 1.'
}

$configKeys = Get-Content -LiteralPath $config |
    Where-Object { $_ -match '^\s*[A-Za-z]' } |
    ForEach-Object { ($_ -split '=', 2)[0].Trim() }
$expectedKeys = @(
    'PollMilliseconds',
    'PageChangeCooldownMilliseconds',
    'TriggerThreshold',
    'LeftKeyboardKey',
    'RightKeyboardKey',
    'ShowPageLabel',
    'DebugLogging'
)
foreach ($key in $expectedKeys) {
    if ($configKeys -notcontains $key) {
        throw "Required configuration key is missing: $key"
    }
}

Write-Host 'Static tests passed.'

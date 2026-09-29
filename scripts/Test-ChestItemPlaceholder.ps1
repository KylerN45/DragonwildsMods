[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modRoot = Join-Path $projectRoot 'mods\ChestItemPlaceholder'
$mainLua = Join-Path $modRoot 'Scripts\main.lua'
$configLua = Join-Path $modRoot 'Scripts\config.lua'
$stateFile = Join-Path $modRoot 'Scripts\chest_item_placeholder_active.txt'
$enabledFile = Join-Path $modRoot 'enabled.txt'
$instructions = Join-Path $modRoot 'instructions.txt'

foreach ($path in @($mainLua, $configLua, $stateFile, $enabledFile, $instructions)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

$lua = Get-Content -LiteralPath $mainLua -Raw
foreach ($token in @(
    'local VERSION = "1.0.0"',
    'local TAG = "[ChestItemPlaceholder] "',
    'api:GetInventoryComponent()',
    'content.CurrentInventory',
    'WBP_WorldActorInventory_VerticalNavigation_C',
    'namedWidget(content, "VerticalBox")',
    'reflectedWidget(content, "WorldInventoryBody")',
    'reflectedWidget(content, "LabelNameHorizontalBox")',
    'container = verticalAncestor(body)',
    'matchingVerticalBox()',
    'verticalBox:InsertChildAt(inputIndex, widget)',
    'verticalBox:InsertChildAt(bodyIndex + 1, widget)',
    'verticalBox:AddChildToHorizontalBox(widget)',
    'hud:GetInventoryAPI()',
    'cachedInventoryAPI, "InventoryComponent"',
    'cachedInventoryAPI, "InventoryController"',
    'local function inventorySnapshot(inventory)',
    'local function monitorReserve()',
    'local matched = math.min(state.lossCredit, state.gainCredit)',
    'local shouldProtectLoss = chestLoss > 0',
    'and state.previousChest > 1',
    'and chestTotal < state.reserve',
    'previousSlots = slotCounts(entry)',
    'state.returnSlot = slot',
    'targetIsSafe = targetCount == 0 or sameObject(targetData, state.data)',
    'controller:SplitAndPutStack(playerInventory, sourceSlot, amount, chest, targetSlot)',
    'returning %d item(s) to chest slot %d to preserve the reserve',
    'ChestItemPlaceholder.active = placeholderEnabled',
    'ChestItemPlaceholder.placeholderAmount = PLACEHOLDER_AMOUNT',
    'chest_item_placeholder_active.txt',
    'WBP_Settings_Checkbox',
    'InputsTakeAll',
    'RegisterKeyBind(Key.F6',
    'RegisterConsoleCommandHandler, "chestitemplaceholder"',
    'local function forgetCheckbox()',
    'local function forgetCurrentChest()',
    'checkboxContentKey == contentKey',
    'local inventory = inventoryFromContent(content)',
    'LoopInGameThreadWithDelay(100, gameThreadUpdate)'
)) {
    if (-not $lua.Contains($token)) {
        throw "Required Chest Item Placeholder integration is missing: $token"
    }
}

$brandedSources = $lua + "`n" + (Get-Content -LiteralPath $configLua -Raw) +
    "`n" + (Get-Content -LiteralPath $instructions -Raw)
foreach ($oldName in @('LeaveJustOne', 'leavejustone', 'ljo_', 'LEAVE_AMOUNT')) {
    if ($brandedSources.Contains($oldName)) {
        throw "Old mod identity is present: $oldName"
    }
}

foreach ($unsafe in @(
    ':AddItemByData(',
    ':RemoveItemByData(',
    ':GetSlotForItem(',
    'RegisterHook(',
    'Server_MoveItemBetweenInventories',
    'Server_SplitAndPutStack',
    'ExecuteUbergraph_WBP_WorldActorInventory_ItemSlot',
    'WBP_WorldActorInventory_ItemSlot_C',
    'LoopAsync(',
    ':RemoveFromParent(',
    'CB_X=',
    '1920x1080'
)) {
    if ($lua.Contains($unsafe)) {
        throw "Unsafe or obsolete Chest Item Placeholder code is present: $unsafe"
    }
}

if ((Get-Content -LiteralPath $enabledFile -Raw).Trim() -ne '1') {
    throw 'enabled.txt must contain 1.'
}
if ((Get-Content -LiteralPath $stateFile -Raw).Trim() -ne '1') {
    throw 'The packaged chest_item_placeholder_active.txt state must contain 1.'
}
if (-not (Get-Content -LiteralPath $configLua -Raw).Contains('PLACEHOLDER_AMOUNT = 1')) {
    throw 'config.lua must contain the default PLACEHOLDER_AMOUNT value.'
}

Write-Host 'Chest Item Placeholder static tests passed.'

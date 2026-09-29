-- Chest Item Placeholder v1.0.0
-- Target: RuneScape: Dragonwilds 1.0, CL-244954

local TAG = "[ChestItemPlaceholder] "
local VERSION = "1.0.0"

local function log(message)
    print(TAG .. tostring(message) .. "\n")
end

local function valid(object)
    if not object then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function full(object)
    local ok, name = pcall(function() return object:GetFullName() end)
    return ok and tostring(name) or "?"
end

local function sameObject(left, right)
    if not valid(left) or not valid(right) then return false end
    if left == right then return true end
    return full(left) == full(right)
end

local function dereference(value)
    if value == nil then return nil end
    local result = value
    pcall(function() result = value:get() end)
    return result
end

local function scriptDirectory()
    local source = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    return source:match("^(.*)[/\\][^/\\]*$")
end

local scripts = scriptDirectory()
local stateFile = scripts and (scripts .. "\\chest_item_placeholder_active.txt") or nil

local function loadPlaceholderAmount()
    local amount = 1
    if scripts then
        local environment = {}
        setmetatable(environment, { __index = _G })
        local okLoad, chunk, loadMessage = pcall(
            loadfile, scripts .. "\\config.lua", "t", environment)
        if okLoad and chunk then
            local okRun, message = pcall(chunk)
            if okRun then
                amount = tonumber(environment.PLACEHOLDER_AMOUNT) or amount
            else
                log("config.lua could not be read: " .. tostring(message))
            end
        else
            log("config.lua could not be loaded; using PLACEHOLDER_AMOUNT=1: "
                .. tostring(okLoad and loadMessage or chunk))
        end
    end
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then amount = 1 end
    if amount > 9999 then amount = 9999 end
    return amount
end

local PLACEHOLDER_AMOUNT = loadPlaceholderAmount()

local function readEnabledState()
    if not stateFile then return true end
    local file = io.open(stateFile, "r")
    if not file then return true end
    local value = file:read("*l")
    file:close()
    return tostring(value or "1"):match("^%s*0%s*$") == nil
end

local placeholderEnabled = readEnabledState()

local function writeEnabledState()
    if not stateFile then return end
    local file, message = io.open(stateFile, "w")
    if not file then
        log("could not write chest_item_placeholder_active.txt: " .. tostring(message))
        return
    end
    file:write(placeholderEnabled and "1\n" or "0\n")
    file:close()
end

ChestItemPlaceholder = type(ChestItemPlaceholder) == "table" and ChestItemPlaceholder or {}
local function syncPublicState()
    ChestItemPlaceholder.active = placeholderEnabled
    ChestItemPlaceholder.placeholderAmount = PLACEHOLDER_AMOUNT
    ChestItemPlaceholder.version = VERSION
end
syncPublicState()

-- Current world inventory ------------------------------------------------------------------------

local cachedPC, cachedHUD, cachedWorldAPI = nil, nil, nil
local nextPCScan, nextAPIScan = 0, 0
local currentInventory, currentInventoryKey, currentContentKey = nil, nil, nil
local chestProtectionEnabled = true
local guardKey = nil
local trackedItems = {}

local function resetReserveGuard()
    guardKey = nil
    trackedItems = {}
end

local function localPlayerController()
    if valid(cachedPC) then
        local ok, localController = pcall(function() return cachedPC:IsLocalController() end)
        if ok and localController == true then return cachedPC end
    end
    cachedPC = nil
    if os.clock() < nextPCScan then return nil end
    nextPCScan = os.clock() + 2
    local controllers = nil
    pcall(function() controllers = FindAllOf("PlayerController") end)
    if type(controllers) ~= "table" then return nil end
    for _, controller in ipairs(controllers) do
        if valid(controller) and not full(controller):find("Default__", 1, true) then
            local isLocal = false
            pcall(function() isLocal = controller:IsLocalController() end)
            if isLocal then cachedPC = controller return controller end
        end
    end
    return nil
end

local function hudSubsystem()
    if valid(cachedHUD) then return cachedHUD end
    cachedHUD = nil
    pcall(function() cachedHUD = FindFirstOf("HUDUISubsystem") end)
    return valid(cachedHUD) and cachedHUD or nil
end

local function worldInventoryAPI()
    if valid(cachedWorldAPI) then return cachedWorldAPI end
    cachedWorldAPI = nil
    if os.clock() < nextAPIScan then return nil end
    nextAPIScan = os.clock() + 1
    local hud = hudSubsystem()
    if valid(hud) then
        pcall(function() cachedWorldAPI = hud.WorldActorInventoryAPI end)
        if not valid(cachedWorldAPI) then
            pcall(function() cachedWorldAPI = hud:GetWorldActorInventoryAPI() end)
        end
    end
    if not valid(cachedWorldAPI) then
        pcall(function() cachedWorldAPI = FindFirstOf("WorldActorInventoryUIAPI") end)
    end
    return valid(cachedWorldAPI) and cachedWorldAPI or nil
end

local function inventoryFromAPI(api)
    if not valid(api) then return nil end
    local inventory = nil
    local readers = {
        function() return api:GetInventoryComponent() end,
        function() return api.InventoryComponent end,
    }
    for _, read in ipairs(readers) do
        pcall(function() inventory = read() end)
        inventory = dereference(inventory)
        if valid(inventory) then return inventory end
    end
    return nil
end

local function inventorySlotCount(inventory)
    if not valid(inventory) then return 0 end
    local count = nil
    pcall(function() count = inventory.MaxSlotCount end)
    if type(count) ~= "number" then pcall(function() count = inventory:GetMaxSlotCount() end) end
    count = math.floor(tonumber(count) or 0)
    if count < 1 or count > 2000 then return 0 end
    return count
end

local function isPlayerStorage(inventory)
    if not valid(inventory) or inventorySlotCount(inventory) == 0 then return false end
    local supportsStorageActions = nil
    pcall(function() supportsStorageActions = inventory.bSupportsSortAndFillStacks end)
    return supportsStorageActions == true
end

local function inventoryKey(inventory)
    if not valid(inventory) then return nil end
    local owner = nil
    pcall(function() owner = inventory:GetOwner() end)
    if valid(owner) then return full(owner) end
    return full(inventory)
end

-- Live checkbox ----------------------------------------------------------------------------------

local CHECKBOX_LABEL = "Keep item placeholders in this chest"
local checkboxWidget, checkboxInput, checkboxFocus, takeAllFocus = nil, nil, nil, nil
local checkboxContentKey = nil
local checkboxSuppressedForDrag = false
local checkboxNeedsReset = false
local uiMessages = {}

local function logUIOnce(key, message)
    if uiMessages[key] then return end
    uiMessages[key] = true
    log(message)
end

local function namedWidget(widget, name)
    if not valid(widget) then return nil end
    local result = nil
    pcall(function() result = widget[name] end)
    if valid(result) then return result end
    pcall(function() result = widget:GetWidgetFromName(FName(name)) end)
    return valid(result) and result or nil
end

local function findNewestLive(classNames)
    for _, className in ipairs(classNames) do
        local objects = nil
        pcall(function() objects = FindAllOf(className) end)
        if type(objects) == "table" then
            for index = #objects, 1, -1 do
                local object = objects[index]
                if valid(object) and not full(object):find("Default__", 1, true) then
                    local visible = true
                    pcall(function() visible = object:IsVisible() end)
                    if visible ~= false then return object end
                end
            end
        end
    end
    return nil
end

local function liveInventoryContent()
    return findNewestLive({
        "WBP_WorldActorInventory_VerticalNavigation_C",
        "WorldActorInventoryContent",
    })
end

local function inventoryFromContent(content)
    if not valid(content) then return nil end
    local inventory = nil
    pcall(function() inventory = content.CurrentInventory end)
    inventory = dereference(inventory)
    return valid(inventory) and inventory or nil
end

-- The game owns the checkbox after it is inserted into the chest panel. When that panel closes,
-- release every Lua reference without calling the widget. Calling RemoveFromParent during the
-- game's own UI teardown can race destruction of the pause and inventory screens.
local function forgetCheckbox()
    checkboxWidget, checkboxInput, checkboxFocus, takeAllFocus = nil, nil, nil, nil
    checkboxContentKey = nil
    checkboxSuppressedForDrag = false
end

local function setCheckboxLabel(widget)
    pcall(function() widget.LabelText = FText(CHECKBOX_LABEL) end)
    local labelButton = nil
    pcall(function() labelButton = widget.InputLabelButton end)
    if valid(labelButton) then
        pcall(function() labelButton.ButtonLabel = FText(CHECKBOX_LABEL) end)
        local text = nil
        pcall(function() text = labelButton.LabelText end)
        if valid(text) then pcall(function() text:SetText(FText(CHECKBOX_LABEL)) end) end
    end
    pcall(function()
        widget:SetToolTipText(FText(
            "Keep the configured placeholder amount in this player-built chest."))
    end)
end

local function createCheckbox(pc)
    pcall(function() LoadAsset("/Game/UI/Settings/WBP_Settings_Checkbox") end)
    local class, library, widget = nil, nil, nil
    pcall(function()
        class = StaticFindObject("/Game/UI/Settings/WBP_Settings_Checkbox.WBP_Settings_Checkbox_C")
    end)
    pcall(function() library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    if valid(class) and valid(library) then
        pcall(function() widget = library:Create(pc, class, pc) end)
    end
    if not valid(widget) then return nil, nil, nil end
    local input = nil
    pcall(function() input = widget.InputCheckBox end)
    if not valid(input) then return nil, nil, nil end
    setCheckboxLabel(widget)
    pcall(function() widget.bIsFocusable = true end)
    pcall(function() input.bIsFocusable = true end)
    return widget, input, widget
end

local function parentOf(widget)
    if not valid(widget) then return nil end
    local slot, parent = nil, nil
    pcall(function() slot = widget.Slot end)
    if valid(slot) then pcall(function() parent = slot.Parent end) end
    return valid(parent) and parent or nil
end

local function reflectedWidget(owner, propertyName)
    if not valid(owner) then return nil end
    local widget = nil
    pcall(function() widget = owner[propertyName] end)
    widget = dereference(widget)
    return valid(widget) and widget or nil
end

local function liveInventoryInputs()
    return findNewestLive({ "WBP_WorldActorInventory_Inputs_C" })
end

local function verticalAncestor(widget)
    local current = widget
    for _ = 1, 8 do
        current = parentOf(current)
        if not valid(current) then return nil end
        if full(current):find("VerticalBox", 1, true) then return current end
    end
    return nil
end

local function matchingVerticalBox()
    local boxes = nil
    pcall(function() boxes = FindAllOf("VerticalBox") end)
    if type(boxes) ~= "table" then return nil end
    for index = #boxes, 1, -1 do
        local box = boxes[index]
        local name = valid(box) and full(box) or ""
        if name:find("WBP_WorldActorInventory_VerticalNavigation", 1, true)
            and not name:find("Default__", 1, true) then return box end
    end
    return nil
end

local function inventoryPanelWidgets(content)
    local inputs = namedWidget(content, "InventoryInputs")
    if not valid(inputs) then inputs = liveInventoryInputs() end

    -- These two fields are native reflected properties on UWorldActorInventoryContent.
    -- Their panel slots expose the real cooked parent even when Blueprint widget names do not.
    local body = reflectedWidget(content, "WorldInventoryBody")
    if not valid(body) then body = namedWidget(content, "WorldInventoryBody") end
    local labelRow = reflectedWidget(content, "LabelNameHorizontalBox")
    if not valid(labelRow) then labelRow = namedWidget(content, "LabelNameHorizontalBox") end

    local container = namedWidget(content, "VerticalBox")
    if not valid(container) then container = verticalAncestor(inputs) end
    if not valid(container) then container = verticalAncestor(body) end
    if not valid(container) then container = verticalAncestor(labelRow) end
    if not valid(container) then container = matchingVerticalBox() end

    -- The native label row is a reliable final target. A header-row option is better than
    -- silently omitting the control if a future cooked hierarchy hides every parent panel.
    local headerFallback = false
    if not valid(container) and valid(labelRow) then
        container = labelRow
        headerFallback = true
    end
    return container, inputs, body, headerFallback
end

local function attachCheckbox(pc, content, contentKey)
    if checkboxContentKey == contentKey and valid(checkboxWidget) and valid(checkboxInput) then
        return true
    end
    forgetCheckbox()
    if not valid(content) or contentKey == nil then return false end

    local verticalBox, inventoryInputs, inventoryBody, headerFallback =
        inventoryPanelWidgets(content)
    local takeAll = nil
    if valid(inventoryInputs) then takeAll = namedWidget(inventoryInputs, "InputsTakeAll") end
    if not valid(takeAll) then takeAll = namedWidget(content, "InputsTakeAll") end
    if not valid(verticalBox) then
        logUIOnce("no-parent", "the world-inventory option container was not found")
        return false
    end

    local widget, input, focus = createCheckbox(pc)
    if not valid(widget) then
        logUIOnce("no-widget", "the current game checkbox widget was not found")
        return false
    end

    local slot, placement = nil, nil
    if not headerFallback and valid(inventoryInputs) then
        local inputIndex = nil
        pcall(function() inputIndex = verticalBox:GetChildIndex(inventoryInputs) end)
        if type(inputIndex) == "number" and inputIndex >= 0 then
            pcall(function() slot = verticalBox:InsertChildAt(inputIndex, widget) end)
            if valid(slot) then placement = "before inventory controls" end
        end
    end
    if not valid(slot) and not headerFallback and valid(inventoryBody) then
        local bodyIndex = nil
        pcall(function() bodyIndex = verticalBox:GetChildIndex(inventoryBody) end)
        if type(bodyIndex) == "number" and bodyIndex >= 0 then
            pcall(function() slot = verticalBox:InsertChildAt(bodyIndex + 1, widget) end)
            if valid(slot) then placement = "after the chest inventory" end
        end
    end
    if not valid(slot) then
        if headerFallback then
            pcall(function() slot = verticalBox:AddChildToHorizontalBox(widget) end)
        else
            pcall(function() slot = verticalBox:AddChildToVerticalBox(widget) end)
        end
        if not valid(slot) then pcall(function() slot = verticalBox:AddChild(widget) end) end
        if valid(slot) then
            placement = headerFallback and "in the chest header" or "at the end of the inventory panel"
        end
    end
    if not valid(slot) then
        logUIOnce("rejected", "the world-inventory panel rejected the checkbox")
        return false
    end
    pcall(function() slot:SetPadding({ Left = 8, Top = 8, Right = 8, Bottom = 8 }) end)
    pcall(function() widget:SetVisibility(placeholderEnabled and 0 or 1) end)
    pcall(function() input:SetIsChecked(chestProtectionEnabled) end)

    checkboxWidget, checkboxInput, checkboxFocus = widget, input, focus
    takeAllFocus = takeAll
    checkboxContentKey = contentKey
    if valid(takeAllFocus) then
        pcall(function()
            takeAllFocus:SetNavigationRuleExplicit(3, checkboxFocus)
            checkboxFocus:SetNavigationRuleExplicit(2, takeAllFocus)
        end)
    end
    log("added the controller-focusable option to the current chest panel (" .. placement .. ")")
    return true
end

local function syncCheckbox(pc, content, contentKey)
    if contentKey ~= currentContentKey or not valid(content)
        or not valid(currentInventory) or not isPlayerStorage(currentInventory) then
        forgetCheckbox()
        return
    end
    if not attachCheckbox(pc, content, contentKey) then return end
    if checkboxNeedsReset then
        pcall(function() checkboxInput:SetIsChecked(true) end)
        checkboxNeedsReset = false
    end
    pcall(function() checkboxWidget:SetVisibility(placeholderEnabled and 0 or 1) end)
    if not placeholderEnabled then return end
    local checked = nil
    pcall(function() checked = checkboxInput:IsChecked() end)
    if type(checked) == "boolean" then chestProtectionEnabled = checked end
end

local function suppressCheckboxDuringDrag(contentKey)
    if contentKey ~= currentContentKey or checkboxContentKey ~= contentKey
        or not valid(checkboxWidget) or not valid(checkboxFocus) or not placeholderEnabled then return end
    local dragging = false
    local hud = hudSubsystem()
    local dragAPI = nil
    if valid(hud) then
        pcall(function() dragAPI = hud.DragAndDropAPI end)
        if not valid(dragAPI) then pcall(function() dragAPI = hud:GetDragAndDropAPI() end) end
    end
    if valid(dragAPI) then
        local state = nil
        pcall(function() state = dragAPI:IsDragInProgress() end)
        if type(state) == "boolean" then
            dragging = state
        else
            local payload = nil
            pcall(function() payload = dragAPI.CurrentDragPayload end)
            dragging = valid(payload)
        end
    end
    if dragging == checkboxSuppressedForDrag then return end
    checkboxSuppressedForDrag = dragging
    if dragging then
        pcall(function() checkboxFocus:SetIsEnabled(false) end)
        pcall(function() checkboxWidget:SetVisibility(1) end)
    else
        pcall(function() checkboxWidget:SetVisibility(0) end)
        pcall(function() checkboxFocus:SetIsEnabled(true) end)
    end
end

local function forgetCurrentChest()
    currentInventory, currentInventoryKey, currentContentKey = nil, nil, nil
    chestProtectionEnabled = true
    checkboxNeedsReset = false
    forgetCheckbox()
    resetReserveGuard()
end

local function updateCurrentInventory()
    local content = liveInventoryContent()
    if not valid(content) then
        forgetCurrentChest()
        return nil, nil
    end

    -- A live chest panel is mandatory. The API can retain the last chest after this panel closes.
    local contentKey = full(content)
    local inventory = inventoryFromContent(content)
    if not valid(inventory) then inventory = inventoryFromAPI(worldInventoryAPI()) end
    if not valid(inventory) then
        forgetCurrentChest()
        return nil, nil
    end
    local key = inventoryKey(inventory)
    local contentChanged = contentKey ~= currentContentKey
    local inventoryChanged = key ~= currentInventoryKey
    if contentChanged then
        forgetCheckbox()
        uiMessages = {}
    end
    if contentChanged or inventoryChanged then
        currentInventory, currentInventoryKey, currentContentKey = inventory, key, contentKey
        chestProtectionEnabled = true
        checkboxNeedsReset = true
        if inventoryChanged then uiMessages = {} end
        if isPlayerStorage(inventory) then log("opened player storage: " .. tostring(key)) end
    else
        currentInventory = inventory
    end
    return content, contentKey
end

-- Reserve guard ----------------------------------------------------------------------------------

local function slotItem(inventory, slot)
    local item, count, data = nil, 0, nil
    pcall(function() item = inventory:GetItemFromSlot(slot) end)
    if item == nil then return nil, 0, nil end
    pcall(function() data = item.ItemData end)
    data = dereference(data)
    pcall(function() count = inventory:GetNumItemsInSlot(slot) end)
    count = math.floor(tonumber(count) or 0)
    if not valid(data) or count <= 0 then return item, 0, nil end
    return item, count, data
end

local function inventorySnapshot(inventory)
    local snapshot = {}
    if not valid(inventory) then return snapshot end
    for slot = 0, inventorySlotCount(inventory) - 1 do
        local item, count, data = slotItem(inventory, slot)
        if count > 0 and valid(data) then
            local key = full(data)
            local entry = snapshot[key]
            if not entry then
                entry = { data = data, item = item, total = 0, slots = {} }
                snapshot[key] = entry
            end
            entry.total = entry.total + count
            entry.slots[#entry.slots + 1] = { index = slot, item = item, count = count }
        end
    end
    return snapshot
end

local function slotCounts(entry)
    local counts = {}
    if entry and type(entry.slots) == "table" then
        for _, slot in ipairs(entry.slots) do counts[slot.index] = slot.count end
    end
    return counts
end

local cachedInventoryAPI = nil
local function playerInventoryContext()
    if not valid(cachedInventoryAPI) then
        cachedInventoryAPI = nil
        local hud = hudSubsystem()
        if valid(hud) then
            pcall(function() cachedInventoryAPI = hud.InventoryAPI end)
            if not valid(cachedInventoryAPI) then
                pcall(function() cachedInventoryAPI = hud:GetInventoryAPI() end)
            end
        end
        if not valid(cachedInventoryAPI) then
            pcall(function() cachedInventoryAPI = FindFirstOf("InventoryUIAPI") end)
        end
    end
    if not valid(cachedInventoryAPI) then return nil, nil end
    local inventory = reflectedWidget(cachedInventoryAPI, "InventoryComponent")
    local controller = reflectedWidget(cachedInventoryAPI, "InventoryController")
    if not valid(inventory) or not valid(controller) then return nil, nil end
    return inventory, controller
end

-- Current chest slots use native C++ input handlers. Those handlers call the inventory controller
-- directly and bypass UE4SS UFunction hooks. Compare both replicated inventories instead. A repair
-- is permitted only when the chest loses an item and this local player gains the same item.
local returnedCount, detectedCount, failedReturnCount = 0, 0, 0
local CORRELATION_SECONDS = 1.0
local RETURN_TIMEOUT_SECONDS = 5.0
local MAX_RETURN_ATTEMPTS = 2

local function initialiseReserveGuard(chest, playerInventory)
    guardKey = inventoryKey(chest)
    trackedItems = {}
    local chestItems = inventorySnapshot(chest)
    local playerItems = inventorySnapshot(playerInventory)
    for key, entry in pairs(chestItems) do
        trackedItems[key] = {
            data = entry.data,
            reserve = math.min(PLACEHOLDER_AMOUNT, entry.total),
            previousChest = entry.total,
            previousPlayer = playerItems[key] and playerItems[key].total or 0,
            lossCredit = 0,
            gainCredit = 0,
            lossAt = 0,
            gainAt = 0,
            repairCredit = 0,
            pendingAmount = 0,
            pendingUntil = 0,
            attempts = 0,
            previousSlots = slotCounts(entry),
            returnSlot = entry.slots[1] and entry.slots[1].index or nil,
        }
    end
    log("reserve guard is active for this chest")
end

local function requestReturn(controller, playerInventory, chest, playerEntry, state, amount)
    local sourceSlot, sourceItem, sourceCount = nil, nil, 0
    for _, slot in ipairs(playerEntry.slots) do
        if slot.count > sourceCount then
            sourceSlot, sourceItem, sourceCount = slot.index, slot.item, slot.count
        end
    end
    amount = math.min(math.max(0, math.floor(amount)), sourceCount)
    if sourceSlot == nil or amount <= 0 or not valid(sourceItem) then return false end

    -- GetSlotForItem finds the exact UItem object. The returned player item is not the
    -- same object that was in the chest, so that function returns -1 after a full-stack
    -- transfer. Reuse the chest slot whose count decreased instead.
    local targetSlot = tonumber(state.returnSlot)
    local targetIsSafe = false
    if type(targetSlot) == "number" and targetSlot >= 0
        and targetSlot < inventorySlotCount(chest) then
        local _, targetCount, targetData = slotItem(chest, targetSlot)
        targetIsSafe = targetCount == 0 or sameObject(targetData, state.data)
    end
    if not targetIsSafe then
        for slot = 0, inventorySlotCount(chest) - 1 do
            local _, targetCount = slotItem(chest, slot)
            if targetCount == 0 then
                targetSlot, targetIsSafe = slot, true
                break
            end
        end
    end
    if not targetIsSafe then
        logUIOnce("return-space", "an item could not be returned because the chest has no target slot")
        return false
    end
    local ok, message = pcall(function()
        controller:SplitAndPutStack(playerInventory, sourceSlot, amount, chest, targetSlot)
    end)
    if ok then
        state.pendingAmount = amount
        state.pendingUntil = os.clock() + RETURN_TIMEOUT_SECONDS
        state.attempts = state.attempts + 1
        log(string.format(
            "returning %d item(s) to chest slot %d to preserve the reserve",
            amount, targetSlot))
        return true
    else
        failedReturnCount = failedReturnCount + 1
        log("the server return request failed: " .. tostring(message))
        return false
    end
end

local function monitorReserve()
    if not placeholderEnabled or not chestProtectionEnabled or not isPlayerStorage(currentInventory) then
        resetReserveGuard()
        return
    end
    local playerInventory, controller = playerInventoryContext()
    if not valid(playerInventory) or not valid(controller)
        or sameObject(playerInventory, currentInventory) then return end

    local key = inventoryKey(currentInventory)
    if guardKey ~= key then
        initialiseReserveGuard(currentInventory, playerInventory)
        return
    end

    local now = os.clock()
    local chestItems = inventorySnapshot(currentInventory)
    local playerItems = inventorySnapshot(playerInventory)

    -- Start tracking an item when it is first deposited into this open chest.
    for itemKey, entry in pairs(chestItems) do
        if not trackedItems[itemKey] then
            trackedItems[itemKey] = {
                data = entry.data,
                reserve = math.min(PLACEHOLDER_AMOUNT, entry.total),
                previousChest = entry.total,
                previousPlayer = playerItems[itemKey] and playerItems[itemKey].total or 0,
                lossCredit = 0, gainCredit = 0, lossAt = 0, gainAt = 0,
                repairCredit = 0, pendingAmount = 0, pendingUntil = 0, attempts = 0,
                previousSlots = slotCounts(entry),
                returnSlot = entry.slots[1] and entry.slots[1].index or nil,
            }
        end
    end

    for itemKey, state in pairs(trackedItems) do
        local chestTotal = chestItems[itemKey] and chestItems[itemKey].total or 0
        local playerTotal = playerItems[itemKey] and playerItems[itemKey].total or 0
        local currentSlots = slotCounts(chestItems[itemKey])

        -- Keep the exact chest slot that lost this item. A full-stack transfer removes
        -- the old UItem object, but the emptied source slot remains the valid return target.
        local largestSlotLoss = 0
        for slot, previousCount in pairs(state.previousSlots or {}) do
            local slotLoss = previousCount - (currentSlots[slot] or 0)
            if slotLoss > largestSlotLoss then
                largestSlotLoss = slotLoss
                state.returnSlot = slot
            end
        end

        -- Increase the reserve after more of an initially small stack is deposited.
        state.reserve = math.min(PLACEHOLDER_AMOUNT, math.max(state.reserve, chestTotal))

        local recovered = math.max(0, chestTotal - state.previousChest)
        if recovered > 0 then
            state.repairCredit = math.max(0, state.repairCredit - recovered)
            state.pendingAmount = math.max(0, state.pendingAmount - recovered)
            if state.pendingAmount == 0 then state.attempts = 0 end
        end
        if chestTotal >= state.reserve then
            state.repairCredit = 0
            state.pendingAmount = 0
            state.attempts = 0
        end

        if state.lossCredit > 0 and now - state.lossAt > CORRELATION_SECONDS then
            state.lossCredit = 0
        end
        if state.gainCredit > 0 and now - state.gainAt > CORRELATION_SECONDS then
            state.gainCredit = 0
        end

        local chestLoss = math.max(0, state.previousChest - chestTotal)
        local playerGain = math.max(0, playerTotal - state.previousPlayer)
        -- A separately transferred final item is intentional. Protect the reserve only when
        -- this loss started above one item and this same loss crossed below the reserve.
        local shouldProtectLoss = chestLoss > 0
            and state.previousChest > 1
            and chestTotal < state.reserve
        if shouldProtectLoss then
            state.lossCredit = state.lossCredit + chestLoss
            state.lossAt = now
        end
        if playerGain > 0 then
            state.gainCredit = state.gainCredit + playerGain
            state.gainAt = now
        end

        local matched = math.min(state.lossCredit, state.gainCredit)
        if matched > 0 then
            state.lossCredit = state.lossCredit - matched
            state.gainCredit = state.gainCredit - matched
            local deficit = math.max(0, state.reserve - chestTotal)
            if deficit > 0 then
                local credit = math.min(deficit, matched)
                state.repairCredit = math.min(deficit, state.repairCredit + credit)
                detectedCount = detectedCount + credit
            end
        end

        if state.pendingAmount > 0 and now >= state.pendingUntil then
            state.pendingAmount = 0
            failedReturnCount = failedReturnCount + 1
            log("a chest reserve return was not confirmed by replication")
        end

        local deficit = math.max(0, state.reserve - chestTotal)
        local returnAmount = math.min(deficit, state.repairCredit)
        local playerEntry = playerItems[itemKey]
        if returnAmount > 0 and state.pendingAmount == 0 and state.attempts < MAX_RETURN_ATTEMPTS
            and playerEntry and playerEntry.total > 0 then
            returnAmount = math.min(returnAmount, playerEntry.total)
            if requestReturn(controller, playerInventory, currentInventory,
                    playerEntry, state, returnAmount) then
                returnedCount = returnedCount + returnAmount
            end
        end

        state.previousChest = chestTotal
        state.previousPlayer = playerTotal
        state.previousSlots = currentSlots
    end
end

-- Controls and status ----------------------------------------------------------------------------

local function togglePlaceholder(source)
    placeholderEnabled = not placeholderEnabled
    writeEnabledState()
    syncPublicState()
    log(string.format("%s: %s", tostring(source), placeholderEnabled and "enabled" or "disabled"))
end

RegisterKeyBind(Key.F6, function()
    ExecuteInGameThread(function() togglePlaceholder("F6") end)
end)

pcall(RegisterConsoleCommandHandler, "chestitemplaceholder", function(_, parameters)
    local command = parameters and parameters[1] and tostring(parameters[1]):lower() or "status"
    if command == "toggle" then
        togglePlaceholder("console")
    elseif command ~= "status" then
        log("usage: chestitemplaceholder [status|toggle]")
    else
        log(string.format(
            "status: enabled=%s, chest=%s, reserve=%d, detected=%d, returned=%d, failed=%d",
            tostring(placeholderEnabled), tostring(chestProtectionEnabled), PLACEHOLDER_AMOUNT,
            detectedCount, returnedCount, failedReturnCount))
    end
    return true
end)

local errors, disabledByErrors = 0, false
local function gameThreadUpdate()
    if disabledByErrors then return end
    local ok, message = pcall(function()
        local content, contentKey = updateCurrentInventory()
        local pc = localPlayerController()
        if valid(pc) and valid(content) then syncCheckbox(pc, content, contentKey) end
        suppressCheckboxDuringDrag(contentKey)
        monitorReserve()
    end)
    if not ok then
        errors = errors + 1
        if errors <= 5 then log("UI update error: " .. tostring(message)) end
        if errors >= 25 then
            disabledByErrors = true
            forgetCurrentChest()
            log("too many UI errors; the checkbox is disabled for this session")
        end
    end
end

-- UE4SS deprecates LoopAsync for game-object work because it runs on an async Lua thread.
-- Keep all inventory and widget access in the safer delayed-action game-thread state.
local loopStarted, loopMessage = pcall(function()
    LoopInGameThreadWithDelay(100, gameThreadUpdate)
end)
if not loopStarted then
    disabledByErrors = true
    forgetCurrentChest()
    log("the UE4SS game-thread timer is unavailable: " .. tostring(loopMessage))
end

log(string.format("loaded v%s for Dragonwilds 1.0. PLACEHOLDER_AMOUNT=%d -- F6 to toggle",
    VERSION, PLACEHOLDER_AMOUNT))

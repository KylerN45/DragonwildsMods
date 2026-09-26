-- Expanded Quick Access v0.2.0
-- Adds the three main-inventory rows to the standard eight-slice quick-access radial.

local TAG = "[ExpandedQuickAccess] "
local MOD_VERSION = "0.2.0"
local PAGE_COUNT = 4
local SLOTS_PER_PAGE = 8
local QUICK_ACTION = 0
local INVENTORY_ITEMS = 1

local cfg = {
    PollMilliseconds = 16,
    PageChangeCooldownMilliseconds = 200,
    TriggerThreshold = 0.55,
    LeftKeyboardKey = "Q",
    RightKeyboardKey = "E",
    ShowPageLabel = true,
    DebugLogging = false,
}

local state = {
    radial = nil,
    inventoryAPI = nil,
    playerController = nil,
    page = 0,
    wasOpen = false,
    leftTriggerDown = false,
    rightTriggerDown = false,
    leftTriggerKey = nil,
    rightTriggerKey = nil,
    leftKeyboardKey = nil,
    rightKeyboardKey = nil,
    nextObjectScan = 0,
    queued = false,
    queuedAt = 0,
    errors = 0,
    disabled = false,
    nextPageChangeAt = 0,
    quickRestorePending = true,
    nextRestoreAt = 0,
}

local function log(message)
    print(TAG .. tostring(message) .. "\n")
end

local function debugLog(message)
    if cfg.DebugLogging then log("DEBUG " .. tostring(message)) end
end

local function valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok then return result end
    return value
end

local function fullName(object)
    if not valid(object) then return "" end
    local ok, result = pcall(function() return object:GetFullName() end)
    return ok and tostring(result) or ""
end

local function modRoot()
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    local scripts = source:match("^(.*)[/\\][^/\\]+$")
    if scripts == nil then return nil end
    return scripts:match("^(.*)[/\\][^/\\]+$")
end

local function parseBoolean(value)
    value = tostring(value):lower()
    if value == "true" or value == "1" or value == "yes" then return true end
    if value == "false" or value == "0" or value == "no" then return false end
    return nil
end

local function loadConfig()
    local root = modRoot()
    if root == nil then
        log("could not locate config.txt; defaults will be used")
        return
    end

    local file = io.open(root .. "\\config.txt", "r")
    if file == nil then
        log("config.txt was not found; defaults will be used")
        return
    end

    for line in file:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, value = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
            if key ~= nil and cfg[key] ~= nil then
                if type(cfg[key]) == "boolean" then
                    local parsed = parseBoolean(value)
                    if parsed == nil then
                        log("invalid boolean for " .. key .. ": " .. tostring(value))
                    else
                        cfg[key] = parsed
                    end
                elseif type(cfg[key]) == "number" then
                    local parsed = tonumber(value)
                    if parsed == nil then
                        log("invalid number for " .. key .. ": " .. tostring(value))
                    else
                        cfg[key] = parsed
                    end
                else
                    cfg[key] = value
                end
            elseif key ~= nil then
                log("unknown config key ignored: " .. key)
            end
        end
    end
    file:close()

    cfg.PollMilliseconds = math.max(8, math.min(100, math.floor(cfg.PollMilliseconds)))
    cfg.PageChangeCooldownMilliseconds = math.max(0,
        math.min(1000, math.floor(cfg.PageChangeCooldownMilliseconds)))
    cfg.TriggerThreshold = math.max(0.1, math.min(0.95, cfg.TriggerThreshold))
end

local function makeFKey(keyName)
    if keyName == nil or tostring(keyName):lower() == "none" then return nil end
    if FName == nil or type(EFindName) ~= "table" or EFindName.FNAME_Find == nil then
        return nil
    end
    local ok, name = pcall(FName, tostring(keyName), EFindName.FNAME_Find)
    if not ok or name == nil then return nil end
    return { KeyName = name }
end

local function isLocalController(controller)
    if not valid(controller) then return false end
    local ok, result = pcall(function() return controller:IsLocalController() end)
    return ok and result == true
end

local function findLocalController()
    if isLocalController(state.playerController) then return state.playerController end
    state.playerController = nil

    if valid(state.inventoryAPI) then
        local ok, controller = pcall(function() return state.inventoryAPI.PlayerController end)
        if ok and isLocalController(controller) then
            state.playerController = controller
            return controller
        end
    end

    local ok, controllers = pcall(FindAllOf, "PlayerController")
    if not ok or controllers == nil then return nil end
    for _, controller in ipairs(controllers) do
        if isLocalController(controller) and not fullName(controller):find("MainMenu", 1, true) then
            state.playerController = controller
            return controller
        end
    end
    return nil
end

local function usableRadial(candidate)
    if not valid(candidate) then return false end
    local name = fullName(candidate)
    return name ~= "" and not name:find("Default__", 1, true)
end

local function findRadial()
    if usableRadial(state.radial) then return state.radial end
    state.radial = nil

    local ok, candidates = pcall(FindAllOf, "WBP_QuickAccess_RadialSelector_C")
    if ok and candidates ~= nil then
        for _, candidate in ipairs(candidates) do
            if usableRadial(candidate) then
                state.radial = candidate
                debugLog("found radial " .. fullName(candidate))
                return candidate
            end
        end
    end
    return nil
end

local function findInventoryAPI(radial)
    if valid(state.inventoryAPI) then return state.inventoryAPI end
    state.inventoryAPI = nil

    if valid(radial) then
        local ok, slices = pcall(function() return radial.Slices end)
        if ok and slices ~= nil then
            local okSlice, slice = pcall(function() return unwrap(slices[1]) end)
            if okSlice and valid(slice) then
                local okSlot, slot = pcall(function() return slice.QuickAccessSlot end)
                if okSlot and valid(slot) then
                    local okAPI, api = pcall(function() return unwrap(slot.InventoryAPI) end)
                    if okAPI and valid(api) then
                        state.inventoryAPI = api
                        return api
                    end
                end
            end
        end
    end

    local okSubsystems, subsystems = pcall(FindAllOf, "HUDUISubsystem")
    if okSubsystems and subsystems ~= nil then
        for _, subsystem in ipairs(subsystems) do
            if valid(subsystem) and not fullName(subsystem):find("Default__", 1, true) then
                local okAPI, api = pcall(function() return subsystem:GetInventoryAPI() end)
                if okAPI and valid(api) then
                    state.inventoryAPI = api
                    return api
                end
            end
        end
    end

    local okAPIs, apis = pcall(FindAllOf, "InventoryUIAPI")
    if okAPIs and apis ~= nil then
        for _, api in ipairs(apis) do
            if valid(api) and not fullName(api):find("Default__", 1, true) then
                local okReady, ready = pcall(function() return api:IsInventoryInitialized() end)
                if okReady and ready == true then
                    state.inventoryAPI = api
                    return api
                end
            end
        end
    end
    return nil
end

local function radialIsOpen(radial)
    if not usableRadial(radial) then return false end

    local okActive, active = pcall(function() return radial:IsActivated() end)
    if okActive and type(active) == "boolean" then return active end

    local okVisible, visible = pcall(function() return radial:IsVisible() end)
    if okVisible and type(visible) == "boolean" then return visible end

    local okVisibility, visibility = pcall(function() return radial:GetVisibility() end)
    return okVisibility and (visibility == 0 or visibility == 3 or visibility == 4)
end

local function arrayItem(array, zeroBasedIndex)
    if array == nil then return nil end
    local ok, item = pcall(function() return unwrap(array[zeroBasedIndex + 1]) end)
    if ok then return item end
    return nil
end

local function pageItems(api, page)
    if not valid(api) then return nil, QUICK_ACTION, 0 end
    if page == 0 then
        local ok, items = pcall(function() return api:GetQuickActionSlots() end)
        return ok and items or nil, QUICK_ACTION, 0
    end
    local ok, items = pcall(function() return api:GetInventorySlots(INVENTORY_ITEMS) end)
    return ok and items or nil, INVENTORY_ITEMS, (page - 1) * SLOTS_PER_PAGE
end

local function setText(widget, text)
    if not valid(widget) then return end
    pcall(function() widget:SetText(FText(tostring(text))) end)
end

local function slotItemMatches(slot, item)
    local ok, contained = pcall(function() return slot:GetContainedItem() end)
    if not ok then return false end
    if not valid(contained) and not valid(item) then return true end
    return valid(contained) and valid(item) and fullName(contained) == fullName(item)
end

local function collectVisualSources(inventoryType, excludedNames)
    local className = inventoryType == QUICK_ACTION
        and "WBP_Inventory_QuickAccess_ItemSlot_C"
        or "WBP_Inventory_ItemSlot_C"
    local ok, candidates = pcall(FindAllOf, className)
    if not ok or candidates == nil then return {} end

    local sources = {}
    for _, candidate in ipairs(candidates) do
        local sourceSlot = candidate
        if inventoryType == QUICK_ACTION and valid(candidate) then
            local okNested, nested = pcall(function() return candidate.InventorySlot end)
            if okNested then sourceSlot = nested end
        end

        local name = fullName(sourceSlot)
        if valid(sourceSlot) and name ~= "" and not name:find("Default__", 1, true)
            and not excludedNames[name] then
            local okPayload, payload = pcall(function() return sourceSlot.SlotPayload end)
            local index = nil
            if okPayload and valid(payload) then
                pcall(function() index = tonumber(payload.InventoryIndex) end)
            end
            if index ~= nil and index >= 0 then
                sources[index] = sources[index] or {}
                table.insert(sources[index], sourceSlot)
            end
        end
    end
    return sources
end

local function findVisualSource(sources, inventoryIndex, item, allowFallback)
    local candidates = sources[inventoryIndex]
    if candidates == nil then return nil end
    for _, candidate in ipairs(candidates) do
        if valid(candidate) and slotItemMatches(candidate, item) then return candidate end
    end
    if allowFallback then
        for _, candidate in ipairs(candidates) do
            if valid(candidate) then return candidate end
        end
    end
    return nil
end

local function readImageBrush(sourceSlot, imageProperty)
    local okImage, sourceImage = pcall(function() return sourceSlot[imageProperty] end)
    if not okImage or not valid(sourceImage) then return nil end
    local okBrush, brush = pcall(function() return sourceImage.Brush end)
    return okBrush and brush or nil
end

local function readSlotVisual(sourceSlot)
    if not valid(sourceSlot) then return nil end
    local itemBrush = readImageBrush(sourceSlot, "ItemImage")
    if itemBrush == nil then return nil end
    return {
        itemBrush = itemBrush,
        categoryBrush = readImageBrush(sourceSlot, "ItemCategoryClassImage"),
    }
end

local function setImageBrush(targetSlot, imageProperty, brush)
    if brush == nil then return false end
    local okImage, targetImage = pcall(function() return targetSlot[imageProperty] end)
    if not okImage or not valid(targetImage) then return false end
    return pcall(function() targetImage:SetBrush(brush) end)
end

local function applySlotVisual(visual, targetSlot)
    if visual == nil or not valid(targetSlot) then return false end
    local itemCopied = setImageBrush(targetSlot, "ItemImage", visual.itemBrush)
    setImageBrush(targetSlot, "ItemCategoryClassImage", visual.categoryBrush)
    return itemCopied
end

local function refreshSlot(slice, item, inventoryIndex, inventoryType, visual)
    if not valid(slice) then return false end
    local okSlot, slot = pcall(function() return slice.QuickAccessSlot end)
    if not okSlot or not valid(slot) or visual == nil then return false end

    pcall(function() slot.ContainedItem = item end)
    pcall(function()
        local payload = slot.SlotPayload
        if valid(payload) then
            payload.InventoryIndex = inventoryIndex
            payload.OwningInventoryType = inventoryType
        end
    end)

    local count = 0
    if valid(item) then pcall(function() count = item:GetStackSize() end) end
    local countText = count > 1 and tostring(count) or ""
    pcall(function() setText(slot.StackSizeText, countText) end)

    pcall(function() slice:SetEnabled(valid(item)) end)
    pcall(function() slice:RefreshUI() end)
    return applySlotVisual(visual, slot)
end

local PAGE_LABELS = {
    [0] = "QUICK ACCESS  1 / 4",
    [1] = "INVENTORY ROW 1  2 / 4",
    [2] = "INVENTORY ROW 2  3 / 4",
    [3] = "INVENTORY ROW 3  4 / 4",
}

local function showPageLabel(radial, page)
    if not cfg.ShowPageLabel or not valid(radial) then return end
    local ok, label = pcall(function() return radial.ItemName end)
    if ok then setText(label, PAGE_LABELS[page] or "") end
end

local function showSelectedItemName(radial)
    if state.page == 0 or not valid(radial) then return end

    local selected = nil
    pcall(function() selected = tonumber(radial.CachedSectionId) end)
    if selected == nil or selected < 0 or selected >= SLOTS_PER_PAGE then
        showPageLabel(radial, state.page)
        return
    end
    local api = findInventoryAPI(radial)
    local items, _, offset = pageItems(api, state.page)
    local item = arrayItem(items, offset + selected)
    if not valid(item) then
        showPageLabel(radial, state.page)
        return
    end

    local data, itemName = nil, nil
    pcall(function() data = item:BP_GetItemData() end)
    if valid(data) then pcall(function() itemName = data:GetName() end) end

    local okLabel, label = pcall(function() return radial.ItemName end)
    if okLabel and valid(label) and itemName ~= nil then
        pcall(function() label:SetText(itemName) end)
    end
end

local function applyPage(radial, page)
    local api = findInventoryAPI(radial)
    if not valid(api) then return false, "inventory API is not ready" end

    local items, inventoryType, offset = pageItems(api, page)
    if items == nil then return false, "inventory slots are not ready" end

    local okSlices, slices = pcall(function() return radial.Slices end)
    if not okSlices or slices == nil then return false, "radial slices are not ready" end

    local targets = {}
    local excludedNames = {}
    for zeroIndex = 0, SLOTS_PER_PAGE - 1 do
        local slice = arrayItem(slices, zeroIndex)
        local okSlot, slot = pcall(function() return slice.QuickAccessSlot end)
        if not okSlot or not valid(slot) then return false, "radial slot is not ready" end
        targets[zeroIndex] = { slice = slice, slot = slot }
        excludedNames[fullName(slot)] = true
    end

    local visualSources = collectVisualSources(inventoryType, excludedNames)
    local resolvedVisuals = {}
    for zeroIndex = 0, SLOTS_PER_PAGE - 1 do
        local item = arrayItem(items, offset + zeroIndex)
        local source = findVisualSource(visualSources, offset + zeroIndex, item, page == 0)
        if not valid(source) then
            return false, "inventory slot visuals are not ready; open the inventory once"
        end
        local visual = readSlotVisual(source)
        if visual == nil then return false, "inventory slot brushes are not ready" end
        resolvedVisuals[zeroIndex] = visual
    end

    local updated = 0
    for zeroIndex = 0, SLOTS_PER_PAGE - 1 do
        local item = arrayItem(items, offset + zeroIndex)
        if refreshSlot(targets[zeroIndex].slice, item, offset + zeroIndex, inventoryType,
            resolvedVisuals[zeroIndex]) then
            updated = updated + 1
        end
    end
    if updated ~= SLOTS_PER_PAGE then
        return false, "only " .. tostring(updated) .. " radial slices were available"
    end

    showPageLabel(radial, page)
    debugLog("showing page " .. tostring(page) .. " with inventory offset " .. tostring(offset))
    return true, nil
end

local function changePage(delta)
    local radial = state.radial
    if not radialIsOpen(radial) then return end

    local now = os.clock() * 1000
    if now < state.nextPageChangeAt then return end
    state.nextPageChangeAt = now + cfg.PageChangeCooldownMilliseconds

    local nextPage = (state.page + delta) % PAGE_COUNT
    local ok, reason = applyPage(radial, nextPage)
    if ok then
        state.page = nextPage
        if nextPage ~= 0 then state.quickRestorePending = false end
    else
        log("could not change page: " .. tostring(reason))
    end
end

local function analogDown(controller, key)
    if not isLocalController(controller) or key == nil then return false end
    local ok, value = pcall(function() return controller:GetInputAnalogKeyState(key) end)
    return ok and math.abs(tonumber(value) or 0) >= cfg.TriggerThreshold
end

local function justPressed(controller, key)
    if not isLocalController(controller) or key == nil then return false end
    local ok, value = pcall(function() return controller:WasInputKeyJustPressed(key) end)
    return ok and value == true
end

local function pollPageInput(controller)
    local leftDown = analogDown(controller, state.leftTriggerKey)
    local rightDown = analogDown(controller, state.rightTriggerKey)
    local left = leftDown and not state.leftTriggerDown
    local right = rightDown and not state.rightTriggerDown
    state.leftTriggerDown = leftDown
    state.rightTriggerDown = rightDown

    left = left or justPressed(controller, state.leftKeyboardKey)
    right = right or justPressed(controller, state.rightKeyboardKey)

    if left and not right then changePage(-1)
    elseif right and not left then changePage(1) end
end

local function resetInputEdges()
    state.leftTriggerDown = false
    state.rightTriggerDown = false
end

local function tick()
    if state.disabled then return end

    local radial = state.radial
    if not usableRadial(radial) then
        local now = os.clock()
        if now >= state.nextObjectScan then
            state.nextObjectScan = now + 2
            radial = findRadial()
        end
    end

    local now = os.clock()
    local open = radialIsOpen(radial)
    if open and not state.wasOpen then
        state.page = 0
        state.quickRestorePending = true
        state.nextRestoreAt = 0
        state.nextPageChangeAt = 0
        resetInputEdges()
        findInventoryAPI(radial)
        debugLog("radial opened")
    elseif not open and state.wasOpen then
        if state.page ~= 0 then state.quickRestorePending = true end
        state.page = 0
        resetInputEdges()
        debugLog("radial closed")
    end
    state.wasOpen = open

    if open then
        if state.page == 0 and state.quickRestorePending and now >= state.nextRestoreAt then
            local restored, reason = applyPage(radial, 0)
            if restored then
                state.quickRestorePending = false
                debugLog("restored the quick-access page")
            else
                state.nextRestoreAt = now + 0.25
                debugLog("quick page restore deferred: " .. tostring(reason))
            end
        end

        local controller = findLocalController()
        if isLocalController(controller) then pollPageInput(controller) end
        showSelectedItemName(radial)
    end
end

local function registerStatusCommand()
    pcall(RegisterConsoleCommandHandler, "expandedquickaccess", function(_, parameters)
        local command = parameters and parameters[1] and tostring(parameters[1]):lower() or "status"
        if command ~= "status" then
            log("usage: expandedquickaccess status")
            return true
        end
        log(string.format("status: version=%s, radial=%s, open=%s, page=%d, inventoryAPI=%s, restorePending=%s, errors=%d",
            MOD_VERSION, tostring(usableRadial(state.radial)), tostring(radialIsOpen(state.radial)),
            state.page, tostring(valid(state.inventoryAPI)), tostring(state.quickRestorePending),
            state.errors))
        return true
    end)
end

loadConfig()
state.leftTriggerKey = makeFKey("Gamepad_LeftTrigger")
state.rightTriggerKey = makeFKey("Gamepad_RightTrigger")
state.leftKeyboardKey = makeFKey(cfg.LeftKeyboardKey)
state.rightKeyboardKey = makeFKey(cfg.RightKeyboardKey)

registerStatusCommand()

LoopAsync(cfg.PollMilliseconds, function()
    if state.queued and os.clock() - state.queuedAt > 5 then state.queued = false end
    if state.queued or state.disabled then return false end
    state.queued = true
    state.queuedAt = os.clock()
    local sent = pcall(ExecuteInGameThread, function()
        state.queued = false
        local ok, message = pcall(tick)
        if not ok then
            state.errors = state.errors + 1
            if state.errors <= 5 then log("tick error: " .. tostring(message)) end
            if state.errors >= 25 then
                state.disabled = true
                log("disabled for this session after repeated errors")
            end
        end
    end)
    if not sent then state.queued = false end
    return false
end)

log(string.format("loaded v%s; 4 radial pages enabled; triggers=%s; keyboard=%s/%s; native selection router required",
    MOD_VERSION, tostring(state.leftTriggerKey ~= nil and state.rightTriggerKey ~= nil),
    tostring(cfg.LeftKeyboardKey), tostring(cfg.RightKeyboardKey)))

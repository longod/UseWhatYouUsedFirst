---@class Config
local defaultConfig = {
    light = true,
    lockpick = true,
    probe = true,
    repairTool = true,
    notify = true,
}
local configPath = "longod.UseWhatYouUsedFirst"
---@type Config
local config = mwse.loadConfig(configPath, defaultConfig)


--- This is a generic iterator function that is used
--- to loop over all the items in an inventory
---@param ref tes3reference
---@return fun(): tes3light|tes3lockpick|tes3probe|tes3repairTool, integer, tes3itemData|nil
local function IterItems(ref)
    local function iterator()
        for _, stack in pairs(ref.object.inventory) do
            ---@cast stack tes3itemStack
            local item = stack.object

            -- Account for restocking items,
            -- since their count is negative
            local count = math.abs(stack.count)

            -- first yield stacks with custom data
            if stack.variables then
                for _, data in pairs(stack.variables) do
                    if data then
                        coroutine.yield(item, data.count, data)
                        count = count - data.count
                    end
                end
            end
            -- then yield all the remaining copies
            if count > 0 then
                coroutine.yield(item, count)
            end
        end
    end
    return coroutine.wrap(iterator)
end

---@param item tes3item
---@param itemData tes3itemData?
---@return number?
local function GetCondition(item, itemData)
    if item.objectType == tes3.objectType.lockpick or
        item.objectType == tes3.objectType.probe or
        item.objectType == tes3.objectType.repairItem then
        ---@cast item tes3lockpick|tes3probe|tes3repairTool
        return itemData and itemData.condition or item.maxCondition
    elseif item.objectType == tes3.objectType.light then
        ---@cast item tes3light
        return itemData and itemData.timeLeft or item.time
    end
    return nil
end

---@param item tes3item
---@return boolean
local function Enable(item)
    local types = {
        [tes3.objectType.light] = config.light,
        [tes3.objectType.lockpick ] = config.lockpick,
        [tes3.objectType.probe ] = config.probe,
        [tes3.objectType.repairItem ] = config.repairTool,
    }
    return types[item.objectType] or false
end


---@param id string
---@param cond number
---@return tes3light|tes3lockpick|tes3probe|tes3repairTool?
---@return tes3itemData?
---@return number
local function FindMostUsed(id, cond)
    local minItem = nil
    local minItemData = nil
    for item, _, itemData in IterItems(tes3.player) do
        if item and item.id == id then
            local c = GetCondition(item, itemData)
            if c and c > 0 and cond > c then -- be less equal than zero?
                cond = c
                minItem = item
                minItemData = itemData
            end
        end
    end
    return minItem, minItemData, cond
end

--- @param e equipEventData
local function OnEquip(e)
    -- player?
    if e.reference ~= tes3.mobilePlayer.reference then
        return
    end
    if not Enable(e.item) then
        return
    end
    -- TODO skip if key pressed
    
    local condition = GetCondition(e.item, e.itemData)
    if condition ~= nil then
        local item, itemData, cond = FindMostUsed(e.item.id, condition)
        if item then
            e.block = true
            tes3.mobilePlayer:equip({ item = item, itemData = itemData})
            if config.notify then
                if item.objectType == tes3.objectType.light then
                    tes3.messageBox(string.format("You switched to %s with the least amount of duration.", item.name))
                else
                    tes3.messageBox(string.format("You switched to %s (uses: %u) with the least amount of remaining.", item.name, cond))
                end
            end
        end
    end
end

-- If there are other callbacks, I'd better prioritize those.
event.register(tes3.event.equip, OnEquip, { priority = -1 })

local function OnModConfigReady()
    local template = mwse.mcm.createTemplate("Use What You Used First")
    template:saveOnClose(configPath, config)
    template:register()

    local page = template:createSideBarPage {
        label = "Settings",
        description = (
            "When using a consumable item that has a number of uses or time, if you have same items already used, you can use the one with the least amount of remaining instead."
            )
    }

    ---@param value boolean
    ---@return string
    local function GetOnOff(value)
        ---@diagnostic disable-next-line: return-type-mismatch
        return value and tes3.findGMST(tes3.gmst.sOn).value  or tes3.findGMST(tes3.gmst.sNo).value
    end

    local names = {
        "light",
        "lockpick",
        "probe",
        "repairTool",
        "notify",
    }
    local labels = {
        "Light Sources",
        "Lockpicks",
        "Probes",
        "Repair Tools",
        "Notification",
    }
    local descs = {
        "Use a light source with the least amount of duration instead.",
        "Use a lockpick with the least amount of remaining instead.",
        "Use a probe with the least amount of remaining instead.",
        "Use a repair tool with the least amount of remaining instead.",
        "Notify when you use the item instead.",
    }

    for i, v in ipairs(names) do
        page:createOnOffButton {
            label = labels[i],
            description = (
                descs[i] ..
                "\n\nDefault: " .. GetOnOff(defaultConfig[v])
                ),
            variable = mwse.mcm.createTableVariable {
                id = v,
                table = config,
            }
        }
    end

end

event.register(tes3.event.modConfigReady, OnModConfigReady)

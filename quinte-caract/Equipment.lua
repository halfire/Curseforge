local _, Q = ...
Q.itemRetries = {}
local function request(id)
    local attempts = Q.itemRetries[id] or 0
    if attempts >= 3 then return end
    Q.itemRetries[id] = attempts + 1
    Q.Read('RequestLoadItemDataByID', (C_Item or {}).RequestLoadItemDataByID, id)
    if C_Timer and C_Timer.After then
        local delay = ({1, 3, 10})[attempts + 1]
        C_Timer.After(delay, function() if Q.pendingItems[id] then Q.Schedule() end end)
    end
end
function Q.CollectEquipment()
    local rows, pending, total, count, complete = {}, {}, 0, 0, true
    local available = type(GetInventoryItemLink) == 'function' or type(GetInventoryItemID) == 'function'
    if not available then return nil, nil end
    local old = QuinteCaractDB.characters[Q.Key()]
    local previous = {}
    for _, row in ipairs(old and old.source == 'self' and old.equipment or {}) do previous[row.slot] = row end
    for slot = 1, 19 do
        local link = Q.String(Q.Read('GetInventoryItemLink.' .. slot, GetInventoryItemLink, 'player', slot), 2048)
        local id = Q.Number(Q.Read('GetInventoryItemID.' .. slot, GetInventoryItemID, 'player', slot), 1, 1e9, true)
        local parsedID, parsedEnchant
        if link then parsedID, parsedEnchant = link:match('item:(%d+):(%d*)') end
        id = id or Q.Number(tonumber(parsedID), 1, 1e9, true)
        if id then
            local name, _, quality, baseLevel = Q.Read('GetItemInfo.' .. slot, (C_Item or {}).GetItemInfo or GetItemInfo, link or id)
            local level = Q.Number(Q.Read('GetDetailedItemLevelInfo.' .. slot,
                (C_Item or {}).GetDetailedItemLevelInfo or GetDetailedItemLevelInfo, link or id), 0, 10000)
            -- A detailed API that exists but is still loading must not be replaced with a misleading base ilvl.
            if type((C_Item or {}).GetDetailedItemLevelInfo or GetDetailedItemLevelInfo) ~= 'function' then
                level = Q.Number(baseLevel, 0, 10000)
            end
            name = Q.String(name)
            if not name and link then name = Q.String(link:match('%[([^%]]+)%]')) end
            if not name and previous[slot] and previous[slot].item == id then name = previous[slot].name end
            local enchant
            if parsedEnchant ~= nil then enchant = tonumber(parsedEnchant) or 0 end
            quality = Q.Number(quality, 0, 8, true)
            if quality == nil and previous[slot] and previous[slot].item == id then quality = previous[slot].quality end
            rows[#rows + 1] = {slot = slot, item = id, name = name, ilvl = level, enchant = enchant, quality = quality}
            count = count + 1
            if level then total = total + level else complete = false end
            if not name or not level or not link then pending[id] = true else Q.itemRetries[id] = nil end
        elseif previous[slot] then
            -- Preserve an occupied slot if an inventory API failed; a successful nil means unequipped.
            local ls, ids = Q.api['GetInventoryItemLink.' .. slot], Q.api['GetInventoryItemID.' .. slot]
            if (ls.state == 'erreur' or ls.state == 'restreinte') or (ids.state == 'erreur' or ids.state == 'restreinte') then
                rows[#rows + 1] = previous[slot]; complete = false
                if previous[slot].item then pending[previous[slot].item] = true end
            end
        end
    end
    Q.pendingItems = pending
    for id in pairs(pending) do request(id) end
    local overall, equipped = Q.Read('GetAverageItemLevel', GetAverageItemLevel)
    local average = Q.Number(equipped, 0, 10000) or Q.Number(overall, 0, 10000)
    if not average and complete and count > 0 then average = total / count end
    return rows, average
end

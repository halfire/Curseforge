local _, Q = ...
--[[
  Codex.lua : Le Codex Secret de Quintessence (Objets Inédits & Chase Items de WoW Forever).
  Scanne chaque objet rare/épique/légendaire ramassé par un membre pour constituer
  une encyclopédie secrète interne à la guilde des nouveaux loots et recettes de raids/donjons.
]]

-- Ajouter un objet au Codex Secret
function Q.AddCodexItem(itemID, itemLink, name, quality, ilvl, equipLoc, zone, finder)
    itemID = tonumber(itemID)
    if not itemID then return false end

    if not QuinteGroupDB.codex then QuinteGroupDB.codex = {} end

    local existing = QuinteGroupDB.codex[itemID]
    if existing then return false end -- Déjà répertorié

    local itemData = {
        id = itemID,
        link = itemLink or ('item:' .. itemID),
        name = name or ('Objet #' .. itemID),
        quality = quality or 4,
        ilvl = ilvl or 60,
        equipLoc = equipLoc or '',
        zone = zone or (GetZoneText and GetZoneText()) or 'Inconnue',
        finder = finder or (Q.PlayerName and Q.PlayerName()) or 'Quintessence',
        foundAt = Q.Now()
    }

    QuinteGroupDB.codex[itemID] = itemData

    -- Diffusion à la guilde
    if Q.comm and Q.comm.Send then
        Q.comm:Send({
            t = 'codex_item',
            item = itemData
        })
    end

    if QuinteGroupDB.settings and QuinteGroupDB.settings.announceCodex then
        Q.Print(string.format('|cffffd200[Codex Secret]|r Nouvel objet découvert par |cffffffff%s|r : %s à %s !',
            itemData.finder, itemData.link, itemData.zone))
    end

    if Q.UI and Q.UI.RefreshCodex then Q.UI.RefreshCodex() end
    return true, itemData
end

-- Réception d'un objet découvert par un membre de la guilde
function Q.OnReceiveCodexItem(data, sender)
    if not data or not data.item or not data.item.id then return end
    local item = data.item
    local itemID = tonumber(item.id)
    if not itemID then return end

    if not QuinteGroupDB.codex then QuinteGroupDB.codex = {} end
    if not QuinteGroupDB.codex[itemID] then
        QuinteGroupDB.codex[itemID] = item
        if QuinteGroupDB.settings and QuinteGroupDB.settings.announceCodex then
            Q.Print(string.format('|cffffd200[Codex Secret]|r Nouvel objet partagé par |cffffffff%s|r : %s !',
                sender or item.finder or 'Guilde', item.link or item.name))
        end
        if Q.UI and Q.UI.RefreshCodex then Q.UI.RefreshCodex() end
    end
end

-- Qualité lue dans la couleur du lien (|cffa335ee… = épique) quand l'objet n'est pas encore dans le cache du jeu
local LINK_QUALITY = {
    ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6,
}

-- Traitement des messages de loot (CHAT_MSG_LOOT)
function Q.OnLootMessage(msg)
    if type(msg) ~= 'string' or (type(issecretvalue) == 'function' and issecretvalue(msg)) then return end
    -- Lien complet d'abord (|c…|Hitem:…|h[Nom]|h|r) : les motifs suivants le coupaient avant |h|r, et ce lien
    -- tronqué était enregistré tel quel quand l'objet n'était pas encore en cache
    local itemLink = msg:match('(|c%x+|Hitem:%d+:[^|]*|h%[[^%]]+%]|h|r)')
        or msg:match('(|c%x+|Hitem:%d+:[^|]+|h%[[^%]]+%] roll|r)')
        or msg:match('(|c%x+|Hitem:%d+:[^|]+|h%[[^%]]+%]%|r)')
        or msg:match('(|c%x+|Hitem:%d+:[^|]+|h%[[^%]]+%])')

    if not itemLink then return end
    local itemID = itemLink:match('item:(%d+)')
    if not itemID then return end

    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot = nil
    if fn then
        name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot = fn(itemLink)
    end

    -- Objet pas encore en cache (fréquent sur un nouveau jeu : GetItemInfo renvoie nil) : la qualité vient de la
    -- couleur du lien. Avant, elle valait 4 par défaut et chaque objet blanc ou gris entrait au Codex comme épique.
    quality = quality or LINK_QUALITY[(itemLink:match('^|c(%x%x%x%x%x%x%x%x)') or ''):lower()]
    if quality and quality >= 3 then -- Rare, Épique ou Légendaire
        local zone = (GetZoneText and GetZoneText()) or 'Inconnue'
        Q.AddCodexItem(itemID, link or itemLink, name or itemLink:match('|h%[(.-)%]') or 'Objet Inédit', quality, iLevel or 60, equipSlot or '', zone, Q.PlayerName())
    end
end

-- Récupérer la liste des objets du Codex
function Q.GetCodexItems(filter)
    local list = {}
    if not QuinteGroupDB.codex then return list end

    filter = filter and filter:lower() or ''
    for id, item in pairs(QuinteGroupDB.codex) do
        if filter == '' or (item.name and item.name:lower():find(filter, 1, true)) or (item.zone and item.zone:lower():find(filter, 1, true)) then
            list[#list + 1] = item
        end
    end

    table.sort(list, function(a, b) return (a.foundAt or 0) > (b.foundAt or 0) end)
    return list
end

function Q.GetCodexItemCount()
    local n = 0
    if QuinteGroupDB.codex then
        for _ in pairs(QuinteGroupDB.codex) do n = n + 1 end
    end
    return n
end

function Q.InitCodex()
    local frame = CreateFrame('Frame')
    Q.Call(frame.RegisterEvent, frame, 'CHAT_MSG_LOOT')
    frame:SetScript('OnEvent', function(_, event, msg)
        if event == 'CHAT_MSG_LOOT' then
            Q.Run('loot_codex', Q.OnLootMessage, msg)
        end
    end)
end

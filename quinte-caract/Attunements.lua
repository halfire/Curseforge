local _, Q = ...
--[[
  Attunements.lua : Suivi des accès de raid et clés de donjon (façon Guild OS).
  - Détecte l'accomplissement des quêtes d'harmonisation (Onyxia, MC, BWL, Naxx, Barrow Deeps, Hyjal).
  - Détecte les clés de donjon possédées (UBRS, Scholomance, Stratholme, Hache-Tripes, BRD).
  - Partagé dans la fiche perso QuinteCaractDB pour consultation par la guilde et les officiers.
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]

Q.ATTUNEMENT_DEFS = {
    -- Raids
    ony = { id = 'ony', label = 'Onyxia', kind = 'raid', quests = { 6502, 6501 }, items = { 16309 } },
    mc = { id = 'mc', label = 'Cœur du Magma', kind = 'raid', quests = { 7848 } },
    bwl = { id = 'bwl', label = 'Aile Noire (BWL)', kind = 'raid', quests = { 7761 } },
    naxx = { id = 'naxx', label = 'Naxxramas', kind = 'raid', quests = { 9121, 9122, 9123 } },
    barrow = { id = 'barrow', label = 'Terriers (Forever)', kind = 'raid', quests = { 10001, 10002 } },
    hyjal = { id = 'hyjal', label = 'Hyjal (Forever)', kind = 'raid', quests = { 10005, 10006 } },

    -- Clés de Donjon
    ubrs = { id = 'ubrs', label = 'Clé UBRS', kind = 'key', items = { 12344 } },
    scholo = { id = 'scholo', label = 'Clé Scholo', kind = 'key', items = { 13704 } },
    strath = { id = 'strath', label = 'Clé Strath', kind = 'key', items = { 12382 } },
    dm = { id = 'dm', label = 'Clé Hache-Tripes', kind = 'key', items = { 18249 } },
    brd = { id = 'brd', label = 'Clé BRD', kind = 'key', items = { 11000 } }
}

local function isQuestDone(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok and done then return true end
    end
    if type(IsQuestFlaggedCompleted) == 'function' then
        local ok, done = pcall(IsQuestFlaggedCompleted, questID)
        if ok and done then return true end
    end
    return false
end

local function hasItem(itemID)
    if not itemID then return false end
    if C_Item and C_Item.GetItemCount then
        local ok, count = pcall(C_Item.GetItemCount, itemID, true)
        if ok and type(count) == 'number' and count > 0 then return true end
    end
    if type(GetItemCount) == 'function' then
        local ok, count = pcall(GetItemCount, itemID, true)
        if ok and type(count) == 'number' and count > 0 then return true end
    end
    return false
end

--- Collecte l'état d'harmonisation et de clés du joueur local
function Q.CollectAttunements()
    local result = {}
    for key, def in pairs(Q.ATTUNEMENT_DEFS) do
        local done = false

        -- Vérification des quêtes
        if def.quests then
            for _, qID in ipairs(def.quests) do
                if isQuestDone(qID) then
                    done = true
                    break
                end
            end
        end

        -- Vérification des objets / clés
        if not done and def.items then
            for _, iID in ipairs(def.items) do
                if hasItem(iID) then
                    done = true
                    break
                end
            end
        end

        result[key] = done
    end
    return result
end

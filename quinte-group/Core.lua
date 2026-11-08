local addonName, Q = ...
--[[
  quinte-group : Compagnon de leveling, quêtes partagées, recherche de donjons
  et Codex secret des nouveaux loots de WoW Forever pour la guilde Quintessence.
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]
local Core = Quintessence
Q.name, Q.version = addonName or 'quinte-group', '0.17.2'
Q.debug = { errors = {}, slow = {} }

function Q.Call(fn, ...)
    if type(fn) ~= 'function' then return false end
    return pcall(fn, ...)
end

function Q.Error(context, reason)
    local list = Q.debug.errors
    list[#list + 1] = context .. ': ' .. tostring(reason)
    if #list > 20 then table.remove(list, 1) end
end

local clock = debugprofilestop
function Q.Run(context, fn, ...)
    local started = clock and clock()
    local ok, result = Q.Call(fn, ...)
    if not ok then Q.Error(context, result) end
    if started then
        local elapsed = clock() - started
        if elapsed > 50 then Q.debug.slow[context] = math.max(Q.debug.slow[context] or 0, math.floor(elapsed)) end
    end
    return ok, result
end

function Q.Now() return (time or GetServerTime)() end
function Q.Key() return Core.Key() end
function Q.PlayerName() return Core.PlayerName() end
function Q.Safe(text) return (tostring(text or ''):gsub('|', '||')) end

function Q.Print(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage('|cff3fb950Quintessence Groupe|r ' .. text)
    end
end

local function initSubmodules()
    if Q.InitLeveling and not Q.levelingInitialized then Q.levelingInitialized = true; Q.Run('leveling', Q.InitLeveling) end
    if Q.InitDungeons and not Q.dungeonsInitialized then Q.dungeonsInitialized = true; Q.Run('dungeons', Q.InitDungeons) end
    if not Q.NoCodex() and Q.InitCodex and not Q.codexInitialized then Q.codexInitialized = true; Q.Run('codex', Q.InitCodex) end
    if Q.InitParty and not Q.partyInitialized then Q.partyInitialized = true; Q.Run('groupe', Q.InitParty) end
end

function Q.Init()
    if not Q.ready then
        if type(QuinteGroupDB) ~= 'table' then QuinteGroupDB = {} end
        QuinteGroupDB.format = QuinteGroupDB.format or 1
        QuinteGroupDB.settings = QuinteGroupDB.settings or {
            autoSyncQuests = true,
            announceCodex = true
        }
        QuinteGroupDB.myPreferences = QuinteGroupDB.myPreferences or {
            role = 'DAMAGER',
            dungeons = {},
            status = 'active',
            note = ''
        }
        QuinteGroupDB.memberQuests = QuinteGroupDB.memberQuests or {}
        QuinteGroupDB.memberPreferences = QuinteGroupDB.memberPreferences or {}
        QuinteGroupDB.codex = QuinteGroupDB.codex or {}
        Q.ready = true

        if Core.RegisterChannel then
            Q.comm = Core:RegisterChannel('qgroup', function(data, sender)
                Q.Run('réseau', Q.OnNetworkMessage, data, sender)
            end)
        end
    end

    initSubmodules()
end

--- Édition CurseForge : Donjons & Quêtes seulement, pas de Codex (ni onglet, ni relevé des butins).
function Q.NoCodex() return Core.IsCurseForge ~= nil and Core.IsCurseForge() end

function Q.OnNetworkMessage(data, sender)
    if type(data) ~= 'table' or not data.t then return end
    if data.t == 'codex_item' and Q.NoCodex() then return end
    if data.t == 'quest_sync' and Q.OnReceiveQuestSync then
        Q.OnReceiveQuestSync(data, sender)
    elseif data.t == 'dungeon_pref' and Q.OnReceiveDungeonPref then
        Q.OnReceiveDungeonPref(data, sender)
    elseif data.t == 'signup_reset' and Q.OnReceiveSignupReset then
        Q.OnReceiveSignupReset(data, sender)
    elseif data.t == 'codex_item' and Q.OnReceiveCodexItem then
        Q.OnReceiveCodexItem(data, sender)
    elseif data.t == 'xp' and Q.OnReceiveXP then
        Q.OnReceiveXP(data, sender)
    end
end

local frame = CreateFrame('Frame')
for _, event in ipairs({ 'ADDON_LOADED', 'PLAYER_LOGIN' }) do Q.Call(frame.RegisterEvent, frame, event) end
frame:SetScript('OnEvent', function(_, event, arg)
    Q.Run(event, function()
        if event == 'ADDON_LOADED' then
            if arg == Q.name then Q.Init() end
            return
        end
        Q.Init()
    end)
end)

-- Commandes slash /qgroup
SLASH_QUINTEGROUP1 = '/qgroup'
SLASH_QUINTEGROUP2 = '/qg'
SlashCmdList.QUINTEGROUP = function(message)
    Q.Run('commande', function()
        if not Q.ready then Q.Init() end
        local cmd = (message or ''):lower():match('^%s*(%S*)')
        if cmd == '' then
            Q.UI.Toggle()
        elseif cmd == 'sync' or cmd == 'quests' then
            if Q.BroadcastMyQuests then Q.BroadcastMyQuests(true) end
            Q.Print('Quêtes synchronisées avec la guilde.')
        elseif cmd == 'pref' or cmd == 'dungeon' then
            if Q.BroadcastMyDungeonPreferences then Q.BroadcastMyDungeonPreferences(true) end
            Q.Print('Préférences de donjon diffusées à la guilde.')
        elseif cmd == 'codex' and not Q.NoCodex() then
            local count = Q.GetCodexItemCount and Q.GetCodexItemCount() or 0
            Q.Print('Le Codex Secret de Quintessence contient ' .. count .. ' objet(s) inédit(s).')
        elseif cmd == 'vider' then
            -- Officiers : /qgroup vider (tous les donjons) ou /qgroup vider CODE
            local code = (message or ''):match('^%s*%S+%s+(%S+)')
            local ok, err = Q.ResetSignups(code)
            if not ok then Q.Print(err) end
        elseif cmd == 'debug' then
            Q.Debug()
        else
            Q.Print('/qgroup : ouvrir l\'interface de groupe · /qgroup quests · /qgroup pref' .. (Q.NoCodex() and '' or ' · /qgroup codex') .. ' · /qgroup debug · /qgroup vider (officiers)')
        end
    end)
end

function Q.Debug()
    Q.Print('Module Quinte-group v' .. Q.version)
    local shared = Q.FindSharedQuests and #Q.FindSharedQuests() or 0
    local lfg = Q.GetLFGMembers and #Q.GetLFGMembers() or 0
    local codex = Q.GetCodexItemCount and Q.GetCodexItemCount() or 0
    Q.Print(string.format('Quêtes en commun : %d · Membres en recherche donjon : %d · Objets au Codex : %d', shared, lfg, codex))
    for _, e in ipairs(Q.debug.errors) do Q.Print(Q.Safe(e)) end
end

function Q.Summary()
    local shared = Q.FindSharedQuests and #Q.FindSharedQuests() or 0
    local lfg = Q.GetLFGMembers and #Q.GetLFGMembers() or 0
    if lfg > 0 then
        return lfg .. ' membre(s) cherchent donjon'
    end
    if shared > 0 then
        return shared .. ' quête(s) en commun'
    end
    return 'Recherche donjon & quêtes'
end

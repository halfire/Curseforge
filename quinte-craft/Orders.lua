local _, Q = ...
--[[
  Orders.lua : commandes à un artisan de la guilde, liste de courses et recettes que personne n'a.
  - Commande (canal temps réel `qcraft`, envoyée à l'artisan seul) : recette, quantité, note. L'artisan l'accepte, la
    marque faite ou la refuse ; le demandeur est prévenu. Une commande pas encore reçue (artisan hors ligne) repart
    quand il se connecte. Rien n'est lu par le site (QuinteCraftDB.orders est ignoré à l'import).
  - Liste de courses : composants d'une recette × quantité, ce qu'on a déjà (sacs et banque), et qui dans la guilde
    sait fabriquer chaque composant.
  - Recettes que personne n'a : catalogue Recipes.lua comparé aux recettes connues de toute la guilde.
]]
local MAX_ORDERS, ORDER_DAYS, NOTE_MAX = 60, 7, 120
local STATUSES = { open = 'en attente', accepted = 'acceptée', done = 'faite', declined = 'refusée', cancelled = 'annulée' }
Q.ORDER_STATUSES = STATUSES

local function orders()
    QuinteCraftDB.orders = type(QuinteCraftDB.orders) == 'table' and QuinteCraftDB.orders or {}
    return QuinteCraftDB.orders
end
local function key(name) return Quintessence.CanonicalKey(name or '') end
local function me() return Quintessence.PlayerName() end
local function clean(text, max)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('[%z\1-\31|]', ''):sub(1, max)
    return text ~= '' and text or nil
end

-- ---------------------------------------------------------------------------------------------- Commandes
--- Mes commandes (passées et reçues), les plus récentes d'abord ; anciennes oubliées (7 jours).
function Q.Orders()
    local list, now = {}, Q.Now()
    for id, o in pairs(orders()) do
        if type(o) ~= 'table' or (o.updated or 0) < now - ORDER_DAYS * 86400 then orders()[id] = nil
        else list[#list + 1] = o end
    end
    table.sort(list, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
    return list
end
--- Commandes reçues encore à traiter (pour le compteur de l'onglet).
function Q.OpenOrdersForMe()
    local mine, n = key(me()), 0
    for _, o in ipairs(Q.Orders()) do if key(o.to) == mine and (o.status == 'open' or o.status == 'accepted') then n = n + 1 end end
    return n
end

-- Une seule alerte récapitulative ; fenêtre glissante persistante, même après /reload.
local noticeScheduled = false
function Q.ScheduleOrderNotice(delay)
    if noticeScheduled or not C_Timer or not C_Timer.After then return end
    noticeScheduled = true
    C_Timer.After(delay or 1, function()
        noticeScheduled = false
        Q.Run('alerte commandes', function()
            local count = Q.OpenOrdersForMe()
            if count == 0 or not Q.UI or not Q.UI.OrderNotice then return end
            local now, recent = Q.Now(), {}
            for _, at in ipairs(type(QuinteCraftDB.orderNoticeTimes) == 'table' and QuinteCraftDB.orderNoticeTimes or {}) do
                if type(at) == 'number' and at > now - 600 and at <= now then recent[#recent + 1] = at end
            end
            table.sort(recent)
            QuinteCraftDB.orderNoticeTimes = recent
            -- Une fenêtre déjà visible se met à jour sans nouvelle ouverture.
            if Q.UI.OrderNoticeVisible and Q.UI.OrderNoticeVisible() then Q.UI.OrderNotice(count); return end
            if #recent >= 5 then
                Q.ScheduleOrderNotice(math.max(1, recent[#recent - 4] + 600 - now))
                return
            end
            if Q.UI.OrderNotice(count) then recent[#recent + 1] = now end
        end)
    end)
end

local function send(o, target)
    if not Q.comm or not Q.comm.Send then return false end
    Q.comm:Send({ t = 'order', o = { id = o.id, from = o.from, to = o.to, spell = o.spell, item = o.item, name = o.name,
        count = o.count, note = o.note, status = o.status, updated = o.updated } }, Quintessence.WhisperTarget(target))
    return true
end

--- Commande une recette à un artisan. Retourne la commande, ou nil et la raison.
function Q.PlaceOrder(entry, crafter, count, note)
    if type(entry) ~= 'table' or type(crafter) ~= 'string' or crafter == '' then return nil, 'Recette ou artisan manquant.' end
    if key(crafter) == key(me()) then return nil, 'Tu ne peux pas te passer commande.' end
    local list = Q.Orders()
    if #list >= MAX_ORDERS then return nil, 'Trop de commandes en cours.' end
    local now = Q.Now()
    local o = { id = (me() or '?'):gsub('%s', ''):sub(1, 12) .. now .. math.random(100, 999), from = me(), to = Quintessence.DisplayName(crafter),
        spell = tonumber(entry.spell), item = tonumber(entry.item), name = clean(entry.name, 80), count = math.max(1, math.min(tonumber(count) or 1, 200)),
        note = clean(note, NOTE_MAX), status = 'open', at = now, updated = now }
    orders()[o.id] = o
    o.delivered = send(o, crafter) and Quintessence.IsOnline and Quintessence.IsOnline(crafter) == true or false
    return o
end

--- Change l'état d'une commande (l'artisan : accepted, done, declined ; le demandeur : cancelled) et prévient l'autre.
function Q.SetOrderStatus(id, status)
    local o = orders()[id]
    if not o or not STATUSES[status] then return false end
    local mineTo, mineFrom = key(o.to) == key(me()), key(o.from) == key(me())
    if status == 'cancelled' and not mineFrom then return false end
    if status ~= 'cancelled' and not mineTo then return false end
    o.status, o.updated = status, Q.Tick(o.updated)
    send(o, mineTo and o.from or o.to)
    return true
end

local function validOrder(o)
    if type(o) ~= 'table' then return nil end
    local id = clean(o.id, 40)
    if not id or not STATUSES[o.status] then return nil end
    local from, to = clean(o.from, 60), clean(o.to, 60)
    if not from or not to then return nil end
    local count = tonumber(o.count)
    if not count or count < 1 or count > 200 or count % 1 ~= 0 then return nil end
    local spell, item = tonumber(o.spell), tonumber(o.item)
    if (spell and (spell < 1 or spell > 1e8)) or (item and (item < 1 or item > 1e8)) then return nil end
    local updated = tonumber(o.updated)
    if not updated or updated > Q.Now() + 300 then return nil end
    return { id = id, from = from, to = to, spell = spell, item = item, name = clean(o.name, 80), count = count,
        note = clean(o.note, NOTE_MAX), status = o.status, updated = updated }
end

function Q.OnOrderMessage(data, sender)
    local o = validOrder(data and data.o)
    if not o then return end
    -- Seuls le demandeur et l'artisan d'une commande en parlent ; une commande ne m'arrive que si elle me concerne
    local who, mine = key(sender), key(me())
    if who ~= key(o.from) and who ~= key(o.to) then return end
    if key(o.to) ~= mine and key(o.from) ~= mine then return end
    local old = orders()[o.id]
    if old and (old.updated or 0) >= o.updated then
        -- (accusé de réception de l'artisan : la commande est arrivée)
        if key(o.from) == mine and who == key(o.to) then old.delivered = true end
        return
    end
    o.at = old and old.at or Q.Now()
    o.delivered = true
    orders()[o.id] = o
    local what = Q.Safe(o.count .. ' × ' .. (o.name or ('recette ' .. tostring(o.spell or o.item or '?'))))
    if key(o.to) == mine and o.status == 'open' and not old then
        Q.Print('|cffffd100Nouvelle commande|r de ' .. Q.Safe(Quintessence.DisplayName(o.from)) .. ' : ' .. what
            .. (o.note and (' — « ' .. Q.Safe(o.note) .. ' »') or '') .. ' (onglet Craft → Commandes).')
        Q.ScheduleOrderNotice()
        -- Accusé de réception : le demandeur sait que la commande est arrivée
        if Q.comm and Q.comm.Send then send(o, o.from) end
    elseif key(o.from) == mine and old and old.status ~= o.status then
        Q.Print('Commande ' .. what .. ' : ' .. STATUSES[o.status] .. ' par ' .. Q.Safe(Quintessence.DisplayName(o.to)) .. '.')
    end
    if Q.UI and Q.UI.OnDataChanged then Q.UI.OnDataChanged() end
end

--- Membre qui se connecte : ses commandes pas encore reçues repartent.
function Q.ResendOrders(name)
    local who, n = key(name), 0
    for _, o in ipairs(Q.Orders()) do
        if key(o.to) == who and key(o.from) == key(me()) and o.status == 'open' and not o.delivered then
            send(o, o.to); n = n + 1
        end
    end
    return n
end

-- ---------------------------------------------------------------------------------------------- Liste de courses
local function owned(item)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    local ok, n = Q.Call(fn, item, true)
    return ok and tonumber(n) or 0
end
--- Composants pour `count` fabrications : { item, name, need, have, missing, crafters = recettes de la guilde qui le fabriquent }.
function Q.ShoppingList(entry, count)
    count = math.max(1, tonumber(count) or 1)
    local out = {}
    if type(entry) ~= 'table' or type(entry.reagents) ~= 'table' then return out end
    local byItem = {}
    for _, e in ipairs(Q.UI.BuildIndex().recipes) do if e.item and not byItem[e.item] then byItem[e.item] = e end end
    for _, r in ipairs(entry.reagents) do
        local need, have = (r.count or 1) * count, owned(r.item)
        out[#out + 1] = { item = r.item, name = r.name, need = need, have = have, missing = math.max(0, need - have), recipe = byItem[r.item] }
    end
    return out
end

-- ---------------------------------------------------------------------------------------------- Recettes manquantes
local professionOfLine
--- Nom (dans la langue du jeu) du métier d'une ligne du catalogue, lu à partir du sort du métier.
local function lineName(line)
    local spellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    local ok, name = Q.Call(spellName, line.skillSpell)
    return ok and type(name) == 'string' and name or nil
end
--- Recettes d'un métier (nom tel que la guilde l'a relevé) que personne dans la guilde ne connaît, triées par compétence.
function Q.MissingRecipes(profession)
    if type(Q.ALL_RECIPES) ~= 'table' or type(profession) ~= 'string' then return {} end
    professionOfLine = professionOfLine or {}
    local line
    for id, l in pairs(Q.ALL_RECIPES) do
        professionOfLine[id] = professionOfLine[id] or lineName(l)
        if professionOfLine[id] == profession then line = l end
    end
    if not line then return {} end
    local known = {}
    for _, e in ipairs(Q.UI.BuildIndex().recipes) do
        if e.profession == profession then
            if e.spell then known['s' .. e.spell] = true end
            if e.item then known['i' .. e.item] = true end
        end
    end
    local spellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    local out = {}
    for _, r in ipairs(line.recipes) do
        local spell, item, skill, source = r[1], r[2], r[3], r[4]
        if not known['s' .. spell] and not (item > 0 and known['i' .. item]) then
            local ok, name = Q.Call(spellName, spell)
            out[#out + 1] = { spell = spell, item = item > 0 and item or nil, skill = skill, source = source,
                name = ok and type(name) == 'string' and name or ('Sort #' .. spell) }
        end
    end
    table.sort(out, function(a, b) if a.skill ~= b.skill then return a.skill < b.skill end return a.name < b.name end)
    return out
end
Q.RECIPE_SOURCES = { T = 'maître de métier', V = 'marchand', D = 'butin', Q = 'quête', ['?'] = 'origine inconnue' }

function Q.InitOrders()
    if Quintessence.RegisterChannel then
        Q.comm = Quintessence:RegisterChannel('qcraft', function(data, sender)
            if type(data) == 'table' and data.t == 'order' then Q.Run('commande reçue', Q.OnOrderMessage, data, sender) end
        end)
    end
    if Quintessence.OnPresence then
        Quintessence:OnPresence(function(name, online) if online then Q.ResendOrders(name) end end)
    end
end

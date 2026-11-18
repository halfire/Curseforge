local _, Q = ...
--[[
  Aperçu 3D du personnage au centre de la fiche, comme l'Armurerie (0.20.0, T191).
    - Son propre personnage, ou un membre visible (cible, survol, groupe, raid) : SetUnit, apparence exacte du jeu.
    - Sinon : race et sexe relevés dans la fiche (SetCustomRace), déshabillé puis habillé de l'équipement relevé
      (TryOn 'item:id:enchant'). Visage, coiffure et couleur de peau ne sont pas relevés : apparence par défaut.
  Souris : glisser pour tourner, molette pour rapprocher, double-clic pour revenir de face.
  Aucun relevé ni envoi nouveau : seules les données déjà dans la fiche sont lues. Repli : blason de classe si le client
  n'a pas de DressUpModel (le module garde son ancien affichage).
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]
local M = {}
Q.Model = M

-- Jeton de race (deuxième retour de UnitRace) → numéro de race du jeu (SetCustomRace)
M.RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Undead = 5, Tauren = 6, Gnome = 7, Troll = 8 }
-- Emplacements portés par le mannequin (pas la munition 0) ; chemise et tabard compris, comme dans le jeu
M.SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }
local ZOOM_MAX, ZOOM_STEP = 0.75, 0.1

local function call(f, method, ...)
    if type(f) ~= 'table' and type(f) ~= 'userdata' then return nil end
    local fn = f[method]
    if type(fn) == 'function' then return pcall(fn, f, ...) end
end
local function secret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end

--- Unité du jeu qui montre ce personnage tel quel (soi, cible, survol, groupe, raid), sinon nil.
function M.UnitFor(key)
    local core = Quintessence
    if type(key) ~= 'string' or not core then return nil end
    -- Soi : toujours montrable (même sans UnitExists ni nom lu dans la liste de guilde)
    local me = core.Key and core.Key()
    if type(me) == 'string' and core.SameName(me, key) then return 'player' end
    local units = { 'target', 'mouseover', 'focus' }
    for i = 1, 4 do units[#units + 1] = 'party' .. i end
    for i = 1, 40 do units[#units + 1] = 'raid' .. i end
    for _, unit in ipairs(units) do
        local ok, exists = pcall(UnitExists or function() end, unit)
        if ok and exists == true then
            local full = core.UnitFullName and core.UnitFullName(unit)
            if type(full) == 'string' and not secret(full) and core.SameName(full, key) then
                local good, visible = pcall(UnitIsVisible or function() return false end, unit)
                if good and visible == true then return unit end
            end
        end
    end
    return nil
end

--- Le personnage affiché par un DressUpModel : { unit } ou { race, sex, items }. Renvoie aussi la raison d'un repli.
function M.Plan(key, c)
    local unit = M.UnitFor(key)
    if unit then return { unit = unit, exact = true } end
    if type(c) ~= 'table' then return nil end
    local race = M.RACE_IDS[c.race or '']
    if not race then return nil, 'race inconnue' end
    local items = {}
    local gear = {}
    for _, row in ipairs(type(c.equipment) == 'table' and c.equipment or {}) do
        if type(row) == 'table' and type(row.slot) == 'number' and type(row.item) == 'number' then gear[row.slot] = row end
    end
    for _, slot in ipairs(M.SLOTS) do
        local row = gear[slot]
        if row then items[#items + 1] = 'item:' .. row.item .. ':' .. (tonumber(row.enchant) or 0) end
    end
    -- UnitSex : 2 homme, 3 femme ; SetCustomRace : 0 homme, 1 femme
    return { race = race, sex = c.sex == 3 and 1 or 0, items = items, exact = false }
end

--- Cadre de l'aperçu : modèle, rotation à la souris, zoom à la molette. nil si le client n'a pas de DressUpModel.
function M.Create(parent, width, height)
    local ok, model = pcall(CreateFrame, 'DressUpModel', nil, parent)
    if not ok or type(model) ~= 'table' or type(model.SetUnit) ~= 'function' then return nil end
    model:SetSize(width, height)
    call(model, 'SetFacing', 0)
    call(model, 'EnableMouse', true)
    call(model, 'EnableMouseWheel', true)
    model.facing, model.zoom = 0, 0
    model:SetScript('OnMouseDown', function(self, button)
        if button ~= 'LeftButton' then return end
        local x = GetCursorPosition and GetCursorPosition()
        self.dragX = type(x) == 'number' and x or nil
    end)
    model:SetScript('OnMouseUp', function(self) self.dragX = nil end)
    model:SetScript('OnHide', function(self) self.dragX = nil end)
    model:SetScript('OnUpdate', function(self)
        if not self.dragX then return end
        local x = GetCursorPosition and GetCursorPosition()
        if type(x) ~= 'number' then return end
        self.facing = (self.facing + (x - self.dragX) * 0.02) % (2 * math.pi)
        self.dragX = x
        call(self, 'SetFacing', self.facing)
    end)
    model:SetScript('OnMouseWheel', function(self, delta)
        self.zoom = math.max(0, math.min(ZOOM_MAX, self.zoom + (tonumber(delta) or 0) * ZOOM_STEP))
        call(self, 'SetPortraitZoom', self.zoom)
    end)
    call(model, 'SetScript', 'OnDoubleClick', function(self)
        self.facing, self.zoom = 0, 0
        call(self, 'SetFacing', 0); call(self, 'SetPortraitZoom', 0)
    end)
    return model
end

-- Objet absent du cache du client : TryOn ne l'affiche pas encore ; il est demandé puis le mannequin rhabillé
local function cached(link)
    local id = tonumber(link:match('item:(%d+)'))
    if not id then return true end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(get) ~= 'function' then return true end
    local ok, name = pcall(get, id)
    if ok and name ~= nil then return true end
    if C_Item and type(C_Item.RequestLoadItemDataByID) == 'function' then pcall(C_Item.RequestLoadItemDataByID, id) end
    return false
end

--- Affiche ce personnage. Ne refait rien si c'est déjà lui avec le même équipement. Renvoie true si le modèle montre
--- quelque chose (sinon l'appelant garde le blason).
function M.Show(model, key, c)
    if not model then return false end
    local plan = M.Plan(key, c)
    if not plan then call(model, 'ClearModel'); model.signature = nil; return false end
    local signature = plan.unit and ('unit:' .. plan.unit .. ':' .. tostring(key))
        or (tostring(key) .. ':' .. plan.race .. ':' .. plan.sex .. ':' .. table.concat(plan.items, ','))
    if model.signature == signature then return true end
    model.signature, model.exact = signature, plan.exact
    model.facing, model.zoom = 0, 0
    if plan.unit then
        local ok = call(model, 'SetUnit', plan.unit)
        call(model, 'SetFacing', 0); call(model, 'SetPortraitZoom', 0)
        return ok ~= false
    end
    if not call(model, 'SetCustomRace', plan.race, plan.sex) then
        -- Client sans SetCustomRace : silhouette du joueur sans équipement serait trompeuse, on garde le blason
        model.signature = nil
        return false
    end
    call(model, 'Undress')
    local missing = false
    for _, link in ipairs(plan.items) do
        call(model, 'TryOn', link)
        if not cached(link) then missing = true end
    end
    call(model, 'SetFacing', 0); call(model, 'SetPortraitZoom', 0)
    -- Objets encore inconnus du client : un second habillage quand ils sont arrivés
    -- (trois fois au plus pour un même personnage)
    if model.retryFor ~= signature then model.retryFor, model.retries = signature, 0 end
    if missing and C_Timer and C_Timer.After and not model.retry and model.retries < 3 then
        model.retry, model.retries = true, model.retries + 1
        C_Timer.After(1.5, function()
            model.retry = nil
            if model.signature == signature then
                model.signature = nil
                Q.Run('aperçu 3D', M.Show, model, key, c)
            end
        end)
    end
    return true
end

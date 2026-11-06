local _, Q = ...
local pending, generation, failures = false, 0, 0
local mode = 'trade'
local function foreign()
    local api = C_TradeSkillUI or {}
    for _, key in ipairs({ 'IsTradeSkillLinked', 'IsTradeSkillGuild', 'IsNPCCrafting' }) do
        if type(api[key]) == 'function' then
            local ok, value = Q.Call(api[key])
            if not ok or value then return true end
        end
    end
    return false
end
Q.ForeignProfession = foreign
local function info()
    local api = C_TradeSkillUI or {}
    for _, fn in ipairs({ 'GetBaseProfessionInfo', 'GetChildProfessionInfo' }) do
        local ok, value = Q.Call(api[fn])
        if ok and type(value) == 'table' and type(value.professionName) == 'string' and value.professionName ~= '' then
            if type(value.skillLevel) == 'number' and type(value.maxSkillLevel) == 'number' then return value end
        end
    end
end
local function sort(recipes)
    table.sort(recipes, function(a,b)
        if (a.spell or 0) ~= (b.spell or 0) then return (a.spell or 0) < (b.spell or 0) end
        if (a.item or 0) ~= (b.item or 0) then return (a.item or 0) < (b.item or 0) end
        return (a.name or '') < (b.name or '')
    end)
end
-- Composants : liste { item = id, count = n, name = nom facultatif }, 12 au plus.
local MAX_REAGENTS = 12
local function reagentSignature(list)
    if type(list) ~= 'table' then return '' end
    local parts = {}
    for i, r in ipairs(list) do parts[i] = tostring(r.item) .. 'x' .. tostring(r.count) end
    return table.concat(parts, ',')
end
local function addReagent(list, item, count, name)
    item, count = tonumber(item), tonumber(count)
    if not item or item < 1 or item % 1 ~= 0 or not count or count < 1 or count % 1 ~= 0 or #list >= MAX_REAGENTS then return end
    list[#list + 1] = { item = item, count = count, name = type(name) == 'string' and name ~= '' and #name <= 100 and name or nil }
end
-- API moderne : nom de la catégorie du métier en jeu (C_TradeSkillUI.GetCategoryInfo).
local function modernCategory(api, categoryID)
    if type(categoryID) ~= 'number' or type(api.GetCategoryInfo) ~= 'function' then return nil end
    local ok, cat = Q.Call(api.GetCategoryInfo, categoryID)
    if ok and type(cat) == 'table' and type(cat.name) == 'string' and cat.name ~= '' and #cat.name <= 100 then
        return cat.name
    end
    return nil
end
-- API moderne : composants obligatoires du schéma (le premier objet possible de chaque emplacement).
local function modernReagents(schematic)
    if type(schematic) ~= 'table' or type(schematic.reagentSlotSchematics) ~= 'table' then return nil end
    local list = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if type(slot) == 'table' and slot.required ~= false and type(slot.reagents) == 'table' then
            local first = slot.reagents[1]
            local id = type(first) == 'table' and first.itemID
            -- Pas de recherche de nom ici : elle chargerait des objets et relancerait des événements de métier.
            if id then addReagent(list, id, slot.quantityRequired) end
        end
    end
    return #list > 0 and list or nil
end
-- API Classic : GetTradeSkillReagentInfo / GetCraftReagentInfo et leurs liens d'objet.
local function legacyReagents(craft, index)
    local count = craft and GetCraftNumReagents or GetTradeSkillNumReagents
    local infoFn = craft and GetCraftReagentInfo or GetTradeSkillReagentInfo
    local linkFn = craft and GetCraftReagentItemLink or GetTradeSkillReagentItemLink
    local ok, n = Q.Call(count, index)
    if not ok or type(n) ~= 'number' or n < 1 then return nil end
    local list = {}
    for j = 1, math.min(n, MAX_REAGENTS) do
        local good, name, _, needed = Q.Call(infoFn, index, j)
        local linkOK, link = Q.Call(linkFn, index, j)
        local id = linkOK and type(link) == 'string' and link:match('item:(%d+)')
        if good and id then addReagent(list, id, needed, name) end
    end
    return #list > 0 and list or nil
end
local function equal(a,b)
    if not a or a.skill ~= b.skill or a.maxSkill ~= b.maxSkill or #a.recipes ~= #b.recipes then return false end
    -- Canonical copies: never sort a persisted table merely to compare it.
    local old = {}; for i,r in ipairs(a.recipes) do old[i] = r end; sort(old)
    for i,r in ipairs(b.recipes) do
        local previous = old[i]
        if r.spell ~= previous.spell or r.item ~= previous.item or r.name ~= previous.name
            or (r.category or '') ~= (previous.category or '')
            or reagentSignature(r.reagents) ~= reagentSignature(previous.reagents) then return false end
    end
    return true
end
Q.ReagentSignature = reagentSignature
function Q.StoreProfession(name, profession)
    if type(name) ~= 'string' or name == '' or #name > 100 or foreign() then return false end
    if type(profession.skill) ~= 'number' or type(profession.maxSkill) ~= 'number' then return false end
    sort(profession.recipes)
    local c = Q.Identity()
    local old = c.professions[name]
    if equal(old, profession) then return false end
    profession.updated = Q.Tick(old and old.updated)
    c.professions[name] = profession; c.updated = Q.Tick(c.updated)
    Q.Changed(true); return true
end
local function legacy(scanMode)
    local craft = scanMode == 'craft'
    local getLine = craft and GetCraftDisplaySkillLine or GetTradeSkillLine
    local ok, name, skill, maxSkill = Q.Call(getLine)
    if not ok or type(name) ~= 'string' or name == '' then return nil end
    if craft then
        -- Classic GetCraftDisplaySkillLine may return only the name.
        -- GetCraftSkillLine returns the skill name/ranks on clients that expose it.
        if type(GetCraftSkillLine) == 'function' then
            local valid, line, rank, maximum = Q.Call(GetCraftSkillLine)
            if valid and type(line) == 'string' then name,skill,maxSkill = line,rank,maximum end
        end
        if not skill and GetNumSkillLines and GetSkillLineInfo then
            local valid, count = Q.Call(GetNumSkillLines)
            for i = 1, valid and count or 0 do
                local good, line, header, _, rank, _, _, maximum = Q.Call(GetSkillLineInfo,i)
                if good and not header and line == name then skill,maxSkill = rank,maximum; break end
            end
        end
    end
    if type(skill) ~= 'number' or type(maxSkill) ~= 'number' then return nil end
    local countOK, count = Q.Call(craft and GetNumCrafts or GetNumTradeSkills)
    if not countOK or type(count) ~= 'number' or count > 20000 then return nil end
    local recipes, seen = {}, {}
    local function add(recipe)
        local key = tostring(recipe.spell)..':'..tostring(recipe.item)..':'..(recipe.name or '')
        if not seen[key] then seen[key] = true; recipes[#recipes+1] = recipe end
    end
    -- Legacy filtered/collapsed lists are partial. Preserve previously learned recipes.
    local c = QuinteCraftDB.characters[Q.Key()]
    local previous = c and c.source == 'self' and c.professions[name]
    -- Les recettes visibles sont relues ensuite et remplacent celles du relevé précédent (composants à jour).
    local fresh = {}
    local currentCategory = nil
    for i = 1,count do
        local valid, recipeName, kind
        if craft then
            local _
            valid,recipeName,_,kind = Q.Call(GetCraftInfo,i)
        else valid,recipeName,kind = Q.Call(GetTradeSkillInfo,i) end
        if valid and recipeName and kind == 'header' then
            if recipeName ~= '' and #recipeName <= 100 and recipeName ~= 'Category' then
                currentCategory = recipeName
            end
        elseif valid and recipeName and kind ~= 'header' then
            local itemOK,itemLink = Q.Call(craft and GetCraftItemLink or GetTradeSkillItemLink,i)
            local spellOK,spellLink = Q.Call(craft and GetCraftRecipeLink or GetTradeSkillRecipeLink,i)
            local recipe = { name=recipeName, spell=spellOK and type(spellLink)=='string' and tonumber(spellLink:match('enchant:(%d+)') or spellLink:match('spell:(%d+)')) or nil,
                item=itemOK and type(itemLink)=='string' and tonumber(itemLink:match('item:(%d+)')) or nil,
                category=currentCategory,
                reagents=legacyReagents(craft, i) }
            fresh[tostring(recipe.spell)..':'..tostring(recipe.item)..':'..recipeName] = true
            add(recipe)
        elseif not valid then return nil end
    end
    -- Legacy filtered/collapsed lists are partial. Preserve previously learned recipes that are not visible.
    if previous then
        for _, r in ipairs(previous.recipes) do
            if not fresh[tostring(r.spell)..':'..tostring(r.item)..':'..(r.name or '')] then
                add({name=r.name,spell=r.spell,item=r.item,category=r.category,reagents=r.reagents})
            end
        end
    end
    return name,{skill=skill,maxSkill=maxSkill,recipes=recipes}
end
local function perform(token)
    if token ~= generation or foreign() then return end
    Q.debug.scans = Q.debug.scans + 1
    local api = C_TradeSkillUI or {}
    local profession = mode == 'trade' and info()
    if profession and type(api.GetAllRecipeIDs) == 'function' and type(api.GetRecipeInfo) == 'function' then
        local readyOK,ready = Q.Call(api.IsTradeSkillReady)
        if type(api.IsTradeSkillReady)=='function' and (not readyOK or not ready) then return Q.RetryScan() end
        local ok,ids = Q.Call(api.GetAllRecipeIDs)
        if not ok or type(ids) ~= 'table' or #ids > 20000 then return Q.RetryScan() end
        if #ids == 0 then return Q.RetryScan() end -- Loading/empty-filter ambiguity must not erase a known profession.
        local name = profession.professionName
        local result = { skill=profession.skillLevel,maxSkill=profession.maxSkillLevel,recipes={} }
        local index,missing,seen = 1,false,{}
        local function batch()
            if token ~= generation or foreign() then return end
            local current = info()
            if not current or current.professionName ~= name or current.skillLevel ~= result.skill or current.maxSkillLevel ~= result.maxSkill then return end
            local budget = debugprofilestop and debugprofilestop()
            for _ = 1,30 do
                -- 8 ms au plus par image : le reste attend l'image suivante (pas de saccade, même sur Retail)
                if budget and debugprofilestop() - budget > 8 then break end
                local id = ids[index]; if not id then break end; index=index+1
                local good,r = Q.Call(api.GetRecipeInfo,id)
                if not good or type(r) ~= 'table' or type(r.learned)~='boolean' then missing=true
                elseif r.learned and not seen[id] then
                    seen[id]=true
                    local schematicOK,schematic=Q.Call(api.GetRecipeSchematic,id,false)
                    local valid=schematicOK and type(schematic)=='table'
                    result.recipes[#result.recipes+1]={name=r.name,spell=id,item=valid and schematic.outputItemID or nil,
                        category=modernCategory(api, r.categoryID),
                        reagents=valid and modernReagents(schematic) or nil}
                    if not r.name then missing=true end
                end
            end
            if index <= #ids then C_Timer.After(0,function() Q.Run('lot de recettes',batch) end)
            elseif missing then Q.RetryScan()
            else failures=0; Q.StoreProfession(name,result) end
        end
        batch()
    else
        local name,result=legacy(mode)
        if name then failures=0; Q.StoreProfession(name,result) end
    end
end
function Q.RetryScan()
    if failures>=2 then return end
    failures=failures+1
    local token=generation
    C_Timer.After(1,function() if token==generation then Q.Run('nouvel essai métier',perform,token) end end)
end
-- Le jeu envoie aussi des événements de métier en tâche de fond : on ne scanne que fenêtre ouverte.
local open = {}
function Q.OnProfessionEvent(event)
    local scanMode = event:match('^CRAFT') and 'craft' or 'trade'
    if event == 'TRADE_SKILL_SHOW' or event == 'CRAFT_SHOW' then open[scanMode] = true
    elseif not open[scanMode] then return end
    Q.ScheduleScan(scanMode)
end
function Q.ScheduleScan(scanMode)
    mode=scanMode or mode
    if pending then return end
    pending=true;generation=generation+1
    local token=generation
    C_Timer.After(.5,function()
        if token~=generation then return end;pending=false;failures=0
        Q.Run('scan métier',perform,token)
    end)
end
function Q.CancelScan(scanMode)
    if scanMode then open[scanMode] = false end
    generation=generation+1;pending=false;failures=0
end
function Q.Debug()
    Q.Print('Métier : mode='..mode..', étranger='..tostring(foreign())..', scans='..Q.debug.scans..', changements='..Q.debug.changes)
    for _,key in ipairs({'GetBaseProfessionInfo','GetChildProfessionInfo'}) do
        local ok,value=Q.Call((C_TradeSkillUI or {})[key])
        if ok and type(value)=='table' then Q.Print(key..' : '..Q.Safe(value.professionName)..' '..tostring(value.skillLevel)..'/'..tostring(value.maxSkillLevel))
        else Q.Print(key..' : '..tostring(ok)..' / '..Q.Safe(value)) end
    end
    Q.Print('Addon : dossier='..Q.Safe(Q.name)..', version='..Q.version..', prêt='..tostring(Q.ready))
    if Q.sync then
        local state=Q.sync:Status()
        Q.Print('Synchro : '..(state.enabled and 'on' or 'off')..', file='..state.queued..', réassemblages='..state.buffers..', report='..state.deferred..', refus='..state.rejected)
    else Q.Print('Synchro : non démarrée') end
    for context,ms in pairs(Q.debug.slow) do Q.Print('Traitement lent : '..Q.Safe(context)..' '..ms..' ms') end
    for _,errorText in ipairs(Q.debug.errors) do Q.Print(Q.Safe(errorText)) end
end

local _, Q = ...
-- État par infobulle gardé dans une table de l'addon : on n'écrit jamais de champ sur les cadres de Blizzard
-- (cela contaminerait leur code sur Retail 12+).
local seen = setmetatable({}, { __mode = 'k' })
local seenRevision = setmetatable({}, { __mode = 'k' })
local hooked = setmetatable({}, { __mode = 'k' })
-- Ligne déjà composée par objet (false = personne), valable pour une révision des données : un survol ne refait ni
-- la liste des artisans ni les couleurs (appelé à chaque objet survolé).
local lines,linesRevision={},nil
local function cleared(t) seen[t]=nil end
local function line(id)
    if linesRevision~=Q.revision then lines,linesRevision={},Q.revision end
    local text=lines[id]
    if text==nil then
        local names=Q.ItemCrafters(id)
        text=false
        if #names>0 then
            -- 5 noms au plus, après le nombre : « fabriqué par 55 membres dont A, B, C, D, E »
            local display={}
            for i=1,math.min(5,#names) do display[#display+1]=Q.Colored(names[i]) end
            local count=#names..' membre'..(#names>1 and 's' or '')
            text='Quintessence : fabriqué par '..count..(#names>5 and ' dont ' or ' : ')..table.concat(display,', ')
        end
        lines[id]=text
    end
    return text
end
local function append(tooltip,id)
    if not Q.ready or Q.disabled or not tooltip or not tooltip.AddLine then return end
    if issecretvalue and issecretvalue(id) then return end
    if type(id)~='number' then return end
    if seen[tooltip]==id and seenRevision[tooltip]==Q.revision then return end
    if not hooked[tooltip] and tooltip.HookScript then
        local ok=Q.Call(tooltip.HookScript,tooltip,'OnTooltipCleared',cleared)
        hooked[tooltip]=ok or nil
    end
    local text=line(id)
    if not text then return end
    tooltip:AddLine(text,.44,.84,.70,true)
    seen[tooltip],seenRevision[tooltip]=id,Q.revision
end
local function fromData(tooltip,data) if type(data)=='table' then append(tooltip,data.id) end end
local function fromItem(tooltip)
    local ok,_,link=Q.Call(tooltip.GetItem,tooltip)
    if ok and type(link)=='string' then append(tooltip,tonumber(link:match('item:(%d+)'))) end
end
function Q.TooltipInit()
    local modern=TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if modern then
        local ok=Q.Call(TooltipDataProcessor.AddTooltipPostCall,Enum.TooltipDataType.Item,function(tooltip,data)
            Q.Run('infobulle moderne',fromData,tooltip,data)
        end)
        if ok then return end
    end
    if GameTooltip and GameTooltip.HookScript then
        Q.Call(GameTooltip.HookScript,GameTooltip,'OnTooltipSetItem',function(tooltip)
            Q.Run('infobulle Classic',fromItem,tooltip)
        end)
    end
end
Q.TooltipAppend=append

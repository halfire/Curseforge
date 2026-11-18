local _, A = ...
A.version, A.protocol = '0.7.1', 5
A.MAX_PLAYERS = 8
-- Messages : tables envoyées telles quelles par le canal temps réel du conteneur (LibSerialize, compressées, découpées
-- en trames de 255 octets), jamais de code Lua exécuté. Protocole 5 (0.6.0) : nouvelles règles et nouvel état.
-- Noms : ceux du conteneur. Sur WoW Forever, « Prénom Nom » sans royaume (uniques dans la région ; un chuchotement
-- vers « Prénom Nom-Royaume » est refusé) ; ailleurs « Nom-Royaume ».
local regional=function() return Quintessence.IsRegional and Quintessence.IsRegional() end
local Names -- bibliothèque du conteneur, cherchée une fois (A.Key est appelé pour chaque ligne de la liste de guilde)
function A.Key(name) Names=Names or LibStub('LibQuinteSync-1.0');return Names.CanonicalKey(tostring(name or '')) end
function A.Name(name)
    if type(name)~='string' or name=='' then return nil end
    -- (Forever : « Prénom Nom », « Prénom-Nom » ou « Prénom Nom-Royaume » → nom de la liste de guilde, sans royaume)
    if regional() then Names=Names or LibStub('LibQuinteSync-1.0');return Names.DisplayName(name) end
    local player,realm=name:match('^([^-]+)%-(.+)$')
    if player then return player..'-'..realm:gsub('%s','') end
    local realm=GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName():gsub('%s','')
    return name..'-'..realm
end
function A.Self() return A.Name(Quintessence.Key()) end
function A.Same(a,b) return A.Key(A.Name(a))==A.Key(A.Name(b)) end
function A.Safe(text) return tostring(text or ''):gsub('|','||') end

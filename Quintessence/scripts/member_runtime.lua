-- Édition membres : repérage des destinataires officiers, sans outils ni réception de leurs données.
local Core = Quintessence
local function secret(value) return issecretvalue and issecretvalue(value) end
local A = {}
Core.Announce = A
function A.IsOfficer() return false end
function A.OnlineOfficers()
    local result = {}
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return result end
    local ok, count = pcall(GetNumGuildMembers)
    if not ok or secret(count) or type(count) ~= 'number' then return result end
    for i = 1, count do
        local good, name, _, rank, _, _, _, _, _, online = pcall(GetGuildRosterInfo, i)
        if good and not secret(name) and not secret(rank) and not secret(online)
            and type(name) == 'string' and type(rank) == 'number' and rank <= 1 and online then
            result[#result + 1] = Core.CanonicalKey(name)
        end
    end
    table.sort(result)
    return result
end
function A.SenderIsOfficer(name)
    if secret(name) or type(name) ~= 'string' then return false end
    local wanted = Core.CanonicalKey(name)
    for _, key in ipairs(A.OnlineOfficers()) do if key == wanted then return true end end
    return false
end

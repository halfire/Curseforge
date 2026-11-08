-- Adaptation embarquée Quintessence ; origine GPL-3.0-or-later dans LICENSE et THIRD_PARTY.md.
local _, QC = ...
local function Embedded(...)
---@class SPFNamespace
local ns = select(2, ...)

-- English phrases are the keys, so a phrase with no translation reads as English.
---@type table<string, string>
local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L = L

end
Embedded(select(1, ...), QC.TravelEngine)

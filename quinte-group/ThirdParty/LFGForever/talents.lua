-- core/talents.lua
--
-- THE PLAYER'S OWN TALENT POINTS, PER TREE, FOR THE ACTIVE SPEC. Read when the
-- window opens (core/window.lua, OnShow) and kept in LFGF.talentPoints, which
-- the Ask to Join whisper's %talents% turns into a word (LFGF.TalentRole, called
-- from LFGF.AskToJoinMessage in core/main.lua). See
-- .claude/rules/player-talents.md.
--
-- ON FOREVER THIS IS C_Traits, NOT THE CLASSIC TALENT API. GetTalentInfo(tab, i)
-- and GetNumTalentTabs are not in the client (GlobalAPI.lua). A class has one
-- trait tree split into three groups -- Arms / Fury / Protection -- each with
-- its own point count, and this file reads those counts exactly the way
-- Blizzard's camelot talent window does
-- (Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua):
--
--   1. the active spec group, 1 or 2 (:99-105);
--   2. that group's build: GetCombatConfigIDForSpecGroup (:160-172). NOT
--      C_ClassTalents.GetActiveConfigID -- the camelot window chooses by spec
--      group, and the sources do not say the two always agree here;
--   3. the build's tree: GetConfigInfo(...).treeIDs[1]
--      (Blizzard_SharedTalentFrame.lua:1315-1323);
--   4. the tree's groups, then every group's points in ONE call, each answer
--      matched to its group by traitNodeGroupID and read as
--      currencyInfos[1].spent (:73-96, :310-323).
--
-- NO EVENTS, BY DECISION. Nothing listens for a talent change: the numbers are
-- read on each open, and a change made while the window stays open shows on
-- the next one. Five engine calls and a handful of small tables per open.
--
-- NO SECRET GUARDS, BECAUSE NOTHING HERE IS SECRET. None of the five entries
-- carries SecretReturns, a SecretWhen* predicate or HasRestrictions
-- (SpecializationInfoDocumentation.lua:41-56, :90-104;
-- SharedTraitsDocumentation.lua:200-215, :280-310). Their only annotation is
-- SecretArguments = "AllowedWhenUntainted", which restricts what an addon may
-- PASS, and everything passed here is a plain number the client just answered.
-- spec/harness/traits_spec.lua fails if the documentation ever says otherwise.

local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end

--- The points spent in each talent tree of the active spec, sorted by the
--- order Blizzard's talent window shows the trees in:
---
---   { { groupID = 11, name = "Arms", orderIndex = 0, spent = 31 }, ... }
---
--- or nil when there is nothing to read: no build for the active spec (a spec
--- never set up, or talent data not loaded yet just after login), or a build
--- the client knows no tree for.
---
--- NAMES ARE DISPLAY TEXT, localised by the client. Anything that decides by
--- tree keys on position or groupID instead -- as %talents% does.
---
--- A group the client gives no count for reads 0: Blizzard's own header shows
--- "0" in that case too (:320-321).
function LFGF.ReadTalentPoints()
	local specGroup = C_SpecializationInfo.GetActiveSpecGroup()
	local configID = specGroup and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(specGroup)
	if configID == nil then
		return nil
	end

	local configInfo = C_Traits.GetConfigInfo(configID)
	local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
	if treeID == nil then
		return nil
	end

	local displayInfos = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
	if displayInfos == nil or #displayInfos == 0 then
		return nil
	end

	local groupIDs = {}
	for _, displayInfo in ipairs(displayInfos) do
		table.insert(groupIDs, displayInfo.groupID)
	end

	-- Matched by ID, not by position: nothing documents that the answer comes
	-- back in the order asked, and Blizzard's caller does the same (:73-79).
	local spentByGroup = {}
	for _, groupInfo in ipairs(C_Traits.GetGroupCurrencyInfo(configID, groupIDs) or {}) do
		local currencyInfo = groupInfo.currencyInfos and groupInfo.currencyInfos[1]
		if currencyInfo then
			spentByGroup[groupInfo.traitNodeGroupID] = currencyInfo.spent
		end
	end

	local trees = {}
	for _, displayInfo in ipairs(displayInfos) do
		table.insert(trees, {
			groupID = displayInfo.groupID,
			name = displayInfo.displayName,
			orderIndex = displayInfo.orderIndex,
			spent = spentByGroup[displayInfo.groupID] or 0,
		})
	end
	table.sort(trees, function(a, b) return a.orderIndex < b.orderIndex end)
	return trees
end

--- THE WORD %talents% BECOMES, per class and tree, typed by the author. Keyed by
--- UnitClass's English class token (its SECOND return, classFilename, which
--- carries no secret predicate, UnitDocumentation.lua:925), and listed by the
--- tree's POSITION left to right -- the order ReadTalentPoints sorts by
--- orderIndex. Position rather than the raw orderIndex value, because the
--- sources do not say whether the game numbers the trees from 0 or from 1.
---
--- NEVER TRANSLATED, by the author's decision: these are the words a leader
--- reads in the whisper, whatever language the player's client is in. The
--- nine classes are the ones Blizzard's camelot talent UI knows
--- (Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentUtil.lua:1-11).
LFGF.TALENT_TREE_ROLES = {
	WARRIOR = { "arms", "fury", "prot" },
	PALADIN = { "holy", "prot", "ret" },
	HUNTER = { "bm", "mm", "surv" },
	ROGUE = { "assassination", "combat", "sub" },
	PRIEST = { "disc", "holy", "shadow" },
	SHAMAN = { "ele", "enh", "resto" },
	MAGE = { "arcane", "fire", "frost" },
	WARLOCK = { "affliction", "demonology", "destruction" },
	DRUID = { "balance", "feral", "resto" },
}

--- The word for the tree with the most points spent, or "" when there is
--- nothing to go on. `trees` is what ReadTalentPoints answers (sorted, so the
--- first index is the leftmost tree).
---
--- A tie goes to the LEFTMOST tied tree: only a strictly larger count
--- replaces the leader. No points spent, no talent data, a class without
--- words, or a winning tree past the class's last word: "" -- the author's
--- choice, so the rest of the whisper is sent as usual.
function LFGF.TalentRole(classFilename, trees)
	local words = classFilename and LFGF.TALENT_TREE_ROLES[classFilename]
	if words == nil or trees == nil then
		return ""
	end

	local best, bestSpent = nil, 0
	for position, tree in ipairs(trees) do
		if tree.spent > bestSpent then
			best, bestSpent = position, tree.spent
		end
	end
	return best and words[best] or ""
end

--- Read the points and keep them in LFGF.talentPoints, replacing whatever the
--- last open read -- including with nil, so an old spec's numbers are never
--- mistaken for the current ones. Called from the window's OnShow.
function LFGF.LoadTalentPoints()
	LFGF.talentPoints = LFGF.ReadTalentPoints()
end

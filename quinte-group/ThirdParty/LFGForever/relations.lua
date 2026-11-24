-- QuinteLFG -- core/relations.lua
--
-- Who the player KNOWS: a guildmate, or a friend (WoW or Battle.net). The
-- players list and the whisper log put a small icon before such a name --
-- friends-icon-tab-guildmates for a guildmate, friends-icon-tab-friends for a
-- friend -- and the players list also moves them up its boxes.
--
-- TWO ROUTES, because the two lists hold different things:
--   * a whisper carries the sender's GUID (the 12th CHAT_MSG_WHISPER field,
--     ChatInfoDocumentation.lua:2611), so RelationByGUID asks the GUID APIs --
--     the same ones Blizzard's own social code asks (SocialQueue.lua:199-204);
--   * a search result carries only NAMES -- LfgSearchResultPlayerInfo has no
--     GUID (LFGListInfoDocumentation.lua:1013-1027) -- so a lookup asks by
--     name.
--
-- GUILD WINS when someone is both: it is the narrower, more specific fact.
--
-- TWO OPTIONS, one per relation (core/settings.lua, read through
-- LFGF.MarkGuildmates / LFGF.MarkFriends in core/main.lua). OFF MEANS NO CALL:
-- with "Mark guild members" off nothing here touches IsInGuild, IsGuildMember or
-- C_GuildInfo; with "Mark friends" off nothing touches C_FriendList,
-- C_BattleNet or BNGetNumFriends. Every guild and friend call in the addon is
-- in this file, so gating them here is the whole of that promise. Friends are
-- off by default -- untested, because the beta has the friend system disabled.
--
-- NO EVENTS, BY DECISION. Nothing here listens for GUILD_ROSTER_UPDATE,
-- FRIENDLIST_UPDATE or a Battle.net change. The players list builds one lookup
-- per search and throws it away, so it is current on the next search; a whisper
-- row asks when it is drawn, so it is current when it is next drawn. What goes
-- stale in between is accepted -- see .claude/rules/relation-icons.md.
--
-- SECRET VALUES. Every lookup below is SecretArguments = "AllowedWhenUntainted"
-- -- Blizzard may pass a secret, an addon may not -- and names and GUIDs are
-- secret in chat-messaging lockdown (a dungeon, a raid, a restricted map). So
-- every argument is checked with canaccessvalue FIRST and, when it cannot be
-- read, the answer is "no relation". That FAILS CLOSED, unlike the filters,
-- which fail open: a filter that cannot check a listing lets it through, but an
-- icon CLAIMS something, and when it cannot be checked the honest answer is no
-- icon.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

LFGF.RELATION_GUILD = "guild"
LFGF.RELATION_FRIEND = "friend"

-- Both in the running client's atlas dump, on the same sheet as the addon's own
-- friends-icon-tab-quickJoin (AtlasInfo.lua:7420, :7419). The Friends UI's own
-- tab icons for these two lists, so the meaning comes with them.
local RELATION_ATLAS = {
	[LFGF.RELATION_GUILD] = "friends-icon-tab-guildmates",
	[LFGF.RELATION_FRIEND] = "friends-icon-tab-friends",
}

-- Blizzard's own words by default, from the retail Group Finder's member
-- tooltip (LFG_LIST_GUILD_MEMBER / LFG_LIST_FRIEND, GlobalStrings/enUS.lua
-- :13547, :13544), so they arrive localised; a language pack may replace them.
local RELATION_LABEL = {
	[LFGF.RELATION_GUILD] = L.RELATION_GUILD,
	[LFGF.RELATION_FRIEND] = L.RELATION_FRIEND,
}

-- 16: a line of GameFontNormal text is about that tall, and it is the size the
-- players list's role icons are drawn at. The atlases are 33x33 / 66x66, so
-- this is a scale down, not up.
local ICON_SIZE = 16
local ICON_TO_NAME_GAP = 2

-- The point on the ICON a name hangs off, per point the name was anchored by.
-- Only the left-edge points: a name is always laid out from its left.
local MIRRORED_POINT = {
	TOPLEFT = "TOPRIGHT",
	LEFT = "RIGHT",
	BOTTOMLEFT = "BOTTOMRIGHT",
}

-------------------------------------------------------
---------- Asking
-------------------------------------------------------

--- Is this character in the same game as the player?
---
--- Blizzard's own camelot friends list draws exactly this line before treating
--- a Battle.net game account as a character here (Camelot/FriendsFrame.lua
--- :2063). clientProgram rules out the app and other games; wowProjectID rules
--- out a character in another WoW flavour who happens to share a name.
local function IsCharacterInThisGame(gameAccountInfo)
	return gameAccountInfo ~= nil
		and gameAccountInfo.clientProgram == BNET_CLIENT_WOW
		and gameAccountInfo.wowProjectID == WOW_PROJECT_ID
end

--- The relation to the character with this GUID, or nil.
---
--- The whisper log's route. Three GUID calls, no loop:
---   IsGuildMember(guid)                    in the client dump, undocumented;
---                                          Blizzard's call, SocialQueue.lua:204
---   C_FriendList.IsFriend(guid)            FriendListDocumentation.lua:228
---   C_BattleNet.GetGameAccountInfoByGUID   BattleNetDocumentation.lua:208
---
--- IsFriend only when the WoW friend system is on, as Blizzard asks it
--- (SocialQueue.lua:199; its camelot friends list guards every WoW friend call
--- the same way, Camelot/FriendsFrame.lua:449, :1235).
---
--- Each half only while its option is on, read on every call: a whisper row
--- asks when it is drawn, so a row drawn after the option changed follows it.
function LFGF.RelationByGUID(guid)
	if guid == nil or not canaccessvalue(guid) then
		return nil
	end

	if LFGF.MarkGuildmates() and IsInGuild() and IsGuildMember(guid) then
		return LFGF.RELATION_GUILD
	end
	if LFGF.MarkFriends() then
		if C_FriendList.IsLegacyFriendSystemEnabled() and C_FriendList.IsFriend(guid) then
			return LFGF.RELATION_FRIEND
		end
		if IsCharacterInThisGame(C_BattleNet.GetGameAccountInfoByGUID(guid)) then
			return LFGF.RELATION_FRIEND
		end
	end
	return nil
end

--- The names of the Battle.net friends' characters in this game, as a set.
---
--- THE ONE COSTLY PART, which is why a lookup does it once rather than once per
--- name: every GetFriendGameAccountInfo call builds a table
--- (BattleNetDocumentation.lua:148-162). BNGetNumFriends is in the client dump
--- but undocumented; its first return is the total, as Blizzard's camelot
--- friends list reads it (Camelot/FriendsFrame.lua:771).
---
--- characterName is Nilable (:480): an account that is online in the app, or
--- offline, has none.
local function BattleNetCharacterNames()
	local names = {}
	local numFriends = BNGetNumFriends() or 0
	for friendIndex = 1, numFriends do
		for accountIndex = 1, C_BattleNet.GetFriendNumGameAccounts(friendIndex) do
			local info = C_BattleNet.GetFriendGameAccountInfo(friendIndex, accountIndex)
			if IsCharacterInThisGame(info) and info.characterName then
				names[info.characterName] = true
			end
		end
	end
	return names
end

local lookupProto = {}
local lookupMeta = { __index = lookupProto }

--- A snapshot of who the player knows, for ONE search.
---
--- Made when a search's results are sorted and thrown away with them. That is
--- what makes the Battle.net scan affordable and what stands in for the events
--- this file does not listen to: a friend added after a lookup was made is
--- seen by the next one.
---
--- THE OPTIONS ARE READ HERE TOO, once, so one search uses one answer and an
--- option switched off makes the lookup ask nothing of that API: inGuild and
--- legacyFriends stay false, the Battle.net scan is skipped, and ByName tests
--- those flags before any call.
function LFGF.NewRelationLookup()
	local markGuildmates, markFriends = LFGF.MarkGuildmates(), LFGF.MarkFriends()
	return setmetatable({
		inGuild = markGuildmates and IsInGuild(),
		legacyFriends = markFriends and C_FriendList.IsLegacyFriendSystemEnabled(),
		battleNetNames = markFriends and BattleNetCharacterNames() or {},
	}, lookupMeta)
end

--- The relation to the character with this name, or nil.
---
--- The players list's route. Matched EXACTLY as the search result spells the
--- name ("Firstname Surname" on this client); nothing in the sources shows how
--- the roster and friend list lookups normalise a name, so no guess is made.
---   C_GuildInfo.MemberExistsByName(name)   GuildInfoDocumentation.lua:235;
---                                          Blizzard's camelot Hardcore UI asks
---                                          it of a typed name, HardcoreUI.lua:64
---   C_FriendList.GetFriendInfo(name)       FriendListDocumentation.lua:90,
---                                          MayReturnNothing
function lookupProto:ByName(name)
	if name == nil or not canaccessvalue(name) then
		return nil
	end

	if self.inGuild and C_GuildInfo.MemberExistsByName(name) then
		return LFGF.RELATION_GUILD
	end
	if self.legacyFriends and C_FriendList.GetFriendInfo(name) then
		return LFGF.RELATION_FRIEND
	end
	if self.battleNetNames[name] then
		return LFGF.RELATION_FRIEND
	end
	return nil
end

--- Ask the server for the guild roster.
---
--- Blizzard asks only when a guild-related window opens (CommunitiesFrame.lua
--- :290, MailFrame.lua:108, Blizzard_Calendar.lua:4163), so a player who never
--- opens one may have no roster at all -- and MemberExistsByName would then
--- find nobody. core/window.lua calls this when the window opens. It is a
--- REQUEST, not a listener: the answer is used by the next search.
---
--- C_GuildInfo.GuildRoster takes nothing and carries no restriction
--- (GuildInfoDocumentation.lua:166-168).
---
--- Nothing at all -- not even IsInGuild -- while "Mark guild members" is off.
function LFGF.RequestGuildRoster()
	if LFGF.MarkGuildmates() and IsInGuild() then
		C_GuildInfo.GuildRoster()
	end
end

-------------------------------------------------------
---------- The icon
-------------------------------------------------------

local function ShowIconTooltip(self)
	local label = self.relation and RELATION_LABEL[self.relation]
	if not label then
		return
	end
	LFGF.ShowTextTooltip(self, label, true)
end

--- Build the icon for one row. Hidden until LayOutRelationIcon shows it.
---
--- The addon's shared tooltip icon (LFGF.CreateTooltipIcon, core/main.lua):
--- it takes the mouse's movement for its tooltip and lets clicks through, so a
--- right-click on the icon lands on the row beneath and still opens the row's
--- menu. Moving onto it is leaving the row, so the row's own hover (tooltip,
--- highlight) gives way to the icon's while the mouse is over it.
function LFGF.CreateRelationIcon(row)
	return LFGF.CreateTooltipIcon(row, ICON_SIZE, ShowIconTooltip)
end

--- Put the icon where the name begins and the name after it -- or, with no
--- relation, put the name back where it begins and hide the icon.
---
--- The anchor passed in is the one the name would have had. The name is
--- re-anchored on EVERY call, both ways, because rows are pooled: one frame
--- shows a guildmate and then a stranger, and a one-way rule would leave the
--- stranger's name indented past a hidden icon.
---
--- Returns the width the icon takes out of the name's line (0 when there is
--- none), so the caller can clamp the name that much shorter.
function LFGF.LayOutRelationIcon(icon, name, relation, point, relativeTo, relativePoint, x, y)
	local atlas = relation and RELATION_ATLAS[relation]
	name:ClearAllPoints()
	icon.relation = atlas and relation or nil

	if not atlas then
		icon:Hide()
		name:SetPoint(point, relativeTo, relativePoint, x, y)
		return 0
	end

	icon.Icon:SetAtlas(atlas)
	icon:ClearAllPoints()
	icon:SetPoint(point, relativeTo, relativePoint, x, y)
	icon:Show()
	name:SetPoint(point, icon, MIRRORED_POINT[point], ICON_TO_NAME_GAP, 0)
	return ICON_SIZE + ICON_TO_NAME_GAP
end

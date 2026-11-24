-- QuinteLFG -- core/recentparty.lua
--
-- The last five players who joined your party, newest first, because
-- Blizzard's Recent Allies can take a while to list them. Each keeps their
-- name, class, level and GUID, the zone you were in and when they joined. The
-- Player ratings tab (core/playerratings.lua) puts the ones missing from
-- Blizzard's first ten rows on top, so they can be rated at once.
--
-- The author's decisions (2026-11-13), .claude/rules/player-ratings.md, "The
-- last five party members":
--   * first in, first out: a sixth join pushes the oldest out;
--   * anyone new in your party counts, the members of a party you join and
--     the ones already there when you log in or /reload too; parties only;
--   * a player who joins again moves to the newest place;
--   * kept in memory, saved PER CHARACTER, brought back at load;
--   * recorded only while the Player ratings setting is on.
-- It also warns in chat when a player you rated 1 star joins your party (the
-- author's decisions, 2026-11-14, below).
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

local KEY = "recentPartyMembers"
local MAX_MEMBERS = 5

-------------------------------------------------------
---------- The list
-------------------------------------------------------
--- In memory, newest first: { name, class, level, guid, zone, time }, any of
--- them but the name possibly nil. Brought back from the saved table on
--- ADDON_LOADED; every change is written back at once.
local members = {}
local restored = false

local function Copy(member)
	return {
		name = member.name, class = member.class, level = member.level,
		guid = member.guid, zone = member.zone, time = member.time,
	}
end

local function IndexOf(key)
	for index, member in ipairs(members) do
		if LFGF.PlayerKey(member.name) == key then
			return index
		end
	end
	return nil
end

--- The list, newest first, as fresh copies: changing them changes nothing.
--- Empty before ADDON_LOADED.
function LFGF.RecentPartyMembers()
	local copies = {}
	for index, member in ipairs(members) do
		copies[index] = Copy(member)
	end
	return copies
end

local function Save()
	local copies = LFGF.RecentPartyMembers()
	LFGF.SaveValue(KEY, copies)
	EventRegistry:TriggerEvent(LFGF.EVENT_RECENT_PARTY_MEMBERS_CHANGED)
end

-------------------------------------------------------
---------- Bringing it back
-------------------------------------------------------
-- The saved table is a file on disk, so every field is checked, and a field
-- that fails is left out rather than the entry. A string holding "|" is left
-- out too: it would start an escape where it is shown. Nothing is written
-- back on load (core/db.lua, no repair on load).

local function SavedString(value)
	if type(value) == "string" and value ~= "" and not string.find(value, "|", 1, true) then
		return value
	end
	return nil
end

local function SavedMember(record)
	if type(record) ~= "table" then
		return nil
	end
	local name = SavedString(record.name)
	if name == nil or LFGF.PlayerKey(name) == nil then
		return nil
	end
	local level = record.level
	if not LFGF.IsFiniteNumber(level) or level <= 0 then
		level = nil
	end
	local time = record.time
	if not LFGF.IsFiniteNumber(time) then
		time = nil
	end
	return {
		name = name, class = SavedString(record.class), level = level,
		guid = SavedString(record.guid), zone = SavedString(record.zone), time = time,
	}
end

--- The saved list, checked: broken entries and repeats of a player left out
--- (the first one kept), five at most.
local function Restore()
	local list = {}
	local saved = LFGF.SavedValue(KEY)
	if type(saved) ~= "table" then
		return list
	end
	local seen = {}
	for _, record in ipairs(saved) do
		local member = SavedMember(record)
		local key = member and LFGF.PlayerKey(member.name)
		if key and not seen[key] then
			seen[key] = true
			table.insert(list, member)
			if #list == MAX_MEMBERS then
				break
			end
		end
	end
	return list
end

-------------------------------------------------------
---------- Noticing a join
-------------------------------------------------------
-- No event names who joined: GROUP_ROSTER_UPDATE carries nothing
-- (PartyInfoDocumentation.lua). So each look reads the party's own units,
-- party1 to partyN, as Blizzard's own party loop walks them (`for i = 1,
-- GetNumSubgroupMembers() do local unit = "party" .. i`,
-- Blizzard_CooldownBroadcaster.lua), and compares them with the last look.
--
-- A PARTY MEMBER'S NAME IS READABLE: UnitNameUnmodified, UnitGUID and
-- UnitClass are SecretWhenUnitIdentityRestricted, which keeps a party or raid
-- member's identity readable (SecretPredicatesDocumentation.lua); UnitLevel has
-- no secret predicate. Each value is still read through LFGF.Readable, and one
-- that cannot be read is left out.

--- The players in your party at the last look, by LFGF.PlayerKey; nil when
--- there was no look since the list came back or recording started. The first
--- look then moves nobody already listed: a /reload in the same party, or
--- turning Player ratings on again, changes no one's place or time.
local present = nil

--- True from the list coming back, or recording starting, until a look reads
--- every party member's name. Nobody added meanwhile is warned about: they
--- were in the party before the addon looked (a login, a /reload, turning
--- Player ratings on), not a join. At a login the names can arrive only by
--- PLAYER_LOGIN, after the first look, which is why the first look alone does
--- not end it.
local settling = true

--- One party unit, or nil while its name is not known yet. A player who has
--- just joined can read as UNKNOWNOBJECT until the client has their data, as
--- Blizzard's raid frames know (Blizzard_RaidUI.lua, `unitName ~=
--- UNKNOWNOBJECT`); UNIT_NAME_UPDATE then brings a new look.
---
--- THE SECOND RETURN OF UnitNameUnmodified IS THE SURNAME on this client,
--- joined to the first name by a space (Camelot/NameUtil.lua,
--- GetUnmodifiedUnitFullName; the separator, LuaEnum.lua). A level of 0 is
--- the client not knowing it yet.
local function ReadMember(unit)
	local first, surname = UnitNameUnmodified(unit)
	first = LFGF.Readable(first, nil)
	if first == nil or first == "" or first == UNKNOWNOBJECT then
		return nil
	end
	surname = LFGF.Readable(surname, nil)
	local name = first
	if surname ~= nil and surname ~= "" then
		name = first .. " " .. surname
	end
	if LFGF.PlayerKey(name) == nil then
		return nil
	end

	local _, class = UnitClass(unit)
	local level = LFGF.Readable(UnitLevel(unit), nil)
	if level ~= nil and level <= 0 then
		level = nil
	end
	return {
		name = name,
		class = LFGF.Readable(class, nil),
		level = level,
		guid = LFGF.Readable(UnitGUID(unit), nil),
	}
end

--- Your zone at the time of a join, from GetRealZoneText (ZoneScriptDocumentation.lua),
--- or nil.
local function Zone()
	local zone = LFGF.Readable(GetRealZoneText(), nil)
	if zone == "" then
		return nil
	end
	return zone
end

--- Class, level and GUID of a player still in the party, kept fresh in place:
--- no move, and the join's zone and time stay. Answers whether anything
--- changed.
local function Refresh(listed, member)
	local changed = false
	for _, field in ipairs({ "class", "level", "guid" }) do
		if member[field] ~= nil and member[field] ~= listed[field] then
			listed[field] = member[field]
			changed = true
		end
	end
	return changed
end

-------------------------------------------------------
---------- A warning when a player you rated 1 star joins
-------------------------------------------------------
-- THE AUTHOR'S DECISIONS (2026-11-14), .claude/rules/player-ratings.md: one
-- chat line per player you rated 1 star who joins your party, "Arin Vale
-- joined your party. You rated the player 1 star *." in the author's words,
-- the name in the 1-star strip's red, the stars' own gold art after "1 star";
-- on every real join, with no sound, parties only (this file's join).

-- The rating stars' gold art (core/playerratings.lua; AtlasInfo.lua, 40 x 36)
-- at the height of Blizzard's own small chat icons, 12 (TimerunningUtil.AddSmallIcon,
-- Blizzard_TimerunningUtil.lua:7-9), and 13 wide to keep its 10:9 shape. Atlas
-- markup in a chat line is Blizzard's own practice too: a Recent Allies icon
-- after a player link (Mainline/ChatFrameOverrides.lua:621).
local STAR_ATLAS = "auctionhouse-icon-favorite"
local STAR_MARKUP_WIDTH, STAR_MARKUP_HEIGHT = 13, 12

--- Say so in chat when `member` is a player you rated 1 star.
---
--- The name is the client's own (ReadMember), and a character's name holds no
--- |, so it needs no escaping. RED_FONT_COLOR is generated at load from the
--- client's colour database, so it is read here, and a missing one leaves the
--- name plain.
local function WarnIfOneStar(member)
	if LFGF.PlayerRating(LFGF.PlayerKey(member.name)) ~= 1 then
		return
	end
	local name = member.name
	if RED_FONT_COLOR then
		name = RED_FONT_COLOR:WrapTextInColorCode(name)
	end
	LFGF.Print(L.PARTY_ONE_STAR_JOINED_FORMAT:format(name,
		CreateAtlasMarkup(STAR_ATLAS, STAR_MARKUP_WIDTH, STAR_MARKUP_HEIGHT)))
end

--- Look at the party, add whoever is new, and warn about each of them you
--- rated 1 star (WarnIfOneStar), once settled. Nothing while the list is not
--- back yet, while Player ratings is off, or in a raid (parties only, by
--- decision; a raid leaves the last look as it was, so a raid turned back into
--- a party adds only who is new). An answer that cannot be read is no look.
local function Look()
	if Quintessence.GuildStatus() ~= "ok" then return end
	if not restored then
		return
	end
	if not LFGF.ShowPlayerRatings() then
		present = nil
		settling = true
		return
	end
	if LFGF.Readable(IsInRaid(), nil) ~= false then
		return
	end
	local count = LFGF.Readable(GetNumSubgroupMembers(), nil)
	if count == nil then
		return
	end

	local first = present == nil
	local seen = {}
	local changed = false
	local zone, now, joined = nil, nil, false
	local joins, unread = {}, false
	-- From the last slot to the first, each new one on top: party1 ends first.
	for slot = count, 1, -1 do
		local member = ReadMember("party" .. slot)
		if not member then
			unread = true
		else
			local key = LFGF.PlayerKey(member.name)
			seen[key] = true
			local index = IndexOf(key)
			if (present and present[key]) or (first and index) then
				if index and Refresh(members[index], member) then
					changed = true
				end
			else
				if not joined then
					zone, now, joined = Zone(), GetServerTime(), true
				end
				if index then
					table.remove(members, index)
				end
				member.zone, member.time = zone, now
				table.insert(members, 1, member)
				changed = true
				if not settling then
					table.insert(joins, 1, member)
				end
			end
		end
	end
	while #members > MAX_MEMBERS do
		table.remove(members)
	end
	present = seen
	if not unread then
		settling = false
	end
	-- Each join, the first party slot first, as the list puts them.
	for _, member in ipairs(joins) do
		WarnIfOneStar(member)
	end

	if changed then
		Save()
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_NAME_UPDATE")
frame:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_NAME_UPDATE" then
		-- Every unit's name arrives here (UnitDocumentation.lua, UNIT_NAME_UPDATE
		-- names it); only the party's own units matter.
		unit = LFGF.Readable(unit, nil)
		if unit == nil or not string.find(unit, "^party%d$") then
			return
		end
	end
	Look()
end)

-- Turned on: look at once, so the party you are in is added. Turned off: the
-- last look is forgotten; the list is kept.
EventRegistry:RegisterCallback(LFGF.EVENT_PLAYER_RATINGS_CHANGED, Look, frame)

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	members = Restore()
	present = nil
	restored = true
	Look()
end)

-- At login the party's names may only be known by PLAYER_LOGIN. Load callbacks
-- run in no promised order, so Look waits for the list itself.
EventUtil.ContinueOnPlayerLogin(Look)

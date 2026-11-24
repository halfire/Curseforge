-- QuinteLFG -- core/activitynames.lua
--
-- DATA ONLY: the English names of the Group Finder's dungeons and raids, by
-- activity ID. The Invite whisper's %dungeon_en% sends these on a client in
-- another language (LFGF.InviteWhisperMessage, core/main.lua), so a player can
-- invite in English whatever their game's language.
--
-- WHY A TABLE: no Blizzard API answers an English name on a non-English
-- client. C_LFGList.GetActivityInfoTable's fullName and shortName are the
-- client's own (LFGListInfoDocumentation.lua, GroupFinderActivityInfo), and
-- nothing else in the documentation or the client dump returns English text.
--
-- WHERE IT CAME FROM: dumped from the author's English (enUS) client on
-- 2026-11-16, Forever 1.60.1: every activity of the Dungeons (2) and Raids
-- (114) categories, by C_LFGList.GetActivityInfoTable. Each name is the one an
-- English client's players list shows, LFGUtil_GetActivityInfoName's rule:
-- the short name when there is one, else the full one ("Scarlet Cathedral",
-- not "Scarlet Monastery - Cathedral"). Other categories (quests,
-- battlegrounds, custom) are not here, by the author's decision: they keep the
-- client's names.
--
-- WHAT THE GROUP FINDER OFFERED THEN (GetAvailableActivities): every dungeon
-- below except Stormwind Stockades (802), Demon Fall Canyon (1607) and
-- Karazhan Crypts (1693), and no raid at all. They are kept, so a raid phase
-- or a returning dungeon needs no new dump. An ID the Group Finder never
-- offers is never looked up.
--
-- WHEN FOREVER ADDS A DUNGEON, this file goes stale for it: the whisper then
-- sends that one in the client's language until the table is dumped again.
-- How: .claude/rules/dungeon-en-placeholder.md, *Refreshing the table*.

local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end

LFGF.ENGLISH_ACTIVITY_NAMES = {
	-- Dungeons (category 2)
	[796] = "Wailing Caverns",
	[797] = "Scholomance",
	[798] = "Ragefire Chasm",
	[799] = "Deadmines",
	[800] = "Shadowfang Keep",
	[801] = "Blackfathom Deeps",
	[802] = "Stormwind Stockades",
	[803] = "Gnomeregan",
	[804] = "Razorfen Kraul",
	[805] = "Scarlet Graveyard",
	[806] = "Razorfen Downs",
	[807] = "Uldaman",
	[808] = "Zul'Farrak",
	[809] = "Maraudon",
	[810] = "Sunken Temple",
	[811] = "Blackrock Depths",
	[812] = "Lower Blackrock Spire",
	[813] = "Dire Maul (East)",
	[814] = "Dire Maul (West)",
	[815] = "Dire Maul (North)",
	[816] = "Stratholme (Main Gate)",
	[827] = "Scarlet Armory",
	[828] = "Scarlet Cathedral",
	[829] = "Scarlet Library",
	[837] = "Upper Blackrock Spire",
	[1603] = "Stratholme (Service Gate)",
	[1607] = "Demon Fall Canyon",
	[1693] = "Karazhan Crypts",
	[1978] = "The Shaper's Terrace",
	[1979] = "Blackmaw Hold",
	[1980] = "Alcaz Prison",
	[1981] = "Excavation Site: Wetlands",
	[1982] = "Ruins of Lordaeron",
	[1983] = "City of Dalaran",
	[1984] = "Hall of Thanes",
	[1985] = "The Drowned City",
	[1986] = "Krol'dok Stronghold",

	-- Raids (category 114). Some names appear twice, under two activity IDs.
	[836] = "Zul'Gurub",
	[838] = "Onyxia's Lair",
	[839] = "Molten Core",
	[840] = "Blackwing Lair",
	[841] = "Naxxramas",
	[842] = "Ahn'Qiraj Ruins",
	[843] = "Ahn'Qiraj Temple",
	[1604] = "Blackfathom Deeps",
	[1605] = "Gnomeregan",
	[1606] = "Sunken Temple",
	[1608] = "Storm Cliffs",
	[1609] = "The Tainted Scar",
	[1610] = "Nightmare Grove",
	[1611] = "The Crystal Vale",
	[1612] = "Onyxia's Lair",
	[1613] = "Molten Core",
	[1614] = "Ahn'Qiraj Temple",
	[1615] = "Ahn'Qiraj Ruins",
	[1710] = "Scarlet Enclave",
}

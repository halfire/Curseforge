-- QuinteLFG -- core/db.lua
--
-- THE SAVED TABLES: every key LFG Forever keeps on disk, its default, and the
-- four helpers every other file reads and writes them through. Loads SECOND,
-- after core/locale.lua, so every later file can read a default at file scope.
--
--   QuinteLFGDB      ## SavedVariables               account-wide
--   QuinteLFGCharDB  ## SavedVariablesPerCharacter   per character
--
-- The client assigns both before the addon's ADDON_LOADED, or leaves them nil
-- on a first install (and on a character's first load); core/settings.lua
-- creates them then, through LFGF.SavedTable.
--
-- ONE OWNER. No other file names QuinteLFGDB or QuinteLFGCharDB: they read
-- with LFGF.SavedValue / LFGF.SavedSetting and write with LFGF.SaveValue, so a
-- key is spelled once, here (spec/QuinteLFG/db_spec.lua holds both). The keys
-- are the ones 0.20.0 writes, unchanged: a renamed key would lose the
-- player's value, so renaming one needs a migration, and there are none.
--
-- NO REPAIR ON LOAD, by the author's decision (2026-10-11). A saved value of
-- the wrong type stays on disk; each reader falls back when it reads it, as
-- before. .claude/rules/saved-variables-db.md

local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end

local ACCOUNT, CHARACTER = "account", "character"


--- Every key on disk, in the order the settings page shows its settings, then
--- the state the addon keeps by itself. Fields:
---   key       the name in the saved table
---   scope     "account" (QuinteLFGDB) or "character" (QuinteLFGCharDB)
---   variable  the Blizzard Settings variable, for the eleven that are settings
---             (prefixed with the addon's name: variables share one registry
---             across every addon, Blizzard_Setting.lua:390-395)
---   type      the Lua type a usable value has
---   default   what a reader answers when nothing usable is saved, and what
---             Settings.RegisterAddOnSetting writes for a missing setting
---   min       (whisperLogSize only) the smallest usable number
LFGF.SAVED_KEYS = {
	-- How many received whispers the Whispers tab keeps.
	{ key = "whisperLogSize", scope = ACCOUNT, variable = "QUINTELFG_WHISPER_LOG_SIZE",
		type = "number", default = 200, min = 1 },

	-- Ask to Join: whisper the leader with the message, or open a whisper box.
	{ key = "askToJoinAutoWhisper", scope = ACCOUNT, variable = "QUINTELFG_ASK_TO_JOIN_AUTO_WHISPER",
		type = "boolean", default = false },
	-- The Ask to Join whisper, PER CHARACTER since 0.11.0. Four placeholders are
	-- filled in when the button is clicked (LFGF.AskToJoinMessage, core/main.lua):
	-- %class%, %level%, %talents% and %role%, rather than string.format's %s and
	-- %d, because the player edits this text and a stray % must not be read as a
	-- format directive. No addon tag: the leader reads a greeting from a player,
	-- not an advert. %role% (0.20.0-dev.2) is not in the default, by the author's
	-- decision: players add it themselves (.claude/rules/role-placeholder.md).
	{ key = "askToJoinMessage", scope = CHARACTER, variable = "QUINTELFG_ASK_TO_JOIN_MESSAGE",
		type = "string", default = "Bonjour ! %class% niveau %level%. Une place dans ton groupe ?" },

	-- Invite: whisper the invited player with the message (0.12.0-dev.1).
	{ key = "inviteAutoWhisper", scope = ACCOUNT, variable = "QUINTELFG_INVITE_AUTO_WHISPER",
		type = "boolean", default = false },
	-- The Invite whisper, per character from the start, %dungeon% filled in from
	-- the player's own listing or the ticked activities (LFGF.InviteWhisperMessage,
	-- core/main.lua; .claude/rules/invite-whisper.md). The wording is the author's.
	-- The default names them in English (%dungeon_en%), by the author's decision:
	-- Forever is mostly English-speaking. core/settings.lua moves a character
	-- still holding the older "%dungeon%" default to this one
	-- (.claude/rules/dungeon-en-placeholder.md).
	{ key = "inviteMessage", scope = CHARACTER, variable = "QUINTELFG_INVITE_MESSAGE",
		type = "string", default = "Bonjour ! Tu veux venir pour %dungeon% ?" },

	-- SHOW ALL LEVEL ACTIVITIES: when on, the filter panel offers and searches
	-- every activity, not only those whose suggested level range holds the
	-- player's level (LFGF.Activities, core/filterpanel.lua). OUR OWN SETTING,
	-- not Blizzard's CVar disableSuggestedLevelActivityFilter, which this addon
	-- neither reads nor writes: writing it from addon code would leave a value
	-- set by tainted code in Blizzard's CVarCallbackRegistry cache
	-- (CvarUtil.lua:132-138), which their finder then reads. Off by default, like
	-- the CVar (CVars.lua:625). .claude/rules/level-range-filter.md
	{ key = "showAllLevelRanges", scope = ACCOUNT, variable = "QUINTELFG_SHOW_ALL_LEVEL_RANGES",
		type = "boolean", default = false },
	-- SHOW SUGGESTED LEVEL RANGES: each activity menu row ends in its range,
	-- "Deadmines (17 - 24)" (LFGF.ActivityMenuText, core/filterpanel.lua).
	{ key = "showActivityLevelRanges", scope = ACCOUNT, variable = "QUINTELFG_SHOW_ACTIVITY_LEVEL_RANGES",
		type = "boolean", default = true },

	-- THE GUILD AND FRIEND MARKS (core/relations.lua). Off means no icon, no
	-- moving up, and no call to that API at all, in both lists. Friends were OFF
	-- and labelled Experimental until 0.21.0-dev.7, while the friend system was
	-- disabled in the Forever beta; confirmed working in the client on
	-- 2026-10-12, now ON by default. A new default only reaches players with
	-- nothing saved: every older file holds false, and keeps it, by the
	-- author's decision (.claude/rules/relation-icons.md).
	{ key = "markGuildmates", scope = ACCOUNT, variable = "QUINTELFG_MARK_GUILDMATES",
		type = "boolean", default = true },
	{ key = "markFriends", scope = ACCOUNT, variable = "QUINTELFG_MARK_FRIENDS",
		type = "boolean", default = true },
	-- SORT PLAYERS BY: the order of the players list's Players box, one of
	-- LFGF.PLAYER_SORT_ORDERS (core/main.lua), saved by name. "newest" is the
	-- order the list always kept before the setting existed.
	-- .claude/rules/player-sort-order.md
	{ key = "playerSortOrder", scope = ACCOUNT, variable = "QUINTELFG_PLAYER_SORT_ORDER",
		type = "string", default = "newest" },

	-- THE MINIMAP BUTTON (core/minimap.lua). The addon compartment entry is
	-- declared in the TOC and is not governed by this: it is Blizzard's menu.
	{ key = "showMinimapButton", scope = ACCOUNT, variable = "QUINTELFG_SHOW_MINIMAP_BUTTON",
		type = "boolean", default = false },
	-- PLAYER RATINGS: the window's third tab, listing Blizzard's Recent Allies
	-- with one to three stars each (core/playerratings.lua), the marks in the
	-- lists, the rating order, the "Do you want to rate them?" chat line and
	-- the last party members list. ON by default, by the author's decision. A
	-- saved off stays off. .claude/rules/player-ratings.md
	{ key = "showPlayerRatings", scope = ACCOUNT, variable = "QUINTELFG_SHOW_PLAYER_RATINGS",
		type = "boolean", default = true },

	-- The Filters tab as last searched, reset or applied from My filters
	-- (core/main.lua, LFGF.SavedFilters; .claude/rules/saved-filters.md).
	{ key = "filters", scope = ACCOUNT, type = "table" },
	-- My filters, in save order (core/main.lua, LFGF.MyFilters; my-filters.md).
	{ key = "myFilters", scope = ACCOUNT, type = "table" },
	-- The Filters tab sections the player collapsed, a set of section keys
	-- (core/main.lua, LFGF.CollapsedFilterSections; added in 0.22.0-dev.2,
	-- .claude/rules/collapsible-filter-sections.md).
	{ key = "collapsedFilterSections", scope = ACCOUNT, type = "table" },
	-- The players' ratings, one to three stars each, keyed by "Firstname Surname"
	-- (core/main.lua, LFGF.PlayerRating; added in 1.5.0-dev.5,
	-- .claude/rules/player-ratings.md). Kept when the Player ratings setting is
	-- off, and when the player is no longer a recent ally.
	{ key = "playerRatings", scope = ACCOUNT, type = "table" },
	-- The last five players who joined your party, newest first, each with
	-- their name, class, level, GUID, your zone and the time they joined
	-- (core/recentparty.lua; added in 1.5.0-dev.14,
	-- .claude/rules/player-ratings.md). Per character, by the author's
	-- decision: Blizzard's Recent Allies are each character's own.
	{ key = "recentPartyMembers", scope = CHARACTER, type = "table" },

	-- The window's centre, as an offset from UIParent's centre in UIParent
	-- units, and its size in its own units (core/window.lua). No default: with
	-- nothing saved the window opens at its own default place and size.
	{ key = "windowX", scope = ACCOUNT, type = "number" },
	{ key = "windowY", scope = ACCOUNT, type = "number" },
	{ key = "windowWidth", scope = ACCOUNT, type = "number" },
	{ key = "windowHeight", scope = ACCOUNT, type = "number" },

	-- Where on the minimap's rim the button sits, in degrees counter-clockwise
	-- from the right (core/minimap.lua). 225 -- bottom left -- is LibDBIcon's
	-- default (LibDBIcon-1.0.lua:157), so a first install lands where players
	-- expect minimap buttons.
	{ key = "minimapAngle", scope = ACCOUNT, type = "number", default = 225 },
}

local byKey = {}
for _, entry in ipairs(LFGF.SAVED_KEYS) do
	byKey[entry.key] = entry
end

local function EntryFor(key)
	local entry = byKey[key]
	if not entry then
		-- A typo in a key would otherwise read nil forever, silently.
		error("LFG Forever: no saved key named " .. tostring(key), 3)
	end
	return entry
end


--- The saved table for a scope ("account" or "character"), created if it is
--- missing or is not a table. Creating it as a global is what makes the client
--- save it on logout: that is what the TOC's SavedVariables lines mean.
local function storage(scope, create)
	local db = QuinteGroupDB
	if type(db) ~= "table" then return nil end
	if type(db.lfg) ~= "table" then
		if not create then return nil end
		db.lfg = {}
	end
	local key = scope == ACCOUNT and "account" or "characters"
	if type(db.lfg[key]) ~= "table" then
		if not create then return nil end
		db.lfg[key] = {}
	end
	local tables = db.lfg[key]
	if scope == ACCOUNT then return tables end
	local player = Quintessence.Key()
	if not player or player == "" then return nil end
	if type(tables[player]) ~= "table" then
		if not create then return nil end
		tables[player] = {}
	end
	return tables[player]
end

function LFGF.SavedTable(scope)
	return storage(scope, true) or {}
end

function LFGF.SavedValue(key)
	local entry = EntryFor(key)
	local saved = storage(entry.scope, false)
	return saved and saved[entry.key]
end

function LFGF.SaveValue(key, value)
	local entry = EntryFor(key)
	local saved = storage(entry.scope, value ~= nil)
	if saved then saved[entry.key] = value end
end

--- The saved value when it has the key's type (and, for a number with a
--- `min`, is not below it); the default otherwise.
---
--- NOT `value or default`: that would read a saved false as missing and turn
--- an option the player switched off back on.
function LFGF.SavedSetting(key)
	local entry = EntryFor(key)
	local value = LFGF.SavedValue(key)
	if type(value) ~= entry.type then
		return entry.default
	end
	if entry.min and value < entry.min then
		return entry.default
	end
	return value
end

-- THE OLD DEFAULT CONSTANTS, kept as names (settings.lua and the specs read
-- them) and taken from the table, so each value exists once.
LFGF.WHISPER_LOG_DEFAULT_SIZE = byKey.whisperLogSize.default
LFGF.ASK_TO_JOIN_DEFAULT_MESSAGE = byKey.askToJoinMessage.default
LFGF.INVITE_WHISPER_DEFAULT_MESSAGE = byKey.inviteMessage.default
LFGF.SHOW_ALL_LEVEL_RANGES_DEFAULT = byKey.showAllLevelRanges.default
LFGF.SHOW_ACTIVITY_LEVEL_RANGES_DEFAULT = byKey.showActivityLevelRanges.default
LFGF.MARK_GUILDMATES_DEFAULT = byKey.markGuildmates.default
LFGF.MARK_FRIENDS_DEFAULT = byKey.markFriends.default
LFGF.SHOW_MINIMAP_BUTTON_DEFAULT = byKey.showMinimapButton.default
LFGF.MINIMAP_DEFAULT_ANGLE = byKey.minimapAngle.default
LFGF.PLAYER_SORT_ORDER_DEFAULT = byKey.playerSortOrder.default

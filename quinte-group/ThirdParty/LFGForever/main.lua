-- QuinteLFG -- core/main.lua
--
-- The addon table every other file reads from: identity, the shared helpers,
-- and the row-button factory with its shared action cooldown. Plus the one
-- line it prints when the addon loads.
--
-- `...` at file scope is what the client passes every addon file:
--   (addonName, addonTable). The name is what ADDON_LOADED is matched on and
-- what the version is looked up by.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
local S = Quintessence.Style
local StaticPopupDialogs, StaticPopup_Show = LFGF.Dialogs, LFGF.ShowDialog
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

-------------------------------------------------------
---------- Addon identity
-------------------------------------------------------
-- These live here, in the first file the .toc loads after core/locale.lua,
-- because every other file wants them and none of them owns them. TWO NAMES, kept distinct:
-- "QuinteLFG" is the IDENTIFIER (the folder, this file's first
-- vararg, the stem of every global the addon publishes); LFGF.TITLE is what a
-- player reads.
LFGF.TITLE = "Recherche de groupe Quintessence"

--- One chat line from the addon, prefixed with its name: "LFG Forever: text".
--- print() is the FrameXML global from Blizzard_PrintHandler.lua:93.
function LFGF.Print(text)
	print(LFGF.TITLE .. ": " .. text)
end

-- The addon's icon, shared by the window's portrait and by the tab it adds to
-- Blizzard's Group Finder, so the two read as one feature.
--
-- An ATLAS rather than an Interface\ICONS\ path, because an atlas is verifiable
-- offline: AtlasInfo.lua is dumped from a running client, so presence there is
-- proof, while the ICONS files are not in .libraries at all.
--   AtlasInfo.lua:7482  ["friends-icon-tab-quickJoin"] = {66, 66, ...}
-- "Quick Join" is the Friends UI's group-finding feature, so it is apt as well
-- as available.
LFGF.ICON_ATLAS = "friends-icon-tab-quickJoin"

-- THE ADDON'S ONE SEPARATOR: between the activity and the zone on a players-list
-- row, and between the links on a whisper's action line. One constant, so the
-- two cannot drift apart again (they did: a "-" in one, a "|" in the other).
--
-- WRITTEN DOUBLED ON PURPOSE. "|" opens an escape sequence in a FontString
-- (|c, |r, |T, |H...), and "||" is how a single pipe is shown -- Blizzard's own
-- RECENT_ALLY_ENTRY_CHARACTER_DATA_FORMAT is "%s ||%d||%s"
-- (GlobalStrings/enUS.lua:18377).
LFGF.SEPARATOR = "||"

-- EventRegistry event name, namespaced the way Blizzard namespaces its own
-- ("UIParentPanelManager.ShowUIPanel", UIParentPanelManager.lua:873). Declared
-- here so the panel that fires it and the panel that listens share one string
-- rather than two literals that can drift.
LFGF.EVENT_FILTERS_APPLIED = "QuinteLFG.FiltersApplied"

-- Raised by core/whisperlog.lua when a whisper arrives FROM someone else, and
-- consumed by core/filterpanel.lua to flash the Whispers tab. Over
-- EventRegistry for the same reason the search is: neither file has to hold a
-- reference to the other.
LFGF.EVENT_WHISPER_RECEIVED = "QuinteLFG.WhisperReceived"

-- Raised by core/settings.lua when the player moves the whisper log size slider,
-- with the new size; core/whisperlog.lua listens and trims. EventRegistry again,
-- so the log never has to know the Settings API exists.
LFGF.EVENT_WHISPER_LOG_SIZE_CHANGED = "QuinteLFG.WhisperLogSizeChanged"

-- THE SAVED TABLES (QuinteLFGDB account-wide, QuinteLFGCharDB per
-- character), every key in them and every default live in core/db.lua. The
-- readers below are named wrappers over its LFGF.SavedSetting.

--- How many whispers the log keeps: the saved size, or the default.
---
--- DEFENSIVE ON PURPOSE. Saved variables are a file on disk that another addon
--- or a hand edit can change, and the log compares this against its length on
--- every whisper -- so anything but a finite number of at least 1 falls back
--- rather than erroring there (the entry's type and min, core/db.lua). NaN and
--- +inf are numbers that pass both, and the log could never trim to them.
--- Callable before ADDON_LOADED, when the table may not exist.
function LFGF.WhisperLogSize()
	local size = LFGF.SavedSetting("whisperLogSize")
	if not LFGF.IsFiniteNumber(size) then
		return LFGF.WHISPER_LOG_DEFAULT_SIZE
	end
	return size
end

-------------------------------------------------------
---------- The saved Filters tab
-------------------------------------------------------
-- QuinteLFGDB.filters: the Filters tab as last searched or reset, account-wide,
-- in the shape core/filterpanel.lua's FilterSnapshot hands the list --
--   { groupFilters = { field = bool }, playerRoles = { ... },
--     playerClasses = { CLASSFILE = bool }, playerLevels = { min = n, max = n },
--     playstyles = { Learning = bool, FunRelaxed = bool, ... },
--     languages = { enUS = bool, ... },
--     groupExcludedClasses = { CLASSFILE = bool } }
-- The category and activity dropdowns are NOT in it, by the author's decision.
--
-- WHO TOUCHES IT: the filter panel restores it once, when it is built (the
-- window is built on the first open of a session); Search and Reset filters
-- save it; Blizzard's Defaults button forgets it (core/settings.lua). Nothing
-- else: ticking a box waits for Search. See .claude/rules/saved-filters.md.

-- Raised by LFGF.ForgetSavedFilters; a filter panel that is already built puts
-- its boxes back to their defaults. Over EventRegistry, like the other events
-- here, so core/settings.lua never has to reach into the window.
LFGF.EVENT_FILTERS_FORGOTTEN = "QuinteLFG.FiltersForgotten"

-- The sections of on/off values: the three sections of boxes, and the
-- Playstyle, Languages and group class dropdowns' ticks. Levels are handled on
-- their own.
local FILTER_BOX_SECTIONS = { "groupFilters", "playerRoles", "playerClasses", "playstyles", "languages",
	"groupExcludedClasses" }

--- The four playstyles a listing can carry, read by the Playstyle dropdown
--- (core/filterpanel_miscellaneous.lua) and the list's filter
--- (core/listpanel.lua), so the two cannot disagree.
---
--- IN BLIZZARD'S ORDER, the order its camelot Listing tab offers them
--- (Blizzard_LFGVanilla_Listing.lua:945-948). `value` is the
--- Enum.LFGEntryGeneralPlaystyle member a listing's generalPlaystyle holds
--- (LFGConstantsDocumentation.lua; None = 0 is not a playstyle anyone picks).
---
--- `key` is what the filter record saves, the enum member's own name: a
--- string, which the saved-record cleaner keeps (CleanFilters), and one that
--- does not change with the client's language. Renaming one loses the
--- players' saved ticks.
LFGF.PLAYSTYLES = {
	{ key = "Learning", value = Enum.LFGEntryGeneralPlaystyle.Learning },
	{ key = "FunRelaxed", value = Enum.LFGEntryGeneralPlaystyle.FunRelaxed },
	{ key = "FunSerious", value = Enum.LFGEntryGeneralPlaystyle.FunSerious },
	{ key = "Expert", value = Enum.LFGEntryGeneralPlaystyle.Expert },
}

-- The level boxes are three-letter numeric edit boxes (LevelRangeEditBoxTemplate,
-- InputBoxTemplates.xml:378-409), and an empty box reads as 0 (GetNumber), the
-- filter's "no limit". So a usable saved level is a whole number the box could
-- have held; anything else is 0.
local FILTER_LEVEL_MAX = 999

local function SavedLevel(value)
	-- The whole-number test is also what stops NaN: NaN passes both range
	-- comparisons (every comparison with it is false), but NaN % 1 is NaN,
	-- which is ~= 0. The infinities fail the range.
	if type(value) ~= "number"
		or value < 1 or value > FILTER_LEVEL_MAX or value % 1 ~= 0 then
		return 0
	end
	return value
end

--- One filter record, cleaned: each box section keeps only string keys with
--- boolean values -- a box the record does not name, or names with anything
--- but a boolean, takes its own default when the panel applies this -- and a
--- level the box could not hold reads as no limit. A fresh table.
---
--- SHARED by the saved Filters tab and My filters (below), so the two records
--- cannot come to disagree about what a usable filter is.
local function CleanFilters(saved)
	local filters = {}
	for _, key in ipairs(FILTER_BOX_SECTIONS) do
		filters[key] = {}
		local section = saved[key]
		if type(section) == "table" then
			for field, value in pairs(section) do
				if type(field) == "string" and type(value) == "boolean" then
					filters[key][field] = value
				end
			end
		end
	end

	local levels = type(saved.playerLevels) == "table" and saved.playerLevels or {}
	filters.playerLevels = { min = SavedLevel(levels.min), max = SavedLevel(levels.max) }
	return filters
end

--- The saved Filters tab, cleaned, or nil when nothing usable is saved.
---
--- DEFENSIVE ON PURPOSE, the same way WhisperLogSize is: the record is a file on
--- disk. A fresh table every call, so the caller can keep it.
function LFGF.SavedFilters()
	local saved = LFGF.SavedValue("filters")
	if type(saved) ~= "table" then
		return nil
	end
	return CleanFilters(saved)
end

--- Save the Filters tab. A copy (CopyTable is deep, TableUtil.lua:218-228), so
--- the caller's snapshot can go on to be handed around. Creates the saved table
--- if the window is somehow used before ADDON_LOADED made it.
function LFGF.SaveFilters(snapshot)
	LFGF.SaveValue("filters", CopyTable(snapshot))
end

--- Forget the saved Filters tab (Blizzard's Defaults button) and announce it.
--- The key is cleared, not set to the defaults, so a future change to a
--- default reaches this player too.
function LFGF.ForgetSavedFilters()
	LFGF.SaveValue("filters", nil)
	EventRegistry:TriggerEvent(LFGF.EVENT_FILTERS_FORGOTTEN)
end

-------------------------------------------------------
---------- My filters
-------------------------------------------------------
-- QuinteLFGDB.myFilters: the player's NAMED filters, account-wide, in the order
-- they were saved --
--   { { name = "Tanks", filters = <FilterSnapshot's shape> }, ... }
-- The "My filters" dropdown on the Filters tab lists them (core/filterpanel.lua).
-- Picking one fills the boxes and saves them as the current filters above; it
-- does not search. See .claude/rules/my-filters.md.
--
-- WHO TOUCHES IT: "Save new filter" adds one, the x on a menu row deletes one,
-- and Blizzard's Defaults button forgets them all (core/settings.lua), by the
-- author's decisions. Nothing else.

-- At most 20 filters, each named in at most 20 letters, by the author's
-- decision. The popup's edit box is limited to the same 20 (maxLetters), so
-- the letter check here only catches a hand-edited file or a pasted name.
LFGF.MY_FILTERS_MAX = 20
LFGF.MY_FILTER_NAME_MAX_LETTERS = 20

-- Raised by LFGF.ForgetMyFilters; a built filter panel hides its dropdown.
LFGF.EVENT_MY_FILTERS_FORGOTTEN = "QuinteLFG.MyFiltersForgotten"

--- A name as it is saved and compared: spaces trimmed from both ends
--- (strtrim, GlobalAPI.lua), anything that is not a string read as "".
--- Case is kept and counts, by the author's decision: "Tanks" and "tanks" are
--- two filters.
function LFGF.CleanMyFilterName(name)
	if type(name) ~= "string" then
		return ""
	end
	return strtrim(name)
end

--- My filters, cleaned: a fresh list of { name, filters } in save order.
---
--- DEFENSIVE, like LFGF.SavedFilters: an entry that is not a table, has no
--- usable name, or has no filters table is skipped, and each filter is cleaned
--- by CleanFilters. Names are unique by construction; should a hand edit repeat
--- one, only the first counts, so what the menu lists, what "saved" means and
--- what a click applies all agree.
function LFGF.MyFilters()
	local saved = LFGF.SavedValue("myFilters")
	local list = {}
	if type(saved) ~= "table" then
		return list
	end

	local seen = {}
	for _, entry in ipairs(saved) do
		if type(entry) == "table" and type(entry.filters) == "table" then
			local name = LFGF.CleanMyFilterName(entry.name)
			if name ~= "" and not seen[name] then
				seen[name] = true
				table.insert(list, { name = name, filters = CleanFilters(entry.filters) })
			end
		end
	end
	return list
end

--- Whether a filter is saved under `name`, trimmed and matched exactly (case
--- counts, as everywhere in My filters). Saving under such a name overwrites it.
function LFGF.IsMyFilterSaved(name)
	name = LFGF.CleanMyFilterName(name)
	if name == "" then
		return false
	end
	for _, filter in ipairs(LFGF.MyFilters()) do
		if filter.name == name then
			return true
		end
	end
	return false
end

--- What is wrong with saving a filter under `name`, or nil if nothing is:
---   "empty" -- nothing left once trimmed
---   "long"  -- more than 20 letters; strlenutf8 counts letters, not bytes
---   "full"  -- 20 are saved and the name is new
--- A name already saved is fine: saving overwrites it, which adds none, so it
--- is never "full" (the author's decision). One answer, the first that
--- applies, so the popup can say why its Okay is off and SaveMyFilter can
--- refuse with the same word.
function LFGF.MyFilterNameProblem(name)
	name = LFGF.CleanMyFilterName(name)
	if name == "" then
		return "empty"
	end
	if strlenutf8(name) > LFGF.MY_FILTER_NAME_MAX_LETTERS then
		return "long"
	end
	if not LFGF.IsMyFilterSaved(name) and #LFGF.MyFilters() >= LFGF.MY_FILTERS_MAX then
		return "full"
	end
	return nil
end

--- Write the cleaned list back. Writing the CLEANED list is what drops any
--- entry a hand edit broke, the next time the player saves or deletes.
local function WriteMyFilters(list)
	LFGF.SaveValue("myFilters", list)
end

--- Save a filter at the end of My filters, under the trimmed name. A filter
--- already saved under that name is deleted first, so an overwrite moves the
--- name to the end, as a new save would (the author's decision). Returns true
--- and whether it overwrote one, or false and the problem (see
--- MyFilterNameProblem), saving nothing.
---
--- The snapshot is stored as given (a deep copy, CopyTable, TableUtil.lua:218-
--- 228), levels included: a min above the max is saved as typed, by the
--- author's decision, and put right by FixLevelRange when it is applied.
function LFGF.SaveMyFilter(name, snapshot)
	local problem = LFGF.MyFilterNameProblem(name)
	if problem then
		return false, problem
	end
	name = LFGF.CleanMyFilterName(name)
	local list = LFGF.MyFilters()
	local overwritten = false
	for index, filter in ipairs(list) do
		if filter.name == name then
			table.remove(list, index)
			overwritten = true
			break
		end
	end
	table.insert(list, { name = name, filters = CopyTable(snapshot) })
	WriteMyFilters(list)
	return true, overwritten
end

--- Delete the filter with exactly this name. Returns true if one was deleted.
--- Every raw entry with the name goes, so a duplicate a hand edit made cannot
--- step into the deleted one's place.
function LFGF.DeleteMyFilter(name)
	local list = LFGF.MyFilters()
	for index, filter in ipairs(list) do
		if filter.name == name then
			table.remove(list, index)
			WriteMyFilters(list)
			return true
		end
	end
	return false
end

--- Forget every filter in My filters (Blizzard's Defaults button, both "All
--- Settings" and "These Settings" on this page, by the author's decision) and
--- announce it.
function LFGF.ForgetMyFilters()
	LFGF.SaveValue("myFilters", nil)
	EventRegistry:TriggerEvent(LFGF.EVENT_MY_FILTERS_FORGOTTEN)
end

-------------------------------------------------------
---------- Collapsed filter sections
-------------------------------------------------------
-- WHICH FILTERS-TAB SECTIONS THE PLAYER COLLAPSED, account-wide, as a set of
-- section keys ({ classes = true }): QuinteLFGDB.collapsedFilterSections.
-- The keys are the sections' collapseKey (core/filterpanel.lua,
-- core/filterpanel_miscellaneous.lua). A view choice, kept apart from the
-- filters themselves: a collapsed section's boxes still apply, and Reset
-- filters and My filters never touch this.
--
-- WHO TOUCHES IT: a section's header saves its own key on every click
-- (core/filterpanel_shared.lua); the filter panel restores it once, when it is
-- built; Blizzard's Defaults button forgets it (core/settings.lua).
-- .claude/rules/collapsible-filter-sections.md

-- Raised by LFGF.ForgetCollapsedFilterSections; a filter panel that is already
-- built expands every section.
LFGF.EVENT_FILTER_SECTIONS_FORGOTTEN = "QuinteLFG.FilterSectionsForgotten"

--- The collapsed sections, cleaned: only string keys set to true, so a hand
--- edit or another addon's junk reads as expanded. A fresh table every call.
function LFGF.CollapsedFilterSections()
	local collapsed = {}
	local saved = LFGF.SavedValue("collapsedFilterSections")
	if type(saved) == "table" then
		for key, value in pairs(saved) do
			if type(key) == "string" and value == true then
				collapsed[key] = true
			end
		end
	end
	return collapsed
end

--- Save one section's state. An expanded section's key is removed, and the
--- saved key is cleared when nothing is left collapsed, so a player who
--- collapses nothing keeps no record. Writes the cleaned set, which drops any
--- junk already saved.
function LFGF.SetFilterSectionCollapsed(key, collapsed)
	local sections = LFGF.CollapsedFilterSections()
	sections[key] = collapsed and true or nil
	LFGF.SaveValue("collapsedFilterSections", next(sections) ~= nil and sections or nil)
end

--- Forget them all (Blizzard's Defaults button) and announce it.
function LFGF.ForgetCollapsedFilterSections()
	LFGF.SaveValue("collapsedFilterSections", nil)
	EventRegistry:TriggerEvent(LFGF.EVENT_FILTER_SECTIONS_FORGOTTEN)
end

-- THE ON/OFF SETTINGS (their defaults and why: core/db.lua). Each reader is
-- DEFENSIVE: callable before ADDON_LOADED, and anything but a boolean on disk
-- reads as the default -- while a saved false stays false (LFGF.SavedSetting).

--- Is "Mark guild members" on? (core/relations.lua)
function LFGF.MarkGuildmates()
	return LFGF.SavedSetting("markGuildmates")
end

--- Is "Mark friends (Experimental)" on? (core/relations.lua)
function LFGF.MarkFriends()
	return LFGF.SavedSetting("markFriends")
end

--- Is "Show minimap button" on? (core/minimap.lua)
function LFGF.ShowMinimapButton()
	return LFGF.SavedSetting("showMinimapButton")
end

-- Raised by core/settings.lua when "Show minimap button" changes, with the new
-- value; core/minimap.lua shows or hides the button. EventRegistry, like the
-- whisper log size, so the button never has to know the Settings API exists.
LFGF.EVENT_MINIMAP_BUTTON_CHANGED = "QuinteLFG.MinimapButtonChanged"

--- Is "Player ratings" on? (core/filterpanel.lua shows the third tab by it)
function LFGF.ShowPlayerRatings()
	return LFGF.RatingsAvailable and LFGF.SavedSetting("showPlayerRatings")
end

-- Raised by core/settings.lua when "Player ratings" changes, with the new
-- value; the filter panel shows or hides the Player ratings tab, and the list
-- of the last party members (core/recentparty.lua) starts or stops recording.
LFGF.EVENT_PLAYER_RATINGS_CHANGED = "QuinteLFG.PlayerRatingsChanged"

--- Is "Show all level activities" on? Our own setting, never Blizzard's CVar
--- (why: core/db.lua).
function LFGF.ShowAllLevelRanges()
	return LFGF.SavedSetting("showAllLevelRanges")
end

-- Raised by core/settings.lua when "Show all level activities" changes, with the
-- new value; core/filterpanel.lua rebuilds its dropdowns.
LFGF.EVENT_LEVEL_RANGES_CHANGED = "QuinteLFG.LevelRangesChanged"

--- Is "Show suggested level ranges" on? No change event: the activity menu
--- is rebuilt every time it opens (DropdownButton.lua:117-118), so it reads
--- this afresh.
function LFGF.ShowActivityLevelRanges()
	return LFGF.SavedSetting("showActivityLevelRanges")
end

--- The orders "Sort players by" offers, in its dropdown's order
--- (core/settings.lua), for the Players box of the list (core/listpanel.lua).
--- Each is SAVED BY NAME, so reordering the menu never changes a player's
--- choice; renaming one loses it. .claude/rules/player-sort-order.md
LFGF.PLAYER_SORT_ORDERS = { "newest", "oldest", "levelHigh", "levelLow", "class" }

--- The chosen order. Anything the list does not offer -- a hand edit, another
--- addon, a name from a later build -- reads as the default.
function LFGF.PlayerSortOrder()
	local order = LFGF.SavedSetting("playerSortOrder")
	for _, offered in ipairs(LFGF.PLAYER_SORT_ORDERS) do
		if order == offered then
			return order
		end
	end
	return LFGF.PLAYER_SORT_ORDER_DEFAULT
end

-- Raised by core/settings.lua when "Sort players by" changes, with the new
-- value; the list panel sorts its Players box again (core/listpanel.lua).
LFGF.EVENT_PLAYER_SORT_ORDER_CHANGED = "QuinteLFG.PlayerSortOrderChanged"

-- Settings.OpenToCategory(categoryID, scrollToElementName) is the call
-- Blizzard's guide for addon authors documents
-- (Blizzard_ImplementationReadme.lua:198-211); BugSack's build for this client
-- makes it from a click. It passes through the engine
-- (C_SettingsUtil.OpenSettingsPanel, HasRestrictions) and back into Blizzard's
-- own panel code as SETTINGS_PANEL_OPEN (Blizzard_SettingsPanel.lua:144-151).
--
-- REFUSED IN COMBAT, observed in the client: ADDON_ACTION_BLOCKED "tried to
-- call the protected function 'OpenSettingsPanel()'". So it checks first and
-- says why, the way the side tabs do before opening Blizzard's Group Finder.
-- A nil category (not registered yet) opens nothing.
local function OpenSettingsCategory(categoryID, scrollToElementName)
	if InCombatLockdown() then
		LFGF.Print(L.COMBAT_SETTINGS)
		return
	end
	if categoryID then
		Settings.OpenToCategory(categoryID, scrollToElementName)
	end
end

--- Open Options -> AddOns -> LFG Forever, the page core/settings.lua builds.
--- Every way in -- the settings gear, the minimap button's and the
--- compartment's right click -- comes through here. Does nothing until
--- core/settings.lua has registered the category on ADDON_LOADED.
function LFGF.OpenSettings()
	local category = LFGF.settingsCategory
	OpenSettingsCategory(category and category:GetID())
end

--- Open Blizzard's own Keybindings page at the LFG Forever section, where
--- Blizzard's code sets the key: the settings page's key binding button.
--- Blizzard links its Ping keybindings this way (PingSystem.lua:74-91), with
--- the page's ID from Keybindings.lua:282. The section is titled with the
--- binding's category, BINDING_HEADER_QUINTELFG = LFGF.TITLE (core/slash.lua,
--- read as _G[category] at Keybindings.lua:220-226), and the panel scrolls to
--- the element of that name (Blizzard_SettingsList.lua:152-158).
---
--- Blizzard also expands the section before opening it, by writing its
--- initializer's data.expanded. That is a write onto Blizzard's own object,
--- so the section is left as it is: collapsed until the player clicks it.
function LFGF.OpenKeybindings()
	OpenSettingsCategory(Settings.KEYBINDINGS_CATEGORY_ID, LFGF.TITLE)
end

-- REPORT A BUG: the Discord invite link in a popup. Two controls open it: the
-- settings page's Discord button (core/settings.lua) and the window header's
-- Report a bug (core/window.lua). .claude/rules/report-bug-header.md
local DISCORD_URL = "https://discord.com/invite/z6BU5Rkdsy"

-- THE LINK IS SHOWN TO COPY, NOT OPENED. Addon code may do neither of the
-- obvious things: LaunchURL and CopyToClipboard are both HasRestrictions
-- (URLDocumentation.lua:12, OsDocumentation.lua:12), and CopyToClipboard has
-- already been refused from this addon in the client. So the popup holds the
-- link in a text box, selected, for the player's own Ctrl+C -- what every
-- example addon that shows a link does.
local REPORT_BUG_POPUP = "QUINTELFG_REPORT_BUG"
local REPORT_BUG_POPUP_TEXT = L.REPORT_BUG_POPUP_TEXT

-- Wide enough to show the whole link; GameDialogMixin:SetupEditBox reads it
-- (GameDialog.lua:253). The default is 130 (GameDialog.xml:212).
local REPORT_BUG_EDITBOX_WIDTH = 260

-- ALWAYS SET, because the text box is shared. Blizzard reuses four popup
-- frames, one edit box each (GameDialog.xml:348-367, StaticPopup.lua:389-393),
-- and SetupEditBox applies a letter limit ONLY when the dialog defines one
-- (GameDialog.lua:248-251); nothing resets it. Without this the popup inherits
-- whatever limit the previous dialog left -- 24 after Blizzard's generic input
-- box (GameDialogDefs.lua:213), 31 after a guild note -- and the link does not
-- fit. Exactly the link's length also keeps the copy box from growing. The link
-- is plain ASCII, so its byte length is its letter count.
local REPORT_BUG_MAX_LETTERS = #DISCORD_URL

-- Defined once, at file scope: StaticPopupDialogs is a shared registry, and the
-- key is namespaced because every addon's dialogs live in it.
StaticPopupDialogs[REPORT_BUG_POPUP] = {
	text = REPORT_BUG_POPUP_TEXT,
	button1 = L.CLOSE,
	hasEditBox = 1,
	maxLetters = REPORT_BUG_MAX_LETTERS,
	editBoxWidth = REPORT_BUG_EDITBOX_WIDTH,

	-- Runs synchronously inside StaticPopup_Show, with the link as `data`
	-- (StaticPopup.lua:591-596). The text box is reached through the dialog's
	-- accessor (GameDialog.lua:242), not a field.
	OnShow = function(dialog, url)
		local editBox = dialog:GetEditBox()
		editBox:SetText(url)
		editBox:SetFocus()
		editBox:HighlightText()
	end,

	-- READ-ONLY, the way a copy box should be: anything typed over the link is
	-- put back at once. The hook is called with the dialog's data
	-- (SharedTemplates.lua:69-74), which is the link itself.
	EditBoxOnTextChanged = function(editBox, url)
		if editBox:GetText() ~= url then
			editBox:SetText(url)
			editBox:HighlightText()
		end
	end,

	-- Escape in the box closes the popup -- Blizzard's own helper
	-- (StaticPopup.lua:152-154).
	EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,

	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

--- Open the Report a bug popup, the link passed as `data` -- the FOURTH
--- argument, so it is there before OnShow runs (StaticPopup.lua:309). Opened
--- again while it shows, Blizzard reuses that dialog instead of opening a
--- second one (StaticPopup_Show -> StaticPopup_FindVisible). Works in combat:
--- StaticPopup_Show has no combat check, and its only issecure test is for
--- editBoxSecureText (StaticPopup.lua:323), which this popup does not set.
function LFGF.ShowReportBug()
	StaticPopup_Show(REPORT_BUG_POPUP, nil, nil, DISCORD_URL)
end

-------------------------------------------------------
---------- A popup's Okay, and why it is off
-------------------------------------------------------
-- A popup with a box keeps its Okay off until what is typed will do, and says
-- why on hover: Save new filter (core/filterpanel.lua) and Clear player rating
-- (core/playerratings.lua). Blizzard's popup has no tooltip for its buttons, so
-- it goes on the button itself. But that button is Blizzard's: the popups are
-- four reused frames (GameDialog.xml:348-367), each owning its buttons
-- (:181-184), and per dialog Blizzard resets only their text, enabled state
-- and pulse (GameDialogMixin:SetupButtons, GameDialog.lua:319-341). Left in
-- place, our scripts would reach the next dialog in that frame, one of
-- Blizzard's own, say. So OnShow keeps what was there, and OnHide puts it
-- back. Kept here, in a table of ours, not on Blizzard's frame. OnClick is
-- never touched.
local okayRestore = setmetatable({}, { __mode = "k" })

--- From a popup's OnShow: while `dialog`'s Okay is off, hovering it shows
--- `title` over `Reason(text)`, the reason for what the box holds (nil when
--- there is none). Undo it with LFGF.RestorePopupOkay from the popup's OnHide.
function LFGF.HookPopupOkayTooltip(dialog, title, Reason)
	local okay = dialog:GetButton1()
	okayRestore[okay] = {
		motion = okay:GetMotionScriptsWhileDisabled(),
		onEnter = okay:GetScript("OnEnter"),
		onLeave = okay:GetScript("OnLeave"),
	}
	-- A disabled button fires no OnEnter unless told to; Blizzard sets the
	-- same flag on its own Role Check button for its reason tooltip
	-- (Blizzard_LFGVanilla_Listing.xml:413).
	okay:SetMotionScriptsWhileDisabled(true)
	okay:SetScript("OnEnter", function(self)
		local reason = Reason(dialog:GetEditBox():GetText())
		if self:IsEnabled() or reason == nil then
			return
		end
		LFGF.ShowTooltip(self, title, reason)
	end)
	okay:SetScript("OnLeave", function(self)
		if GameTooltip:GetOwner() == self then
			GameTooltip:Hide()
		end
	end)
end

--- From a popup's OnHide: put back what LFGF.HookPopupOkayTooltip found on the
--- Okay button. Nothing for a button it never borrowed.
function LFGF.RestorePopupOkay(dialog)
	local okay = dialog:GetButton1()
	local saved = okayRestore[okay]
	if not saved then
		return
	end
	okayRestore[okay] = nil
	if GameTooltip:GetOwner() == okay then
		GameTooltip:Hide()
	end
	okay:SetMotionScriptsWhileDisabled(saved.motion)
	okay:SetScript("OnEnter", saved.onEnter)
	okay:SetScript("OnLeave", saved.onLeave)
end

-- THE ASK TO JOIN WHISPER. Its text is a setting (core/settings.lua), saved
-- per character as askToJoinMessage; its default and the placeholder rules
-- are with the key in core/db.lua.

-- THE WORD %class% BECOMES, per class: fixed, lower-case English, NEVER
-- translated, by the author's decision -- the leader reads the same word
-- whatever language the player's client is in, and it matches %talents%'s words
-- (core/talents.lua). Keyed by UnitClass's English token (its second return,
-- classFilename). The nine classes are the ones Blizzard's camelot talent UI
-- knows (Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentUtil.lua
-- :1-11). Until 0.9.0-dev.3 this was the client's translated, capitalised name
-- from LOCALIZED_CLASS_NAMES_MALE.
LFGF.ASK_TO_JOIN_CLASS_NAMES = {
	WARRIOR = "warrior",
	PALADIN = "paladin",
	HUNTER = "hunter",
	ROGUE = "rogue",
	PRIEST = "priest",
	SHAMAN = "shaman",
	MAGE = "mage",
	WARLOCK = "warlock",
	DRUID = "druid",
}

--- "A", "A or B", "A, B or C". Fixed English, never translated, like the
--- words %class% and %talents% become.
local function JoinNames(names)
	if #names == 1 then
		return names[1]
	end
	return table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
end

--- What %role% becomes: the roles ticked in Blizzard's Group Finder, the
--- author's English words in the order tank, heal, dps, joined like %dungeon%
--- ("tank or dps"). "" with nothing ticked, or when the client answers
--- nothing. Every class, with no class check, by the author's decision
--- (0.20.0-dev.4; dev.2 and dev.3 left it empty for rogue, hunter, mage and
--- warlock).
---
--- C_LFGListRoles.GetRoles holds the three role checkboxes of Blizzard's
--- Listing tab, which writes them on every click and reads them back
--- (Blizzard_LFGVanilla_Listing.lua:561-574). It is engine API, so it needs no
--- Group Finder loaded, and it carries no secret predicate and no restriction
--- (LFGListRolesDocumentation.lua:11-19); MayReturnNothing. Read when asked,
--- always the checkboxes, solo or grouped, by the author's decision; what is
--- ticked is sent as ticked, even a role the class is not suited to.
local function RoleWords()
	local roles = C_LFGListRoles.GetRoles()
	if roles == nil then
		return ""
	end
	local words = {}
	if roles.tank then table.insert(words, "tank") end
	if roles.healer then table.insert(words, "heal") end
	if roles.dps then table.insert(words, "dps") end
	if #words == 0 then
		return ""
	end
	return JoinNames(words)
end

--- The whisper Ask to Join sends, or nil when it should open a whisper box
--- for the player to type in instead.
---
--- Nil when the "Auto-whisper on Ask to Join" checkbox is off, and when the
--- character's message is empty or blank -- the player asked for both to
--- behave the same. The checkbox is account-wide and ON unless saved off.
---
--- THE MESSAGE IS READ FROM THIS CHARACTER'S TABLE ONLY, with no default of
--- its own, by the author's decision: core/settings.lua always leaves one in
--- QuinteLFGCharDB on ADDON_LOADED (the default, for a character that has
--- none), long before anyone can click Ask to Join. Before that there is
--- nothing, so nil -- a whisper box -- rather than an error.
---
--- BOTH VALUES ARE READABLE BY CONSTRUCTION: UnitClass's classFilename carries
--- no ConditionalSecret (UnitDocumentation.lua:925, unlike className at
--- :924), and UnitLevel carries no secret predicate at all (:2474-2487). The
--- class WORD comes from LFGF.ASK_TO_JOIN_CLASS_NAMES by that filename: fixed
--- English, never translated. A class without a word sends nothing (nil), as a
--- missing name always did.
---
--- %talents% IS THE MAIN TALENT TREE'S WORD (LFGF.TalentRole, core/talents.lua),
--- from the points read when the window last OPENED (LFGF.talentPoints) --
--- nothing is read here. It becomes "" when there is nothing to go on, and
--- the rest of the message is still sent (the default then reads "a  warrior",
--- with two spaces, as the author accepted).
---
--- %role% IS THE ROLES TICKED IN BLIZZARD'S GROUP FINDER (RoleWords above),
--- read now, not when the window opened. "" in the same way, leaving the same
--- double space where the player typed it.
---
--- REPLACED AS PLAIN TEXT: the patterns are the literal tokens, and the
--- replacement goes through a function so nothing in it is read as a capture
--- reference -- any other % the player typed is left exactly as it is.
function LFGF.AskToJoinMessage()
	if not LFGF.SavedSetting("askToJoinAutoWhisper") then
		return nil
	end

	local template = LFGF.SavedValue("askToJoinMessage")
	if type(template) ~= "string" or not template:find("%S") then
		return nil
	end

	local _, classFilename = UnitClass("player")
	local className = classFilename and LFGF.ASK_TO_JOIN_CLASS_NAMES[classFilename]
	local level = UnitLevel("player")
	if className == nil or type(level) ~= "number" then
		return nil
	end

	local message = template:gsub("%%class%%", function() return className end)
	message = message:gsub("%%level%%", function() return tostring(level) end)
	local talents = LFGF.TalentRole(classFilename, LFGF.talentPoints)
	message = message:gsub("%%talents%%", function() return talents end)
	local roles = RoleWords()
	message = message:gsub("%%role%%", function() return roles end)
	return message
end

-- THE INVITE WHISPER (.claude/rules/invite-whisper.md). The players list's
-- invite button invites a solo player and then whispers them this, with
-- %dungeon% filled in from the player's OWN listing -- or, with no listing,
-- from the activities ticked in the filter panel's activity dropdown (all of
-- them, as for a listing). %dungeon_en% is the same with English dungeon and
-- raid names (.claude/rules/dungeon-en-placeholder.md). Saved per character as
-- inviteMessage, the checkbox account-wide as inviteAutoWhisper; the default
-- is with the key in core/db.lua.

-- Where the activity dropdown's selection comes from: a function answering
-- the ticked activity IDs, or nil. core/window.lua hands it over when it
-- builds the two columns (BuildContentPanels), the filter panel's
-- SelectedActivityIDs, so neither panel learns of the other -- the list
-- panel's invite button only ever asks LFGF.InviteWhisperMessage(). Before
-- the window is built there is no source, and nothing counts as ticked.
local inviteActivitySource

--- Hand over the activity dropdown's selection for the invite whisper.
--- `source` is a function answering a list of activity IDs (or nil).
function LFGF.SetInviteActivitySource(source)
	inviteActivitySource = source
end

--- Does the player's listing count for %dungeon%? Only a listing the player
--- LEADS: their own, while in no group, or their group's, as its leader. Not
--- an assistant's, by the author's decision, although an assistant can invite.
--- The same gate decides whose activity dropdown counts when there is no
--- listing (since 0.15.0-dev.1, the author's decision): solo or leader only.
---
--- BOTH ANSWERS ARE GUARDED, and an unreadable one counts as NO. IsInGroup is
--- undocumented; UnitIsGroupLeader is SecretWhenUnitIdentityRestricted
--- (UnitDocumentation.lua:2039), which is not a combat predicate, and testing
--- a secret boolean from addon code errors. Role Check fails the other way
--- (core/filterpanel.lua, CanStartRoleCheck), because there the worst case is
--- the server's own refusal; here it is a whisper to a stranger.
local function LeadsOwnListing()
	local inGroup = IsInGroup()
	if not canaccessvalue(inGroup) then
		return false
	end
	if not inGroup then
		return true
	end
	local leader = UnitIsGroupLeader("player")
	return canaccessvalue(leader) and leader == true
end

--- Is the game in English? GetLocale names the client's language, one string
--- that is never nil or secret (LocaleDocumentation.lua). Blizzard's own
--- localization tables list "enGB" beside "enUS" (Blizzard_SharedXMLGame/
--- Shared/Localization.lua), so both count.
local function ClientIsEnglish()
	local locale = GetLocale()
	return locale == "enUS" or locale == "enGB"
end

--- The names of these activities, in Blizzard's order, or nil; and second,
--- the same names for %dungeon_en%, one for one. Shared by the listing and the
--- activity dropdown, so the two name a dungeon the same way and in the same
--- order.
---
--- THE ORDER IS BLIZZARD'S, the one its Listing tab draws a listing in
--- (Blizzard_LFGVanilla_Listing.lua:1219-1222): groups by their orderIndex,
--- then name; activities within a group the same way
--- (Blizzard_LFGVanilla_ParentFrame.lua:175-244). Those helpers live in the
--- LoadOnDemand Group Finder; a players-list row cannot exist without it, so
--- their absence is a belt, answered with nil.
---
--- THE NAME IS THE ONE THE LIST SHOWS: LFGUtil_GetActivityInfoName, the short
--- name when there is one (:270-273), as core/listpanel.lua's rows do. An
--- activity the client has no info for is left out of both lists
--- (GetActivityInfoTable MayReturnNothing, LFGListInfoDocumentation.lua:184-198;
--- Blizzard's organiser skips it too, ParentFrame.lua:231).
---
--- THE ENGLISH NAME, by the author's rules: on an English client, the client's
--- own name, so a dungeon Blizzard renames is sent as it is now; on any other,
--- the name LFGF.ENGLISH_ACTIVITY_NAMES (core/activitynames.lua) holds for that
--- activity, and the client's name for one it has none for. The ORDER stays the
--- client's: both lists name the same activities in the same order.
local function ActivityNames(activityIDs)
	if type(LFGUtil_OrganizeActivitiesByActivityGroup) ~= "function"
		or type(LFGUtil_SortActivityGroupIDs) ~= "function" then
		return nil
	end

	local organized = LFGUtil_OrganizeActivitiesByActivityGroup(activityIDs)
	local groupIDs = {}
	for groupID in pairs(organized) do
		table.insert(groupIDs, groupID)
	end
	LFGUtil_SortActivityGroupIDs(groupIDs)

	local english = not ClientIsEnglish() and LFGF.ENGLISH_ACTIVITY_NAMES or {}
	local names, englishNames = {}, {}
	for _, groupID in ipairs(groupIDs) do
		for _, activityID in ipairs(organized[groupID]) do
			local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
			local name = activityInfo and LFGUtil_GetActivityInfoName(activityInfo)
			if type(name) == "string" and name ~= "" then
				table.insert(names, name)
				table.insert(englishNames, english[activityID] or name)
			end
		end
	end
	if #names == 0 then
		return nil
	end
	return names, englishNames
end

--- The names of the listing's activities, or nil; and their English names
--- (ActivityNames).
---
--- GetActiveEntryInfo is SecretInChatMessagingLockdown and MayReturnNothing
--- (LFGListInfoDocumentation.lua:139-148), but its activityIDs field is
--- NeverSecret (:938), and that is the only field read. A listing holds up to
--- GROUP_FINDER_MAX_ACTIVITY_CAPACITY (16) activities (LuaEnum.lua:9729), and
--- every one is named.
local function ListingActivityNames(entry)
	if type(entry.activityIDs) ~= "table" then
		return nil
	end
	return ActivityNames(entry.activityIDs)
end

--- The names of the activities ticked in the activity dropdown, or nil when
--- none is ticked or none of them has a name; and their English names
--- (ActivityNames).
---
--- EVERY TICKED ACTIVITY IS NAMED, the same as a listing's: no limit of its
--- own (0.15.0-dev.1 ignored more than 3; removed in 0.15.0-dev.2 by the
--- author's decision), and no length cap on the whisper either (see
--- InviteWhisperMessage). Every ticked ID came from the menu,
--- which lists only what LFGF.Activities offers; an activity with no info is
--- left out of the names, as for a listing.
---
--- Read at click time, from whatever is ticked now -- a Search is not needed.
--- Nothing read is secret: the IDs are the addon's own, and
--- GetActivityInfoTable's returns carry no secret flag.
local function DropdownActivityNames()
	local activityIDs = inviteActivitySource and inviteActivitySource()
	-- Nothing ticked needs no check of its own: ActivityNames answers nil for
	-- an empty list.
	if type(activityIDs) ~= "table" then
		return nil
	end
	return ActivityNames(activityIDs)
end

--- The whisper the players list's invite button sends after inviting, or nil
--- for "invite only". Every rule is the author's (2026-10-01):
---
---   * nil when the checkbox is off, or this character's message is empty or
---     blank. No whisper box either: unlike Ask to Join, an invite says
---     something on its own;
---   * nil when the player does not lead (LeadsOwnListing): solo, or the
---     leader of their group. An assistant or member is only ever invited;
---   * with a listing (GetActiveEntryInfo answers an entry), its activities,
---     every one of them; nil when none has a name. The dropdown is not asked:
---     never a dungeon the player is not listed for;
---   * with no listing, since 0.15.0-dev.1 (the author's rules, 2026-10-05),
---     the activities ticked in the activity dropdown, every one of them
---     (DropdownActivityNames); nil when nothing is ticked;
---   * nil, whatever the message says, %dungeon% or not, when neither names
---     a dungeon;
---   * %dungeon% becomes the names, all of them, joined, and %dungeon_en% the
---     same names in English (ActivityNames; the author's rules, 2026-11-16).
---     The only two placeholders. Replaced as plain text, like
---     AskToJoinMessage's: %dungeon% first, then %dungeon_en% in what is left,
---     so a %dungeon% is filled in exactly as before %dungeon_en% existed;
---     activity names hold no "%dungeon_en%" for the second pass to find;
---   * NO LENGTH CAP, by the author's decision (2026-10-12), like Ask to Join.
---     Until 0.21.0-dev.6 a result over 255 bytes (Blizzard's chat box,
---     visibleBytes="255", Blizzard_ChatFrameBase/Mainline/ChatFrameEditBox
---     .xml:3) was not sent and a chat line said so. What the server does with
---     a longer C_ChatInfo.SendChatMessage is not documented.
---
--- READ AT CLICK TIME: the listing and the ticked activities are whatever
--- they are when the button is clicked. Nothing here is secret: the activity
--- names come from GetActivityInfoTable, whose returns carry no secret flag.
function LFGF.InviteWhisperMessage()
	if not LFGF.SavedSetting("inviteAutoWhisper") then
		return nil
	end

	local template = LFGF.SavedValue("inviteMessage")
	if type(template) ~= "string" or not template:find("%S") then
		return nil
	end

	if not LeadsOwnListing() then
		return nil
	end
	local entry = C_LFGList.GetActiveEntryInfo()
	local names, englishNames
	if entry then
		names, englishNames = ListingActivityNames(entry)
	else
		names, englishNames = DropdownActivityNames()
	end
	if names == nil then
		return nil
	end

	local dungeon = JoinNames(names)
	local dungeonEnglish = JoinNames(englishNames)
	local message = template:gsub("%%dungeon%%", function() return dungeon end)
	message = message:gsub("%%dungeon_en%%", function() return dungeonEnglish end)
	return message
end

-- The slash command, in ONE place. core/slash.lua registers with it and the
-- greeting below names it, so a greeting that tells the player to type
-- something nobody can type is not a state this addon can reach. Published
-- here rather than in slash.lua because main.lua loads first (QuinteLFG.toc)
-- and this file is where the shared constants live.
LFGF.SLASH_COMMAND = "/qlfg"


-------------------------------------------------------
---------- Reading secret-capable data
-------------------------------------------------------
-- SHARED BY BOTH PANELS THAT READ IT. core/listpanel.lua reads search results;
-- core/whisperlog.lua reads chat. Different APIs, same three hazards -- compare,
-- concatenate, use as a table key -- so the guards live here rather than in two
-- copies that can drift.

--- Read a field only when the caller may actually touch it.
--- Returns fallback when it may not, so every caller has a defined answer and
--- none of them has to repeat the guard.
---
--- canaccessvalue is the question Blizzard's own chat filter registry asks
--- (ChatFrameFilters.lua:115-118) and is stricter than issecretvalue: false for
--- a secret AND for a value the caller may not touch.
function LFGF.Readable(value, fallback)
	if not canaccessvalue(value) or value == nil then
		return fallback
	end
	return value
end

--- Whether a value is a number that can go into SetPoint or a trig function:
--- not NaN (the only value not equal to itself) and not an infinity, whose
--- cos and sin are NaN. For saved numbers -- a file on disk -- never secrets.
function LFGF.IsFiniteNumber(value)
	return type(value) == "number" and value == value
		and value ~= math.huge and value ~= -math.huge
end

--- Every value given, or nil when any of them cannot be used: secret, or
--- missing. For geometry reads (GetCenter, GetSize, GetScale, GetWidth), which
--- are SecretWhenAnchoringSecret, GetCenter also MayReturnNothing
--- (SimpleScriptRegionAPIDocumentation.lua:145, :276), so every value is
--- checked before any of them is compared or used in arithmetic.
---
--- ACCESS FIRST, THEN NIL: canaccessallvalues before any `== nil`, so a secret
--- is never compared (the open question in
--- .claude/rules/lfgforever-code-style.md). select("#") counts a trailing nil,
--- which ipairs over {...} would not.
function LFGF.ReadableNumbers(...)
	if not canaccessallvalues(...) then
		return nil
	end
	for index = 1, select("#", ...) do
		if select(index, ...) == nil then
			return nil
		end
	end
	return ...
end

-------------------------------------------------------
---------- Player ratings
-------------------------------------------------------
-- ONE KEY PER PLAYER, whatever list the name came from: the Player ratings tab
-- saves by it (core/playerratings.lua), and the player listings are to look it
-- up. The rules are the forever_notes skill's (assets/notes/NoteKey.lua,
-- FromName): a Forever character is "Firstname Surname", the parts joined by a
-- space, with no realms (LuaEnum.lua:9530-9534), and the same player also
-- arrives in the link form "Firstname-Surname" (ChatFrameEditBox.lua:84-85).
-- .claude/rules/player-ratings.md

--- The key for a player's name: its ends trimmed, every run of spaces made
--- one, and the link form "Firstname-Surname" folded into "Firstname Surname".
--- Nil for no name, an empty one, or one that cannot be read: a hidden name is
--- never a table key.
---
--- NO TYPE TEST AFTER THE READ. A name an API answers is a string, and the
--- harness's secret is a table, so string.gsub errors on it if the guard ever
--- goes (patterns-taint.md, A Type Check Can Hide A Missing Secret Guard).
function LFGF.PlayerKey(name)
	name = LFGF.Readable(name, nil)
	if type(name) ~= "string" then return nil end
	name = name:gsub("%s+", " "):match("^%s*(.-)%s*$")
	if name == "" then return nil end
	return Quintessence.WhisperTarget(name)
end

local function IsRating(rating)
	return rating == 1 or rating == 2 or rating == 3
end

--- A player's rating, 1, 2 or 3 stars, or nil when nobody rated them. `key` is
--- LFGF.PlayerKey's. Anything else on disk (a hand edit, another addon) reads
--- as not rated.
function LFGF.PlayerRating(key)
	if key == nil then
		return nil
	end
	local ratings = LFGF.SavedValue("playerRatings")
	if type(ratings) ~= "table" then
		return nil
	end
	local record = ratings[key]
	if type(record) ~= "table" or not IsRating(record.rating) then
		return nil
	end
	return record.rating
end

--- Save `rating`, 1, 2 or 3 stars, for the player `key` (LFGF.PlayerKey's),
--- with their GUID beside it when it can be read, and the server time.
--- Answers whether it saved: false, saving nothing, for no key or any other
--- rating. The stars only change a rating; Clear player rating clears one, by
--- name (LFGF.ClearPlayerRating).
---
--- THE GUID IS KEPT, NEVER THE KEY: the player listings carry no GUID
--- (LfgSearchResultPlayerInfo, LFGListInfoDocumentation.lua:1013-1027), so a
--- name is what every list can look up.
function LFGF.SetPlayerRating(key, rating, guid)
	if key == nil or not IsRating(rating) then
		return false
	end
	local ratings = LFGF.SavedValue("playerRatings")
	if type(ratings) ~= "table" then
		ratings = {}
	end
	ratings[key] = { rating = rating, guid = LFGF.Readable(guid, nil), time = GetServerTime() }
	LFGF.SaveValue("playerRatings", ratings)
	EventRegistry:TriggerEvent(LFGF.EVENT_PLAYER_RATING_CHANGED, key, rating)
	return true
end

--- Clear the saved rating of the player `key` (LFGF.PlayerKey's), exactly that
--- key: case is kept, so "water boi" is not "Water Boi". Answers whether a
--- rating was cleared: false, changing nothing, for no key, a player nobody
--- rated, or a record on disk that is not a rating (LFGF.PlayerRating's rule).
--- The record goes entirely; rating the player again starts afresh.
function LFGF.ClearPlayerRating(key)
	if LFGF.PlayerRating(key) == nil then
		return false
	end
	local ratings = LFGF.SavedValue("playerRatings")
	ratings[key] = nil
	LFGF.SaveValue("playerRatings", ratings)
	EventRegistry:TriggerEvent(LFGF.EVENT_PLAYER_RATING_CHANGED, key, nil)
	return true
end

--- Raised after a rating is saved (LFGF.SetPlayerRating) or cleared
--- (LFGF.ClearPlayerRating), with (key, rating), the rating nil for a clear.
--- The players list, the whisper log and the Player ratings tab listen, each
--- with itself as the owner, and redraw their marks and stars in place.
LFGF.EVENT_PLAYER_RATING_CHANGED = "QuinteLFG.PlayerRatingChanged"

--- Raised by core/recentparty.lua each time its list of the last five party
--- members changes. The Player ratings tab listens, with itself as the owner,
--- and draws its list again while it is shown.
LFGF.EVENT_RECENT_PARTY_MEMBERS_CHANGED = "QuinteLFG.RecentPartyMembersChanged"

-------------------------------------------------------
---------- The rating marks in the lists (Phase 3)
-------------------------------------------------------
-- THE AUTHOR'S DECISIONS (2026-11-13): a rated player's row in the players
-- list (a solo player, a group by its leader) and in the whisper log gets a
-- 2 px strip in the rating's colour over the left edge of its band; the whisper
-- log's tooltip gets the rating's line too. .claude/rules/player-ratings.md
--
-- 2 PX IS BLIZZARD'S OWN WIDTH: its Event Scheduler draws a 2 px solid line down
-- the left edge of its rows (Mainline/EventScheduler.xml:96-106), the nearest
-- thing to a strip on a row in Blizzard's UI. Nothing of Blizzard's marks a
-- row's status with one.
local RATING_STRIP_WIDTH = 2
-- Where both lists' rows start their band: the players list's template
-- (Blizzard_LFGVanilla_Browse.xml:214-219, TOPLEFT 3, -2 / BOTTOMRIGHT -3, 0) and
-- the shared player row, which copies it (core/playerrow.lua).
local BAND_INSET_X, BAND_INSET_TOP = 3, -2
-- Blizzard's own silver, the |cffc0c0c0 its Group Finder writes its "Silver
-- Tank" rank in (LFG_LIST_PROVING_TANK_SILVER, GlobalStrings/enUS.lua).
local SILVER = 192 / 255
-- Blizzard's own dim green, the |cff40c040 its Wardrobe writes a set in progress
-- in (Blizzard_Collections/Shared/Blizzard_Wardrobe_Sets.lua) and its Group
-- Finder the dash of "Pending" (LFG_LIST_PENDING, GlobalStrings/enUS.lua):
-- DIM_GREEN_FONT_COLOR's value (vscode-wow-api GlobalColors.lua). As a number,
-- because no Lua file of this client reads that global. Its green is the
-- silver's brightness, so the three marks look alike in strength.
local DIM_GREEN_RED_BLUE, DIM_GREEN_GREEN = 64 / 255, 192 / 255

--- The colour a rating is marked in, as r, g, b: 1 star RED_FONT_COLOR, 2
--- Blizzard's silver, 3 Blizzard's dim green (player-ratings.md). Nothing for
--- anything else. RED_FONT_COLOR is generated at load from the client's colour
--- database, so it is read here, at call time.
function LFGF.PlayerRatingRGB(rating)
	if rating == 1 then
		return RED_FONT_COLOR:GetRGB()
	elseif rating == 2 then
		return SILVER, SILVER, SILVER
	elseif rating == 3 then
		return DIM_GREEN_RED_BLUE, DIM_GREEN_GREEN, DIM_GREEN_RED_BLUE
	end
end

--- The rating to MARK a player with: their saved rating while the Player
--- ratings setting is on, by LFGF.PlayerKey (so the link form and a hidden name
--- are handled there), and nothing otherwise. The setting off hides every mark
--- and keeps the ratings (decision 7).
function LFGF.PlayerRatingFor(name)
	if not LFGF.ShowPlayerRatings() then
		return nil
	end
	return LFGF.PlayerRating(LFGF.PlayerKey(name))
end

--- A row's rating strip: a white colour texture tinted per rating, in the
--- BORDER layer, so over the band (BACKGROUND) and under the text and the hover
--- bar. The band's own height, its first 2 px. Starts hidden.
function LFGF.CreateRatingStrip(row)
	local strip = row:CreateTexture(nil, "BORDER")
	strip:SetColorTexture(1, 1, 1)
	strip:SetWidth(RATING_STRIP_WIDTH)
	strip:SetPoint("TOPLEFT", row, "TOPLEFT", BAND_INSET_X, BAND_INSET_TOP)
	strip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", BAND_INSET_X, 0)
	strip:Hide()
	return strip
end

--- Show the strip in `rating`'s colour (1, 2 or 3 stars), or hide it for nil.
--- Written both ways on every call: rows are pooled.
function LFGF.PaintRatingStrip(strip, rating)
	if rating == nil then
		strip:Hide()
		return
	end
	strip:SetVertexColor(LFGF.PlayerRatingRGB(rating))
	strip:Show()
end

--- Show the strip for `name`'s rating (LFGF.PlayerRatingFor), or hide it.
function LFGF.ShowRatingStrip(strip, name)
	LFGF.PaintRatingStrip(strip, LFGF.PlayerRatingFor(name))
end

--- The tooltip line for `name`'s rating, and its colour: the stars tooltip's own
--- line for that rating ("2 stars - I'm fine grouping with this player"), as
--- text, r, g, b. Nothing for someone not marked.
function LFGF.PlayerRatingLine(name)
	local rating = LFGF.PlayerRatingFor(name)
	if rating == nil then
		return nil
	end
	local lines = { L.PLAYER_RATING_ONE_STAR_LINE, L.PLAYER_RATING_TWO_STARS_LINE,
		L.PLAYER_RATING_THREE_STARS_LINE }
	return lines[rating], LFGF.PlayerRatingRGB(rating)
end

-- Blizzard's own table is a FILE-LOCAL in Browse.lua:12-25 -- not a global, so
-- it cannot be borrowed -- and it is built by iterating CLASS_SORT_ORDER:
--     LFGBROWSE_GROUPDATA_ATLASES[CLASS_SORT_ORDER[i]] =
--         "groupfinder-icon-class-" .. string.lower(CLASS_SORT_ORDER[i])
-- This rebuilds it the same way rather than concatenating on demand, and the
-- difference is not cosmetic: CLASS_SORT_ORDER on camelot is the VANILLA NINE
-- (Camelot/Constants.lua:1-11, reached via Blizzard_FrameXMLBase.toc:16), so
-- building the name by hand would happily ask for
-- "groupfinder-icon-class-demonhunter" -- an atlas that exists in the dump but
-- for a class this client does not have -- where the table simply answers nil.
local CLASS_ICON_ATLAS = {}
for _, classFilename in ipairs(CLASS_SORT_ORDER) do
	CLASS_ICON_ATLAS[classFilename] = "groupfinder-icon-class-" .. string.lower(classFilename)
end

--- Look the atlas up, guarding the LOOKUP ITSELF.
---
--- A classFilename can arrive secret -- LfgSearchResultPlayerInfo grants
--- NeverSecret to nothing at all -- and "use as a table key" is on the list of
--- operations that error on one, alongside arithmetic, comparison and
--- concatenation (wow_addon_coder/references/secrets.md:69-70).
---
--- NOTE the predicate name that looks apt and is not:
--- SecretWhenLuaTableHasSecretKeys governs the guarded table APIs -- table.count,
--- table.isempty, table.getcountinfo -- returning a SECRET when the table they
--- are handed holds secret keys (LuaValuePredicatesDocumentation.lua:10-12,
--- LuaTableExtensionsDocumentation.lua:30, :113, :148). It is not the rule
--- being guarded against here.
---
--- Plain Lua does not notice either way: a lookup by a secret key fires no
--- metamethod and quietly returns nil, which is why the test harness cannot
--- falsify this guard.
function LFGF.ClassIconAtlas(classFilename)
	if classFilename == nil or not canaccessvalue(classFilename) then
		return nil
	end
	return CLASS_ICON_ATLAS[classFilename]
end

--- The class colour, or nil when there is none to be had.
---
--- Same hazard as the atlas: RAID_CLASS_COLORS is indexed BY the class name.
--- Blizzard does it unguarded (Browse.lua:442), which is legal for their
--- untainted code and not for ours.
function LFGF.ClassColor(classFilename)
	local readable = LFGF.Readable(classFilename, nil)
	if readable == nil then
		return nil
	end
	return RAID_CLASS_COLORS[readable]
end

--- The classes the Groups section's class filter hides groups by, from the
--- selection a search carries (FilterSnapshot's `groupExcludedClasses`,
--- core/filterpanel.lua): a fresh list, in the class filter's order
--- (CLASS_SORT_ORDER), of every class the client has that is selected with
--- true.
---
--- SECOND, the same classes as a set (class -> true), for the list's member
--- check (core/listpanel.lua), or nil while nothing is hidden.
---
--- EMPTY WHEN NOTHING NARROWS, by the author's rule: no class selected, and
--- every class selected, both mean no filter, as the Playstyle filter reads
--- its four (.claude/rules/group-class-filter.md). The dropdown's text and
--- tooltip (core/filterpanel_groupclasses.lua) and the list
--- (core/listpanel.lua) all ask this one function, so they cannot disagree.
--- Anything but a table selects nothing.
function LFGF.GroupClassesToHide(selected)
	local hide, hidden = {}, {}
	if type(selected) ~= "table" then
		return hide, nil
	end
	for _, classFilename in ipairs(CLASS_SORT_ORDER) do
		if selected[classFilename] == true then
			table.insert(hide, classFilename)
			hidden[classFilename] = true
		end
	end
	if #hide == 0 or #hide == #CLASS_SORT_ORDER then
		return {}, nil
	end
	return hide, hidden
end

-------------------------------------------------------
---------- Lists and text
-------------------------------------------------------

--- A name, or any text a player typed, as a font string should be given it:
--- every | doubled, because a font string reads | as the start of an escape
--- sequence (patterns-ui.md, "| In A FontString Needs Doubling"). What is saved
--- stays as typed.
function LFGF.ShownName(name)
	return (string.gsub(name, "|", "||"))
end

-- The list's place in its parent: 4 in on every side, with a 22 gutter on the
-- right for the scroll bar, which sits 4 beside the list.
local SCROLL_LIST_INSET = 4
local SCROLL_LIST_GUTTER = 22
local SCROLL_BAR_GAP = 4
-- The empty notice keeps this far in from each side of the list.
local NOTICE_INSET = 8

--- The scrolling list both panels draw (core/listpanel.lua, core/whisperlog.lua):
--- a WowScrollBoxList, a MinimalScrollBar beside it, and an empty notice in
--- the middle with no text and its default visibility. The caller sets the
--- notice's text and when it shows, and hands the box a view with
--- ScrollUtil.InitScrollBoxListWithScrollBar.
---
--- The notice spans the list and wraps, centred, so a sentence longer than
--- one line (a language pack's) breaks into lines instead of running past the
--- panel. Blizzard's Group Browser wraps its own at a fixed 240
--- (Blizzard_LFGVanilla_Browse.xml:457-462); this one wraps only when the text
--- needs it. LEFT and RIGHT also pin the vertical centre: it sits mid-list.
---
--- Returns box, bar, notice.
function LFGF.CreateScrollList(parent)
	local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", SCROLL_LIST_INSET, -SCROLL_LIST_INSET)
	box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLL_LIST_GUTTER, SCROLL_LIST_INSET)

	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", SCROLL_BAR_GAP, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", SCROLL_BAR_GAP, 0)

	local notice = S.Text(parent, 13, S.colors.muted, "CENTER")
	notice:SetPoint("LEFT", box, "LEFT", NOTICE_INSET, 0)
	notice:SetPoint("RIGHT", box, "RIGHT", -NOTICE_INSET, 0)
	notice:SetJustifyH("CENTER")
	notice:SetWordWrap(true)
	return box, bar, notice
end

--- Set `text` on a one-line font string, as wide as its words up to
--- `maxWidth`.
---
--- SetWidth(0) auto-sizes, so GetWidth then reports the rendered width
--- (Blizzard's own clamp, Blizzard_LFGVanilla_Browse.lua:456-470). Setting the
--- width to 0 first also lets a reused string shrink back.
---
--- A SECRET TEXT GIVES A SECRET WIDTH (GetWidth is SecretWhenAnchoringSecret,
--- SimpleScriptRegionAPIDocumentation.lua:325), and comparing one errors from
--- addon code. The setter takes the secret. The width is then left at its
--- natural size, or pinned to `unreadableWidth` when the caller gives one.
--- Leaving it is right for a name, whose neighbours hang off its right edge:
--- pinning every short name to the maximum would push them across the row.
function LFGF.SetClampedText(fontString, text, maxWidth, unreadableWidth)
	fontString:SetWidth(0)
	fontString:SetText(text)
	local width = fontString:GetWidth()
	if canaccessvalue(width) then
		if width > maxWidth then
			fontString:SetWidth(maxWidth)
		end
	elseif unreadableWidth then
		fontString:SetWidth(unreadableWidth)
	end
end

--- The click every control of the addon makes when it acts: Blizzard's
--- checkbox sound, as their own check buttons play it.
function LFGF.PlayClick()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

--- Whisper `text` to the player `name`, the way Blizzard's own /tell sends
--- one (SlashCommands.lua:886): "WHISPER" with the target fourth, languageID
--- nil, the documented default (ChatInfoDocumentation.lua:574).
---
--- The target is SecretArguments = "AllowedWhenUntainted"
--- (ChatInfoDocumentation.lua:568), so a name this code may not read would be
--- refused. Then nothing is sent. Returns whether it was sent.
function LFGF.Whisper(name, text)
	if not canaccessvalue(name) then
		return false
	end
	local target = type(name) == "string" and Quintessence.WhisperTarget(name)
	if not target or target == "" then return false end
	return Q.Call(C_ChatInfo.SendChatMessage, text, "WHISPER", nil, target)
end

-------------------------------------------------------
---------- Row action buttons
-------------------------------------------------------
-- ONE LOCK, TWO LISTS. core/listpanel.lua puts an invite and an ask-to-join on
-- a search result as icon buttons; core/whisperlog.lua puts Invite and Location
-- under an incoming whisper as text links (CreateRowActionLink, below). Sharing
-- the SHAPE is tidiness. Sharing the COOLDOWN is correctness: two copies would
-- be two independent locks, and the property worth having is that one action
-- paces every control the player can see, wherever it sits and however it is
-- drawn.
--
-- THE SHAPE IS BLIZZARD'S OWN IN-ROW BUTTON. A search-entry row already
-- contains one of these when the listing is yours: the delist button is a
-- UIMenuButtonStretchTemplate at 24x22 carrying a 12x12 icon
-- (Browse.xml:114-134). Matching it is why these look like they belong.
--
-- The template earns its keep beyond the chrome: its mixin owns the press,
-- swapping the silver art AND nudging self.Icon by a pixel
-- (SharedUIPanelTemplates.lua:929-945). So no button here is given an
-- OnMouseDown or OnMouseUp of its own -- setting either would silently take
-- both away. Naming the child texture `Icon` is what plugs into it, and the
-- hover tooltip is opt-in through tooltipText (:956-968).
local ROW_BUTTON_WIDTH, ROW_BUTTON_HEIGHT = 24, 22
local ROW_BUTTON_ICON_SIZE = 13

-- Natively 13x13 in the running client's atlas dump (AtlasInfo.lua:3276), so it
-- is drawn 1:1 rather than scaled.
LFGF.INVITE_ICON_ATLAS = "common-button-list-plus"

-- Acting on a listing or a whisper locks every one of these for two seconds.
-- Each sends something to another human being, so what is worth pacing is the
-- PLAYER, not the button: a per-button cooldown would leave a list of thirty
-- rows thirty clicks deep, which is the thing being prevented.
--
-- It does NOT cover Blizzard's right-click menus, by decision -- they are
-- theirs, they are several clicks deep, and the one-click path is the one that
-- needed pacing.
--
-- PUBLISHED because it is the addon's one delay: every control that locks
-- itself after a click waits this long, by the author's decision -- the Role
-- Check button (core/filterpanel.lua) keeps its own lock but reads this number.
LFGF.ACTION_COOLDOWN_SECONDS = 2
local ACTION_COOLDOWN_SECONDS = LFGF.ACTION_COOLDOWN_SECONDS

-- DISABLING IS INVISIBLE ON THIS TEMPLATE, so the greying is ours to do.
-- UIMenuButtonStretchTemplate declares an OnEnable and NO OnDisable
-- (SharedUIPanelTemplates.xml:846-853), and carries a DisabledFont but no
-- disabled TEXTURE (:861) -- that font is for a text button, and these hold an
-- icon. So Disable() alone stops the click and leaves the silver art exactly as
-- it was: a button that looks live and is not.
--
-- Desaturating is what "greyed out" means, and the alpha goes with it because
-- these icons are near-monochrome to begin with -- desaturating a white plus
-- changes nothing anyone can see.
local DISABLED_ICON_ALPHA = 0.5

-- Every button ever built, so the lock reaches the ones on rows that are
-- currently pooled or scrolled out of view as well. A plain table rather than a
-- weak one: frames are never garbage collected, so there is nothing to collect.
local rowButtons = {}
local actionsLocked = false

--- Put one button in step with the lock.
---
--- Called on EVERY row update as well as when the lock changes, because rows
--- are pooled and re-rendered whenever data arrives -- and data arrives on the
--- server's schedule, so a refresh lands mid-cooldown as a matter of course. A
--- lock applied only at click time would be undone by the next refresh.
---
--- A LINK needs only the first line: its disabled font object IS its greying
--- (see CreateRowActionLink). Only the icon buttons carry an Icon to dim, and
--- Ask to Join also a Check (core/listpanel.lua), dimmed with it.
local function DimIcon(texture)
	texture:SetDesaturated(actionsLocked)
	texture:SetAlpha(actionsLocked and DISABLED_ICON_ALPHA or 1)
end

function LFGF.ApplyActionLockTo(button)
	button:SetEnabled(not actionsLocked)
	if button.Icon then
		DimIcon(button.Icon)
	end
	if button.Check then
		DimIcon(button.Check)
	end
end

local function ApplyLockToAll()
	for _, button in ipairs(rowButtons) do
		LFGF.ApplyActionLockTo(button)
	end
end

--- Start the cooldown. Only ever called from an action that actually happened.
local function LockActions()
	actionsLocked = true
	ApplyLockToAll()

	C_Timer.After(ACTION_COOLDOWN_SECONDS, function()
		actionsLocked = false
		ApplyLockToAll()
	end)
end

-- ONE HANDLER FOR EVERY BUTTON AND LINK, because what differs between them is
-- the action, not the click. `action` is nil whenever the control is hidden, so
-- a click that somehow arrives on a stale frame does nothing rather than
-- repeating the last row's action.
--
-- THE LOCK IS CHECKED HERE AS WELL AS ENFORCED BY Disable(), a belt-and-braces
-- the stakes justify: Disable() is IsProtectedFunction
-- (SimpleButtonAPIDocumentation.lua:54-66), and if it were ever refused the
-- failure mode without this line is pestering a stranger repeatedly. With it,
-- the failure mode is a click that does nothing. A spec re-enables a locked
-- control behind the addon's back to prove this branch is live.
--
-- AN ACTION THAT RETURNS false STARTS NO COOLDOWN. The cooldown paces what
-- reaches other players; an action that ends up sending nothing -- Ask to Join
-- opening a whisper box for the player to type in -- says so, and leaves every
-- button live. Any other return, including none, locks as before.
local function RunAction(self)
	if actionsLocked or not self.action then
		return
	end
	LFGF.PlayClick()
	if self.action() ~= false then
		LockActions()
	end
end

--- One row button, built to the shared shape and wired to the shared lock.
---
--- Anchored to its row's RIGHT. Callers that have something else at that end --
--- a role display, a message -- re-anchor that thing to this button's LEFT, so
--- the space is reserved whether or not the button is showing.
function LFGF.CreateRowActionButton(row, atlas, tooltipText)
	local button = S.Button(row, "", ROW_BUTTON_WIDTH, ROW_BUTTON_HEIGHT, "ghost")
	button:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	button.tooltipText = tooltipText
	button:Hide()

	-- Named `Icon` because the template's mixin looks for exactly that when it
	-- nudges on press (SharedUIPanelTemplates.lua:932, :941).
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAtlas(atlas)
	icon:SetSize(ROW_BUTTON_ICON_SIZE, ROW_BUTTON_ICON_SIZE)
	icon:SetPoint("CENTER", button, "CENTER", 0, 0)
	button.Icon = icon

	-- The same highlight the delist button uses (Browse.xml:134).
	button:HookScript("OnEnter", function(self)
		LFGF.ShowTextTooltip(self, self.tooltipText)
	end)
	button:HookScript("OnLeave", GameTooltip_Hide)

	button:SetScript("OnClick", RunAction)

	table.insert(rowButtons, button)
	return button
end

-- A LINK'S LOOK: the font UICheckButtonTemplate gives its own label
-- (CheckButtonTemplates.xml:54), white on hover, and GameFontDisableSmall, its
-- grey counterpart (FontStyles.xml), when disabled. Blizzard ships no
-- hyperlink template, so the look is defined here, for every link the addon
-- draws.
local ROW_LINK_HEIGHT = 16

--- A text link in the addon's link look, and nothing else: a bare Button with
--- a font string and three font objects, sized to its words so the hit area is
--- what looks clickable. NOT on the action cooldown -- the caller sets its own
--- OnClick. For a link whose action only touches this addon's own UI, such as
--- the whisper log's Remove.
---
--- Returned unanchored: where a link sits is the caller's business.
function LFGF.CreateRowLink(parent, label)
	local link = CreateFrame("Button", nil, parent)
	local text = S.Text(link, 12, S.colors.gold)
	text:SetPoint("LEFT")
	text:SetText(label)
	local function paint(self)
		text:SetTextColor(unpack(not self:IsEnabled() and S.colors.muted or self.lfgHover and S.colors.text or S.colors.gold))
	end
	link:SetScript("OnEnter", function(self) self.lfgHover = true; paint(self) end)
	link:SetScript("OnLeave", function(self) self.lfgHover = false; paint(self) end)
	link:SetScript("OnEnable", paint)
	link:SetScript("OnDisable", paint)
	link:SetSize(text:GetStringWidth(), ROW_LINK_HEIGHT)
	return link
end

--- The addon's one tooltip for a control that explains itself: `title` in
--- white, then `text` as a gold, wrapped line, anchored to the control's right.
--- Blizzard's usual informational tooltip (GameTooltip_SetTitle,
--- GameTooltip_AddNormalLine, Blizzard_SharedXML/SharedTooltipTemplates.lua:
--- 128, :142); gold, not red, which Blizzard keeps for errors and lockouts.
--- GameTooltip_SetTitle clears the lines first, so each call starts afresh.
---
--- Used by every "why is this off" tooltip (Role Check, Save new filter, a
--- popup's Okay) and by a collapsed filter section's warning.
function LFGF.ShowTooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, title)
	GameTooltip_AddNormalLine(GameTooltip, text)
	GameTooltip:Show()
end

--- The addon's one plain tooltip: `text` alone, in white, anchored to the
--- control's right. Word-wrapped only when `wrap` is true.
---
--- SetText takes SIX arguments, (text, r, g, b, alpha, wrap), and the colour is
--- not optional (FrameAPITooltipDocumentation.lua, SetText: colorR/G/B
--- Nilable = false). Alpha comes BEFORE wrap, so a five-argument call puts
--- `wrap` into alpha. SetText accepts a secret text (ConditionalSecret), but
--- not nil.
function LFGF.ShowTextTooltip(owner, text, wrap)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(text, 1, 1, 1, 1, wrap)
	GameTooltip:Show()
end

--- A small icon that explains itself on hover: a Frame `size` square on
--- `parent`, one texture covering it (`icon.Icon`, for the caller to dress),
--- `showTooltip` as its OnEnter and GameTooltip_Hide as its OnLeave. Starts
--- hidden.
---
--- A FRAME, not a bare texture, so it can take the mouse for its tooltip. But
--- only the MOTION half: clicks are left off, so a click on the icon lands on
--- whatever is beneath it. Blizzard's own shape for a region that only
--- explains itself (CooldownViewer.lua:326-328; the player frame's health bar,
--- Mainline/PlayerFrame.xml:196). Both setters are in the running client's
--- widget dump (WidgetAPI.lua:123-124).
---
--- The cost, known and accepted: moving onto the icon is leaving whatever is
--- beneath it, so that frame's own hover (tooltip, highlight) gives way to the
--- icon's while the mouse is over it.
---
--- Shared by the guild/friend icon (core/relations.lua) and a collapsed filter
--- section's warning (core/filterpanel_shared.lua).
function LFGF.CreateTooltipIcon(parent, size, showTooltip)
	local icon = CreateFrame("Frame", nil, parent)
	icon:SetSize(size, size)
	icon:SetMouseMotionEnabled(true)
	icon:SetMouseClickEnabled(false)

	local texture = icon:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints(icon)
	icon.Icon = texture

	icon:SetScript("OnEnter", showTooltip)
	icon:SetScript("OnLeave", GameTooltip_Hide)
	icon:Hide()
	return icon
end

--- The same kind of action as CreateRowActionButton, drawn as a text link
--- (CreateRowLink above).
---
--- SAME LIST, SAME HANDLER, SAME LOCK. Being in rowButtons is what makes the
--- cooldown reach it, and the disabled font object is what makes the lock
--- visible -- which is why ApplyActionLockTo needs nothing extra for a link.
function LFGF.CreateRowActionLink(parent, label)
	local link = LFGF.CreateRowLink(parent, label)
	link:SetScript("OnClick", RunAction)

	table.insert(rowButtons, link)
	return link
end

-- REMOVED 2026-09-22: the restriction guard (LFGF.ProtectedActionsAllowed /
-- ProtectedActionBlocker). Why, at the one call it guarded: RequestSearch in
-- core/filterpanel.lua; history in .claude/rules/groupfinder-window.md.

-------------------------------------------------------
---------- The load greeting
-------------------------------------------------------

-- ONE LINE, NAMING THE BUILD AND THE WAY IN.
--
-- Not decoration. This addon is hand-copied to a test machine, and without it
-- "did the version I just copied actually load" is a question only a file
-- listing can answer -- which is exactly how two silent non-updates were
-- diagnosed during development.
--
-- An earlier greeting said "Hello from LFG Forever!" and was removed for being
-- noise once the addon had a window of its own. The difference is that this
-- one carries what a tester and a bug report both need: which build, and how
-- to open it.
--
-- THE VERSION COMES FROM THE TOC, via C_AddOns.GetAddOnMetadata
-- (GlobalAPI.lua:205). A version typed in here would be a second place to bump
-- on every release, and the one that gets forgotten. Nilable -- a TOC without
-- a Version line is legal -- and losing the version is not a reason to lose
-- the line saying the addon loaded, so the format drops that segment instead.
--
-- EventUtil.ContinueOnAddOnLoaded(addOnName, callback)
--   Blizzard_SharedXML/EventUtil.lua:67-75, loaded unconditionally by
--   Blizzard_SharedXML.toc:37 (verified with `element_check.py global
--   EventUtil`).
--
-- Preferred over a hand-rolled ADDON_LOADED frame for two reasons:
--   * it unregisters itself after the first matching event, so the callback
--     cannot run twice;
--   * it fires straight away if the addon is somehow already loaded, so there
--     is no path where the message is silently lost.
--
-- Called with our own name from our own file, C_AddOns.IsAddOnLoaded returns
-- isLoaded = false (we are still *loading*), so this takes the register branch
-- and fires on our own ADDON_LOADED.

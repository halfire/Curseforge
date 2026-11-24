-- QuinteLFG -- core/filterpanel.lua
--
-- The right-hand column: filters that narrow the list of groups and players.
--
-- THE CONTRACT
-- ------------
-- This file is a FACTORY. It creates and fills its own inset and returns it
-- UNANCHORED; core/window.lua places it. That split keeps each concern where it
-- can be read in one piece:
--
--   * this file  -- what a filter panel IS and how wide it needs to be
--   * window.lua -- where the two columns sit relative to each other
--
-- If this file anchored itself, the two-column layout would be spread across
-- three files and nobody could see it whole.
--
-- THE DEFAULT FILTER ROW
-- ----------------------
-- Category dropdown, activity dropdown, then a Search button where Blizzard
-- has its refresh button -- copied from Blizzard's camelot Browse panel
-- (Blizzard_LFGVanilla_Browse.lua:1041-1259 and
-- Mainline/Blizzard_LFGVanilla_Browse.xml:414-479) so the two read as one UI.
--
-- SECRET VALUES: this file is on the safe side of that line. Only five
-- C_LFGList getters are SecretInChatMessagingLockdown -- GetActiveEntryInfo,
-- GetApplicantInfo, GetSearchResultInfo, GetSearchResultLeaderInfo,
-- GetSearchResultPlayerInfo. Category and activity info are NOT among them, so
-- their names can be read and formatted normally. The
-- SecretArguments = "AllowedWhenUntainted" on GetLfgCategoryInfo constrains
-- what may be passed IN, and this file passes plain numbers. The results list
-- is where the care is needed, not here. The one read of GetActiveEntryInfo
-- (LFGF.Activities) takes only its activityIDs, which the documentation marks
-- NeverSecret (LFGListInfoDocumentation.lua:938).
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
local StaticPopupDialogs, StaticPopup_Show = LFGF.Dialogs, LFGF.ShowDialog
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L
local S = Quintessence.Style
-- The section builders and the grid they share with
-- core/filterpanel_miscellaneous.lua, from core/filterpanel_shared.lua (loaded
-- just before this file). Taken as locals so this file reads as it did before
-- they moved.
local Shared = LFGF.FilterShared
local ROW_PADDING = Shared.ROW_PADDING
local SECTION_TOP_GAP = Shared.SECTION_TOP_GAP
local SECTION_TITLE_TO_RULE_GAP = Shared.SECTION_TITLE_TO_RULE_GAP
local SECTION_RULE_HEIGHT = Shared.SECTION_RULE_HEIGHT
local SECTION_RULE_TO_CONTENT_GAP = Shared.SECTION_RULE_TO_CONTENT_GAP
local ROLE_ROW_HEIGHT = Shared.ROLE_ROW_HEIGHT
local ROLE_ICON_SIZE = Shared.ROLE_ICON_SIZE
local ROLE_BOX_TO_ICON_GAP = Shared.ROLE_BOX_TO_ICON_GAP
local ROLE_ICON_TO_LABEL_GAP = Shared.ROLE_ICON_TO_LABEL_GAP
local BuildSection = Shared.BuildSection
local SizeSection = Shared.SizeSection
local GridCell = Shared.GridCell
local BuildRoleCheckSection = Shared.BuildRoleCheckSection
local SetSectionCollapsed = Shared.SetSectionCollapsed
local RaiseOverHeader = Shared.RaiseOverHeader
local UpdateSectionWarning = Shared.UpdateSectionWarning

-- How much room the filters need is a question about filters, so it lives here
-- rather than with the window's layout constants. Settings uses 199 for its
-- category column (Blizzard_SettingsPanel.xml:59); checkboxes, dropdowns and
-- their labels need considerably more if they are not to wrap.
-- 600, and it is the GROUP SECTION that sets it. Three checkboxes carrying
-- "Tank role available" / "Healer role available" / "Damage role available" on
-- one row need about 564 of content, plus 12 padding either side. The window is
-- 1165, so the list column still gets roughly 546 -- comfortably more than the
-- 312-wide rows Blizzard's own template draws.
--
-- The number and ROLE_TO_ROLE_GAP move together: at the 22 gap this row wanted
-- 608 and would overflow here. The "fits inside the panel" examples are what
-- hold the pair honest.
--
-- A MINIMUM since language packs (core/locale.lua): MeasureLayout widens the
-- panel only when a translated label would not fit it. English fits, so in
-- English the panel is exactly this.
local FILTER_PANEL_WIDTH = 600

-- Blizzard's own widget sizes: SetWidth(118) and SetWidth(167) in the two
-- dropdown OnLoads (Browse.lua:1042, :1108). (Their 32x32 refresh button,
-- Browse.xml:448, is a labelled Search button here, sized below.)
local CATEGORY_DROPDOWN_WIDTH = 118
local ACTIVITY_DROPDOWN_WIDTH = 167
-- The size Blizzard gives a labelled panel button in THIS addon: 111x28, the
-- same as their Send Message and Back buttons (Browse.xml:526,
-- Listing.xml:309).
local SEARCH_BUTTON_WIDTH = 111
local SEARCH_BUTTON_HEIGHT = 28

-- Blizzard's own gaps, kept exactly: the activity dropdown hangs 15 off the
-- category dropdown's right edge and the refresh button 9 off the activity
-- dropdown's (Browse.xml:427, :450). Our Search button takes the refresh
-- button's 9.
local CATEGORY_TO_ACTIVITY_GAP = 15
local ACTIVITY_TO_SEARCH_GAP = 9



-- THE TAB STRIP sits in the gap between the window's title bar and this inset,
-- which is empty: the inset starts 60 below the frame's top (core/window.lua
-- INSET_TOP) and the title bar ends around 28, so a 32-high tab fits with room
-- to spare. That is exactly where MacroFrame puts its own top tabs
-- (Blizzard_MacroUI.xml:185, TOPLEFT x=51 y=-28).
--
-- The x inset is FriendsFrame's, the closest camelot analogue -- its TabSystem
-- hangs at x=18 (Camelot/FriendsFrame.xml:419).

-- ROLE CHECK IS THE SECONDARY BUTTON of the row, so it is narrower than
-- Search. It is fitted to its label by Blizzard's own
-- UIButtonFitToTextBehaviorMixin:FitToText (SecureUIPanelTemplates.lua:88-92),
-- which UIPanelButtonTemplate carries: width = label width + padding. The
-- template's padding is 40 (SecureUIPanelTemplates.xml:42), about 106 in
-- English and hardly narrower than Search's 111; 16, by the author's choice,
-- gives about 82. That is less than the template's two 12-wide end caps
-- (:44-57), so the label runs a little onto them. A longer translation of
-- ROLE_POLL widens the button rather than overflowing it. (Blizzard's own is a
-- fixed 120, Listing.xml:414, on a panel with nothing else to rank against.)
-- It takes the Search button's height, so the row keeps one top edge.
local ROLE_CHECK_LABEL_PADDING = 16

-- What the search row takes before Role Check: category, activity and Search
-- with their gaps. What the panel leaves over after these (searchRowSpare, in
-- MeasureLayout) is Role Check's: hung off Search, it takes its own width out
-- of that and the rest is the gap, so its right edge sits ROW_PADDING in from
-- the panel's, mirroring the category dropdown's inset on the left.
local SEARCH_ROW_FIXED_WIDTH = CATEGORY_DROPDOWN_WIDTH + CATEGORY_TO_ACTIVITY_GAP
	+ ACTIVITY_DROPDOWN_WIDTH + ACTIVITY_TO_SEARCH_GAP + SEARCH_BUTTON_WIDTH

-- THE SETTINGS GEAR ENDS THE ROW, beyond Role Check (BuildSettingsGear). Its
-- art is Blizzard's own camelot Group Finder gear, LFGOptionsButton
-- (Mainline/Blizzard_LFGVanilla_ParentFrame.xml:4-20): the OptionsIcon-Brown
-- atlas (16x16, AtlasInfo.lua) at alpha 0.8, full on hover, nudged (1, -1)
-- while pressed (Blizzard_LFGVanilla_ParentFrame.lua:290-306). Copied, not
-- inherited: that template is defined inside the LoadOnDemand Group Finder,
-- so CreateFrame against it would error until that addon is in. It hangs off
-- Role Check by the row's own gap, the activity dropdown's to Search.
local SETTINGS_GEAR_SIZE = 16
local SETTINGS_GEAR_ATLAS = "OptionsIcon-Brown"
local SETTINGS_GEAR_ALPHA = 0.8
local SETTINGS_GEAR_HOVER_ALPHA = 1.0
local SETTINGS_GEAR_GAP = ACTIVITY_TO_SEARCH_GAP
local SETTINGS_GEAR_PRESS_X, SETTINGS_GEAR_PRESS_Y = 1, -1

-- THE SECTION HEADERS END IN A TEXT LINK, not an icon: "Reset filters" on
-- "Find groups by role", "Clear chat" on "Messages from players", "Clear
-- player rating" on "Recent allies". Five icons were tried for Clear chat
-- (common-search-clearbutton, GM-raidMarker-remove, transmog-icon-remove,
-- communities-icon-redx, communities-chat-icon-minus) and none read right in
-- the client, and Reset filters' funnel (Map-Filter-Button) said "open
-- filters" as readily as "reset them". Words say it; see AddHeaderLink.

-- Flush: a top tab's art is drawn to meet the panel it belongs to, and
-- FriendsFrame leaves no gap either. A seam here would be the first thing to
-- adjust after seeing it in the client.

-- The least tab a label gets on each side, by the author's request (a
-- screenshot of the English Player ratings tab, its label all but touching
-- both edges). About what Blizzard's Transmog top tabs give theirs: textPadding
-- 17 plus the template's 10, halved (Blizzard_TransmogTemplates.xml:612,
-- TabSystemTemplates.lua:233-235). See GiveTabLabelsRoom.

-- WowStyle1DropdownTemplate's own height -- <Size x="120" y="25"/> at
-- Blizzard_Menu/Mainline/MenuTemplates.xml:4, the file camelot loads
-- ([Family]\MenuTemplates.xml, Blizzard_Menu.toc:21). The dropdowns never set
-- a height, so this is the number the client gives them, and naming it keeps
-- the two sides of the subtraction below symmetrical.
local DROPDOWN_HEIGHT = 25

-- The Search button is the filter row's tallest element -- 28 against the
-- dropdowns' 25 -- and it is centred on them, so it overhangs the dropdown's
-- bottom edge by half the difference.
local FILTER_ROW_OVERHANG = (SEARCH_BUTTON_HEIGHT - DROPDOWN_HEIGHT) / 2



-- THE LEVEL ROW: a "Player level range" label, then Blizzard's LevelRangeFrameTemplate
-- (Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:382, 80x22, its
-- MinLevel box 8 in). The template's first box draws its border 5 to the left
-- of the box (InputBoxVisualTemplate, :46-51), so the border starts 3 into the
-- frame and this gap leaves about 7 between the word and the border. Shared
-- with the Playstyle row (core/filterpanel_shared.lua).
local LEVEL_LABEL_TO_RANGE_GAP = Shared.ROW_LABEL_TO_CONTROL_GAP
-- Sections lay out on a GRID: fixed column width, fixed row height, each box
-- at its own cell. That is what keeps "Has healer" under "Healer role
-- available" and every class under the role above it, without any box
-- depending on how long its neighbour's label happens to be.
--
-- The cost is the other side of that coin: a label that outgrows its column
-- would OVERLAP the next one rather than pushing it along. So both widths are
-- MINIMUMS: MeasureLayout widens a grid's columns, all rows at once, only when
-- one of its labels would not fit -- which a translated label may not
-- (core/locale.lua). English fits, so in English they are exactly these. The
-- "stays inside its column" examples are what hold each of these honest.
--
--   player -- 4 columns; the widest item is a class at ~100 ("Warrior")
--   group  -- 3 columns; the widest item is ~184 ("Damage role available")
--
-- At 576 of usable width, 4x120 = 480 and 3x190 = 570 both fit.
local PLAYER_COLUMN_WIDTH = 120

-- The class section's two bulk toggles are TEXT LINKS (LFGF.CreateRowLink),
-- not panel buttons: a panel button is the heaviest thing in a grid of
-- checkboxes and competes with Search for the eye. The links' font is the one
-- UICheckButtonTemplate gives its own label (CheckButtonTemplates.xml:54), so
-- they sit at the weight of the class names beside them.
local GROUP_COLUMN_WIDTH = 190
-- A NUDGE OFF THE CELL EDGE, and deliberately a tiny one.
--
-- The first attempt here lined the links up with the class NAMES -- the box,
-- the gap, the class icon and the gap after it, 58 points, summed from the
-- chain BuildRoleCheck builds when it re-anchors check.Text. That number is
-- derivable and it looked wrong: it detached the pair from the grid they sit
-- in, which is a reminder that "derived from Blizzard's own constants" is an
-- argument about provenance, not about whether it looks right.
--
-- So this one is what it says: a small nudge, by eye. Nothing derives it and
-- nothing should -- two was too little, six is the answer, and the spec asserts
-- the exact value because there is no reasoning to re-derive it from. It lives
-- in core/filterpanel_shared.lua since the Playstyle row starts there too.
local CLASS_LINK_INSET_X = Shared.ROW_LABEL_INSET_X

-- THE LEVEL LABEL TAKES THE SAME NUDGE, so every word in the grid starts at one
-- inset. At the cell edge it read as shifted left of the Tank box above it: the
-- checkbox frame is 32 wide and its art (Interface\Buttons\UI-CheckBox-Up,
-- CheckButtonTemplates.xml:43 -- a file, so no source states its margin)
-- draws the box inside that. Reported from the client, 0.10.0-dev.2.
local LEVEL_LABEL_INSET_X = CLASS_LINK_INSET_X

-- The titles are deliberately parallel -- "Find players by role and level",
-- "Find players by class", "Find groups by role" -- because each names the
-- SUBJECT and then the DIMENSION, which is exactly what distinguishes the
-- sections from one another. The first gained "and level" with its Level row
-- (0.10.0-dev.1), by the author's wording.
--
-- FIND, not Filter, and they diverge from their neighbour on that: the activity
-- dropdown reads "Filter by activity", but that string is Blizzard's
-- (LFGBROWSE_ACTIVITY_HEADER_DEFAULT) and not ours to reword.
--
-- Published so the spec and any future section can name the same string rather
-- than repeating the text, which is what made rewording these a one-line
-- change. The cost, stated: a spec that names the field cannot also pin the
-- WORDS, so a reword is not something the suite notices. That is the right
-- trade for copy.
--
-- NONE of them has a GlobalString, unlike their neighbour the activity
-- dropdown's LFGBROWSE_ACTIVITY_HEADER_DEFAULT ("Filter by activity"), so each
-- is English unless a language pack replaces it (core/locale.lua).
--
-- Three of the four sections, in the order they stack; the fourth,
-- Miscellaneous, publishes its own title (core/filterpanel_miscellaneous.lua).
-- Roles and classes both narrow
-- PLAYERS and could have shared one heading; they do not, because they are
-- different questions and nine class boxes appended to a role row read as one
-- long list of unrelated things.
LFGF.ROLE_SECTION_TITLE = L.ROLE_SECTION_TITLE
LFGF.CLASS_SECTION_TITLE = L.CLASS_SECTION_TITLE
LFGF.GROUP_SECTION_TITLE = L.GROUP_SECTION_TITLE

-- The tab the three sections above live on. Its sibling, LFGF.WHISPERS_TAB_TITLE,
-- is published by core/whisperlog.lua -- each tab's title lives with the thing
-- it names.
LFGF.FILTERS_TAB_TITLE = L.FILTERS_TAB_TITLE

-- The two section-header links' labels, by the author's choice: "Reset
-- filters" and "Clear chat". RESET_TO_DEFAULT is a real global ("Reset To
-- Default", GlobalStrings/enUS.lua:18675) and is not used: this link resets
-- these filters, not the addon's settings. Neither label is a GlobalString.
LFGF.RESET_FILTERS_LABEL = L.RESET_FILTERS

-- The class section's two bulk toggles. Blizzard ships a matched pair for
-- exactly this job -- CHECK_ALL / UNCHECK_ALL ("Check All" / "Uncheck All",
-- GlobalStrings/enUS.lua:4029, :23823), which its own Group Finder uses to bulk
-- toggle a dungeon filter's checkboxes (Mainline/LFGList.lua:2583, :2593). They
-- are NOT used here, because the wording asked for was "Select all" /
-- "Unselect all" and these read about the selection rather than the boxes. The
-- cost is that these two are ours to translate, like the two labels above them.
LFGF.UNSELECT_ALL_CLASSES_LABEL = L.UNSELECT_ALL
LFGF.SELECT_ALL_CLASSES_LABEL = L.SELECT_ALL
LFGF.CLEAR_CHAT_LABEL = L.CLEAR_CHAT

-- The Level row's label, the author's wording (0.10.0-dev.4). It was
-- Blizzard's LEVEL ("Level"), which did not say whose level it filters. Ours,
-- like the section titles.
LFGF.LEVEL_ROW_LABEL = L.LEVEL_RANGE_LABEL

-- MY FILTERS, the author's wording (0.11.0-dev.3): a dropdown reading
-- "My filters" and a "Save new filter" link, left of "Reset filters" on the
-- same title line. Ours, like the section titles. The popup's buttons are
-- Blizzard's own OKAY ("Okay") and CANCEL by default, by the author's choice.
LFGF.MY_FILTERS_LABEL = L.MY_FILTERS
LFGF.SAVE_NEW_FILTER_LABEL = L.SAVE_NEW_FILTER
LFGF.MY_FILTER_POPUP = "QUINTELFG_SAVE_MY_FILTER"


-- The three roles, in Blizzard's own order (LFGBROWSE_GROUPDATA_ROLE_ORDER,
-- Browse.lua:10). Each row carries what the UI needs and what the filter needs:
--
--   atlas -- the same icons the result rows use (Browse.lua:14-20), so the
--            filter and the list agree visually
--   label -- a GlobalString by default (core/locale.lua), so it localises.
--            Note DAMAGER is "Damage", not "DPS" (enUS.lua:5619)
--   field -- the LFGRoles key the list panel tests, which is `dps` where the
--            role token is DAMAGER. The mapping lives here, once, rather than
--            being re-derived at the point of use.
local PLAYER_ROLE_ROWS = { {
	{ set = "roles", field = "tank",   atlas = "groupfinder-icon-role-large-tank", label = L.ROLE_TANK },
	{ set = "roles", field = "healer", atlas = "groupfinder-icon-role-large-heal", label = L.ROLE_HEALER },
	{ set = "roles", field = "dps",    atlas = "groupfinder-icon-role-large-dps",  label = L.ROLE_DAMAGE },
} }

-- Every class the client has, FOUR to a row, under the roles in the same
-- section: both narrow the same thing, so they belong under one heading.
--
-- CLASS_SORT_ORDER is the order AND the membership, and on camelot it is the
-- vanilla nine (Camelot/Constants.lua:1-11, reached via
-- Blizzard_FrameXMLBase.toc:16). Taking it from the client is what keeps Death
-- Knights and the rest out without a per-class decision here -- and it is the
-- same list Blizzard builds its class-icon atlases from (Browse.lua:23-25), so
-- every entry is guaranteed an icon.
--
-- Labels come from core/locale.lua's class names, which are
-- LOCALIZED_CLASS_NAMES_MALE (Blizzard_FrameXMLBase/Constants.lua:37, loaded on
-- camelot by toc:18) unless a language pack replaces them, rather than the
-- token, which is the uppercase English filename. A class core/locale.lua does
-- not name falls back to Blizzard's name, then to the token.
local CLASSES_PER_ROW = 4

local function BuildClassRows()
	local rows = {}

	for index, classFilename in ipairs(CLASS_SORT_ORDER) do
		if index % CLASSES_PER_ROW == 1 then
			table.insert(rows, {})
		end
		table.insert(rows[#rows], {
			set = "classes",
			field = classFilename,
			atlas = "groupfinder-icon-class-" .. string.lower(classFilename),
			label = L["CLASS_" .. classFilename] or LOCALIZED_CLASS_NAMES_MALE[classFilename]
				or classFilename,
		})
	end

	return rows
end

-- The group criteria, as ROWS. The same three icons as above, asking a
-- different question of a different subject -- and asking it twice, once each
-- way round:
--
--   row 1  "<role> role available" -- the group is SHORT of that role
--   row 2  "Has <role>"            -- it already has enough
--
-- Two rows because three of these labels do not share one with the other two,
-- and because the split is the meaning: the first row is what a group still
-- wants, the second is what it already brings.
--
-- All five labels are OUR words (core/locale.lua); the client has no strings for
-- any of them.
local GROUP_FILTER_ROWS = {
	{
		{ set = "group", field = "tankAvailable",   atlas = "groupfinder-icon-role-large-tank",
		  label = L.GROUP_TANK_AVAILABLE },
		{ set = "group", field = "healerAvailable", atlas = "groupfinder-icon-role-large-heal",
		  label = L.GROUP_HEALER_AVAILABLE },
		{ set = "group", field = "damageAvailable", atlas = "groupfinder-icon-role-large-dps",
		  label = L.GROUP_DAMAGE_AVAILABLE },
	},
	{
		{ set = "group", field = "hasTank",   atlas = "groupfinder-icon-role-large-tank",
		  label = L.GROUP_HAS_TANK },
		{ set = "group", field = "hasHealer", atlas = "groupfinder-icon-role-large-heal",
		  label = L.GROUP_HAS_HEALER },
	},
}

-------------------------------------------------------
---------- Activity selection state
-------------------------------------------------------
-- Mirrors LFGBrowseActivityDropdownMixin's selectedValues (Browse.lua:1107).

local function ActivityIsSelected(panel, activityID)
	return tContains(panel.selectedActivityIDs, activityID)
end

local function ActivityToggle(panel, activityID)
	local index = tIndexOf(panel.selectedActivityIDs, activityID)
	if index then
		table.remove(panel.selectedActivityIDs, index)
	else
		table.insert(panel.selectedActivityIDs, activityID)
	end
	panel:UpdateActivityHeader()
end

local function ActivityReset(panel)
	panel.selectedActivityIDs = {}
	panel:UpdateActivityHeader()
end

-- How many dropped activities the chat line names before it counts the rest:
-- "A, B, C and 2 more".
local NAMED_DROPPED_ACTIVITIES = 3

--- Two or more names for the chat line: "A and B", "A, B and C", then
--- "A, B, C and 2 more". Every word from core/locale.lua.
local function JoinDroppedNames(names)
	local shown = {}
	for index = 1, math.min(#names, NAMED_DROPPED_ACTIVITIES) do
		shown[index] = names[index]
	end
	if #names > NAMED_DROPPED_ACTIVITIES then
		table.insert(shown, L.ACTIVITY_LIST_MORE_FORMAT:format(#names - NAMED_DROPPED_ACTIVITIES))
	end
	return table.concat(shown, L.ACTIVITY_LIST_SEPARATOR, 1, #shown - 1)
		.. L.ACTIVITY_LIST_LAST_SEPARATOR .. shown[#shown]
end

--- Untick every activity that `offered` does not hold, and say so in ONE
--- chat line. Returns whether anything was unticked. It never searches.
---
--- WHY. The ticks are kept apart from the list they were picked from, and
--- that list changes under them: LFGF.Activities leaves out an activity the
--- player's level has left, or one offered only while it was in the player's
--- own listing, and the server can stop offering one. A tick the menu no
--- longer shows cannot be unticked, and Search would keep sending it.
--- Blizzard's Browse tab has the same gap: its selectedValues are never
--- checked again (LFGBrowseActivityDropdownMixin, Blizzard_LFGVanilla_Browse.lua).
---
--- `offered` is LFGF.Activities for the category, so "Show all level
--- activities" counts as it does everywhere: while it is on, nothing drops
--- for level, only what the server stopped offering.
---
--- The names are the menu's (LFGUtil_GetActivityInfoName), in the order they
--- were ticked. An activity the client no longer describes is unticked with no
--- name (GetActivityInfoTable is MayReturnNothing,
--- LFGListInfoDocumentation.lua:186). See .claude/rules/level-range-filter.md.
local function DropUnofferedActivities(panel, offered)
	local kept, names, dropped = {}, {}, false
	for _, activityID in ipairs(panel.selectedActivityIDs) do
		if tContains(offered, activityID) then
			table.insert(kept, activityID)
		else
			dropped = true
			local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
			if activityInfo then
				table.insert(names, LFGUtil_GetActivityInfoName(activityInfo))
			end
		end
	end
	if not dropped then
		return false
	end

	panel.selectedActivityIDs = kept
	panel:UpdateActivityHeader()
	local setting = L.SETTINGS_SHOW_ALL_LEVELS_LABEL
	if #names == 1 then
		LFGF.Print(L.ACTIVITY_NO_LONGER_OFFERED_FORMAT:format(names[1], names[1], setting))
	elseif #names > 1 then
		LFGF.Print(L.ACTIVITIES_NO_LONGER_OFFERED_FORMAT:format(JoinDroppedNames(names), setting))
	end
	return true
end

-------------------------------------------------------
---------- Level ranges
-------------------------------------------------------

--- The activities a category offers: what the dropdowns list, and what a
--- search with nothing ticked asks for.
---
--- BLIZZARD'S RULE, UNDER OUR OWN SETTING. Blizzard's Group Finder drops every
--- activity whose suggested level range does not hold the player's level, unless
--- its CVar disableSuggestedLevelActivityFilter is on
--- (LFGUtil_GetFilteredActivities, Blizzard_LFGVanilla_ParentFrame.lua:259-280).
--- This is the same rule with LFGF.ShowAllLevelRanges() in the CVar's place:
--- the addon never reads or writes Blizzard's CVar (core/main.lua says why), so
--- ticking the option in one finder does not change the other.
---
--- The rule, as Blizzard's:
---   * out of range means minLevelSuggestion above the player's level, or
---     maxLevelSuggestion below it; a 0 means no limit on that side, and both
---     ends count as inside;
---   * an activity of the player's own listing is always kept, so they can
---     find their own group. activityIDs is NeverSecret
---     (LFGListInfoDocumentation.lua:938); GetActiveEntryInfo answers nothing
---     when there is no listing (MayReturnNothing, :141).
---
--- ONE DIFFERENCE: an activity with no info table is KEPT. GetActivityInfoTable
--- is MayReturnNothing (:186) and Blizzard indexes it unguarded; here it is let
--- through, the way the filters let a listing through when they cannot check it.
---
--- UnitLevel carries no secret predicate (UnitDocumentation.lua:2474-2487), and
--- everything else read here is a plain number. Only engine API, so unlike the
--- LFGUtil_* helpers this works before the LoadOnDemand Group Finder is in.
function LFGF.Activities(categoryID, activityGroupID)
	local activities = LFGF.Readable(C_LFGList.GetAvailableActivities(categoryID, activityGroupID), nil) or {}
	if LFGF.ShowAllLevelRanges() then
		return activities
	end

	local activeEntryInfo = LFGF.Readable(C_LFGList.GetActiveEntryInfo(), nil)
	local listed = activeEntryInfo and LFGF.Readable(activeEntryInfo.activityIDs, nil) or {}
	local playerLevel = LFGF.Readable(UnitLevel("player"), nil)
	if not playerLevel then return activities end

	local kept = {}
	for _, activityID in ipairs(activities) do
		local keep = true
		if not tContains(listed, activityID) then
			local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
			if activityInfo then
				local minLevel = activityInfo.minLevelSuggestion
				local maxLevel = activityInfo.maxLevelSuggestion
				keep = not ((minLevel > 0 and minLevel > playerLevel)
					or (maxLevel > 0 and maxLevel < playerLevel))
			end
		end
		if keep then
			table.insert(kept, activityID)
		end
	end
	return kept
end

-------------------------------------------------------
---------- The dropdowns
-------------------------------------------------------

--- The categories the menu would actually OFFER, in menu order.
---
--- Not simply GetAvailableCategories: the menu drops a category with no
--- activities, and one whose info cannot be read. Both the menu and the
--- auto-selection below walk this, so "the first category" means the first one
--- the player can actually see -- auto-selecting something invisible would be
--- worse than selecting nothing.
local function SelectableCategories()
	local selectable = {}

	-- The activity menu a category leads to is built from LFGUtil_* helpers
	-- that live INSIDE the LoadOnDemand Group Finder
	-- (Blizzard_LFGVanilla_ParentFrame.lua:185-280), so they do not exist until
	-- that addon is in -- and this function is also called while the panel is
	-- BUILT, on the first /lfg, which can come first. (LFGF.Activities itself
	-- needs only engine API.)
	--
	-- No categories is the honest answer then, and
	-- LFG_LIST_AVAILABILITY_UPDATE is what picks it up afterwards.
	if not C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder_VanillaStyle") then
		return selectable
	end

	for _, categoryID in ipairs(C_LFGList.GetAvailableCategories()) do
		if #LFGF.Activities(categoryID) ~= 0 then
			local categoryInfo = C_LFGList.GetLfgCategoryInfo(categoryID)
			if categoryInfo then
				table.insert(selectable, { id = categoryID, name = categoryInfo.name })
			end
		end
	end

	return selectable
end

-- Declared before SetupCategoryMenu because the menu's generator closes over
-- it, and assigned after because it calls the menu back.
local SelectCategory

--- Category radios, from Browse.lua:1050-1081.
---
--- The one behaviour worth naming: a category whose filtered activity list is
--- empty is SKIPPED entirely (:1074), so the player is never offered a category
--- that would produce nothing.
local function SetupCategoryMenu(panel)
	-- SetupMenu's generator is called as (dropdown, rootDescription)
	-- (DropdownButton.lua:237). The category menu never needs the dropdown
	-- itself, so the first parameter is left unnamed rather than unused.
	panel.CategoryDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_LFGF_CATEGORY")

		local function IsSelected(value)
			return panel.selectedCategoryID == value
		end
		local function SetSelected(value)
			SelectCategory(panel, value)
		end

		local categories = SelectableCategories()
		if #categories == 0 then
			rootDescription:CreateRadio(L.CATEGORY_NONE)
			return
		end

		for _, category in ipairs(categories) do
			rootDescription:CreateRadio(category.name, IsSelected, SetSelected, category.id)
		end
	end)
end

--- Choose a category, from the menu or from the auto-selection.
---
--- One function so the two cannot drift: picking a category has side effects
--- beyond the field, and an auto-selection that set only the field would leave
--- a stale activity menu and a disabled Search button.
function SelectCategory(panel, categoryID)
	panel.selectedCategoryID = categoryID
	-- Browse.lua:1096-1099 -- choosing a category clears the activity filter,
	-- because the old activities belong to the old category.
	ActivityReset(panel)
	SetupCategoryMenu(panel)
	panel:SetupActivityMenu()
	panel:UpdateSearchState()
end

--- Pick the first category for the player, if they have not picked one.
---
--- A panel that opens with no category cannot search: the Search button is
--- disabled, and C_LFGList.Search refuses a categoryID of 0. So the player's
--- first click would always be the same click, and it is made for them. On this
--- client the first selectable category is Dungeons (id 2,
--- Mainline/LFGVanilla_Constants.lua:10).
---
--- It chooses, it does not SEARCH. Picking a category for someone is a
--- convenience; running a query they did not ask for is not.
local function SelectFirstCategory(panel)
	if panel.selectedCategoryID > 0 then
		return
	end

	local categories = SelectableCategories()
	if #categories == 0 then
		return
	end

	SelectCategory(panel, categories[1].id)
end

--- "Show all level activities" changed (core/settings.lua): rebuild the dropdowns
--- for the new activity list.
---
--- Blizzard's finder does the same on its CVar's change
--- (LFGBrowseMixin:ActivityFiltersChanged, Browse.lua:140-143, :320-322): the
--- ticked activities are cleared, because the list they were ticked from has
--- changed. Theirs also drops the category; this keeps it while the menu still
--- offers it, and otherwise moves to the first one, so the Search button stays
--- usable. It does NOT search: a setting is not a request for results.
local function LevelRangesChanged(panel)
	local current = panel.selectedCategoryID
	local offered = false
	for _, category in ipairs(SelectableCategories()) do
		if category.id == current then
			offered = true
		end
	end

	SelectCategory(panel, offered and current or 0)
	SelectFirstCategory(panel)
end

--- One activity row's text in the activity menu: the name Blizzard shows
--- (LFGUtil_GetActivityInfoName, ParentFrame.lua:282-285), then, while "Show
--- activity level ranges" is on, its suggested level range.
---
--- The range is the one Blizzard's camelot Listing tab shows beside each
--- activity -- minLevelSuggestion / maxLevelSuggestion (Listing.lua:1011-1012),
--- formatted by its rule (:1153-1161), copied exactly so the two finders never
--- disagree about the same dungeon:
---   * min == max, or max == 0: one number, LFD_LEVEL_FORMAT_SINGLE "(%d)",
---     or nothing at all when min is 0 too;
---   * otherwise LFD_LEVEL_FORMAT_RANGE "(%d - %d)" -- including "(0 - 20)",
---     which is how Blizzard's tab shows a range with no floor.
--- Both are GlobalStrings (enUS.lua:13496-13497), used whole so a translation
--- keeps its own wording. Neither field is secret: GetActivityInfoTable only
--- restricts its ARGUMENTS (AllowedWhenUntainted), and its activityID comes
--- from C_LFGList itself.
function LFGF.ActivityMenuText(activityInfo)
	if not activityInfo then
		return ""
	end
	local name = LFGUtil_GetActivityInfoName(activityInfo)
	if not LFGF.ShowActivityLevelRanges() then
		return name
	end

	local minLevel = activityInfo.minLevelSuggestion
	local maxLevel = activityInfo.maxLevelSuggestion
	local range
	if minLevel == maxLevel or maxLevel == 0 then
		if minLevel ~= 0 then
			range = string.format(L.LEVEL_SINGLE_FORMAT, minLevel)
		end
	else
		range = string.format(L.LEVEL_RANGE_FORMAT, minLevel, maxLevel)
	end
	return range and (name .. " " .. range) or name
end

--- The order of the activity menu's rows: Blizzard's camelot LISTING tab's,
--- not its Browse dropdown's. By the author's decision (2026-10-04,
--- .claude/rules/activity-menu-order.md), copied from ActivitySortComparator
--- (Blizzard_LFGVanilla_Listing.lua:965-981), whose fields are filled from
--- GetActivityInfoTable (:1006-1013):
---   1. orderIndex, HIGHEST first;
---   2. maxLevelSuggestion: 0 (no cap) first, then the highest cap first;
---   3. minLevelSuggestion, highest first;
---   4. the name the menu shows (LFGUtil_GetActivityInfoName), ignoring case.
--- Nothing after that, as in the Listing tab: two rows equal on all four may
--- come out either way, since table.sort is not stable.
---
--- Browse's own sorter, LFGUtil_SortActivityIDs (ParentFrame.lua:187-206), is
--- orderIndex LOWEST first, then name, and reads no level at all.
---
--- `infos` holds each activity's answer from OrganizeActivitiesForMenu, so the
--- sort asks the client nothing. None of these fields is secret, and none is
--- nilable (LFGListInfoDocumentation.lua:884-888).
local function ActivityMenuOrder(infos)
	return function(lhsID, rhsID)
		local lhs, rhs = infos[lhsID], infos[rhsID]
		if lhs.orderIndex ~= rhs.orderIndex then
			return lhs.orderIndex > rhs.orderIndex
		elseif lhs.maxLevelSuggestion ~= rhs.maxLevelSuggestion then
			if lhs.maxLevelSuggestion == 0 or rhs.maxLevelSuggestion == 0 then
				return lhs.maxLevelSuggestion == 0
			end
			return lhs.maxLevelSuggestion > rhs.maxLevelSuggestion
		elseif lhs.minLevelSuggestion ~= rhs.minLevelSuggestion then
			return lhs.minLevelSuggestion > rhs.minLevelSuggestion
		end
		return strcmputf8i(LFGUtil_GetActivityInfoName(lhs), LFGUtil_GetActivityInfoName(rhs)) < 0
	end
end

--- The activities bucketed by group, each bucket in ActivityMenuOrder, plus
--- each activity's info table.
---
--- Blizzard's LFGUtil_OrganizeActivitiesByActivityGroup (ParentFrame.lua
--- :239-257) does the bucketing, but sorts each bucket the Browse way and
--- keeps no info, so the rows would ask for it again. This asks once per
--- activity: GetActivityInfoTable builds a table on every call and
--- MayReturnNothing (LFGListInfoDocumentation.lua:186), so a second answer is
--- not even sure to be there. An activity with no answer is left out, as
--- Blizzard's organiser leaves it out (:243).
local function OrganizeActivitiesForMenu(activities)
	local organized, infos = {}, {}
	for _, activityID in ipairs(activities) do
		local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
		if activityInfo then
			infos[activityID] = activityInfo
			local groupID = activityInfo.groupFinderActivityGroupID
			organized[groupID] = organized[groupID] or {}
			table.insert(organized[groupID], activityID)
		end
	end

	local order = ActivityMenuOrder(infos)
	for _, activityIDs in pairs(organized) do
		table.sort(activityIDs, order)
	end
	return organized, infos
end

--- Activity checkboxes, from Browse.lua:1114-1181.
---
--- Two behaviours copied exactly:
---   * with NO category the dropdown is disabled and its selections cleared
---     (:1175-1179) -- this is the "disabled until you pick a category" rule;
---   * the menu SHAPE depends on how many activity groups there are (:1158-1162):
---     several groups become submenus, a single group stays flat on the root
---     with its activities indented by LFG_LIST_INDENT ("  %s").
---
--- Each activity row's text is LFGF.ActivityMenuText: the name, and its level
--- range while that setting is on. The indent wraps both. Group rows have no
--- level, and the dropdown's own text (UpdateActivityHeader) stays the bare
--- name, so the 167-wide button never has to hold a range.
---
--- ONE DIFFERENCE: the rows within a group, and the rows with no group, are
--- in the Listing tab's order (ActivityMenuOrder above), whatever the
--- level-range setting says. The groups keep Blizzard's own order
--- (LFGUtil_SortActivityGroupIDs).
function LFGF.SetupActivityMenu(panel)
	panel.ActivityDropdown:SetupMenu(function(dropdown, rootDescription)
		rootDescription:SetTag("MENU_LFGF_ACTIVITY")

		local function IsActivitySelected(value) return ActivityIsSelected(panel, value) end
		local function SelectActivity(value) ActivityToggle(panel, value) end

		if panel.selectedCategoryID <= 0 then
			dropdown:SetEnabled(false)
			ActivityReset(panel)
			return
		end

		dropdown:SetEnabled(true)

		local activities = LFGF.Activities(panel.selectedCategoryID)
		-- A tick this menu would not show could never be unticked, so it goes
		-- first. The menu is built on every open (DropdownButton.lua:117-118).
		DropUnofferedActivities(panel, activities)
		if #activities == 0 then
			return
		end

		local organized, infos = OrganizeActivitiesForMenu(activities)
		local activityGroupIDs = GetKeysArray(organized)
		LFGUtil_SortActivityGroupIDs(activityGroupIDs)

		for _, activityGroupID in ipairs(activityGroupIDs) do
			local activityIDs = organized[activityGroupID]

			if activityGroupID == 0 then
				-- Free-floating activities, with no group of their own.
				for _, activityID in ipairs(activityIDs) do
					rootDescription:CreateCheckbox(LFGF.ActivityMenuText(infos[activityID]),
						IsActivitySelected, SelectActivity, activityID)
				end
			else
				local groupText = C_LFGList.GetActivityGroupInfo(activityGroupID)
				local groupCheckbox = rootDescription:CreateCheckbox(groupText,
					function() return panel:IsAnyActivitySelectedInGroup(activityGroupID) end,
					function()
						panel:SetAllActivitiesInGroup(activityGroupID,
							not panel:IsAnyActivitySelectedInGroup(activityGroupID))
					end,
					activityGroupID)

				-- One group: keep everything on the root and indent it. More
				-- than one: nest each group's activities under it.
				local parentMenu, textIndent = rootDescription, LFG_LIST_INDENT
				if #activityGroupIDs > 1 then
					parentMenu, textIndent = groupCheckbox, "%s"
				end

				for _, activityID in ipairs(activityIDs) do
					local text = string.format(textIndent, LFGF.ActivityMenuText(infos[activityID]))
					parentMenu:CreateCheckbox(text, IsActivitySelected, SelectActivity, activityID)
				end
			end
		end
	end)
end

-------------------------------------------------------
---------- Sections
-------------------------------------------------------


--- A text link at the right end of a section's title line.
---
--- THE LOOK OF "Select all" / "Unselect all": LFGF.CreateRowLink (core/main.lua),
--- GameFontNormalSmall, white on hover, sized to its words.
---
--- OWNED BY THE SECTION, so it is shown and hidden with it: the tab system
--- already hides a tab's sections (TabSystemOwner.lua:46-51), so a link that
--- belongs to one needs no tab code at all. That is why there is one per
--- section rather than one control re-dressed on every tab switch.
---
--- TOPRIGHT TO TOPRIGHT, never RIGHT. RIGHT is centre-bearing, and a section
--- that holds rows has its vertical centre halfway down them. Dropped by half
--- the difference between the title's height and the link's, so the small text
--- is centred on the large title's line. GetStringHeight is readable here: the
--- title is our own constant string, never a secret.
local function AddHeaderLink(section, label, action)
	local link = LFGF.CreateRowLink(section, label)
	link:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0,
		-(section.Title:GetStringHeight() - link:GetHeight()) / 2)
	link:SetScript("OnClick", function()
		LFGF.PlayClick()
		action()
	end)
	-- Above the section's +/- header, which covers the whole title row, so the
	-- link keeps its own click (RaiseOverHeader, core/filterpanel_shared.lua).
	RaiseOverHeader(section, link)
	section.HeaderLink = link
	return link
end


--- The Level row: a "Level" label and Blizzard's min/max level control, as the
--- next grid row of `section` (the role section).
---
--- LevelRangeFrameTemplate, not two boxes of ours. It is Blizzard's own level
--- range control (InputBoxTemplates.xml:378-409) -- two numeric boxes of three
--- letters with a dash between them -- and its mixin already answers the range
--- (GetLevelRange), empties it (Reset), moves focus between the boxes on Tab
--- and lowers a min above the max (FixLevelRange, InputBoxTemplates.lua
--- :380-433). It lives in Blizzard_SharedXML, which loads on camelot, and
--- Blizzard's retail finder, Auction House and crafting orders all use it.
---
--- AN EMPTY BOX IS NO LIMIT, by the author's rule: GetNumber reads an empty box
--- as 0, which Blizzard's own FixLevelRange also treats as "no max" (:408-411).
---
--- ONLY SEARCH SEARCHES, by the author's rule. Typing changes nothing until
--- Search (the values ride on its snapshot like every checkbox), and Enter --
--- which the template leaves unhandled -- only lets go of the box.
---
--- The label is LFGF.LEVEL_ROW_LABEL ("Player level range"), in
--- GameFontNormalSmall: the font UICheckButtonTemplate gives
--- the role labels above it (CheckButtonTemplates.xml:54). LEFT to the row's
--- TOPLEFT, dropped by half a row: the label sits on the row's vertical centre,
--- where the checkboxes' labels sit on theirs. Nudged LEVEL_LABEL_INSET_X in
--- from the cell edge, to sit under the Tank box rather than its frame.
local function BuildLevelRow(panel, section)
	local rowIndex = section.RowCount + 1
	local x, rowTop = GridCell(1, rowIndex, panel.Layout.playerColumn)

	local label = S.Text(section.Content, 12, S.colors.text)
	label:SetText(LFGF.LEVEL_ROW_LABEL)
	label:SetPoint("LEFT", section.Content, "TOPLEFT", x + LEVEL_LABEL_INSET_X,
		rowTop - ROLE_ROW_HEIGHT / 2)

	local range = CreateFrame("Frame", nil, section.Content, "LevelRangeFrameTemplate")
	range:SetPoint("LEFT", label, "RIGHT", LEVEL_LABEL_TO_RANGE_GAP, 0)

	for _, box in ipairs({ range.MinLevel, range.MaxLevel }) do
		LFGF.ThemeFont(box, 12, "text")
		box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	end

	SizeSection(section, rowIndex)

	-- The level range is part of this section's defaults too, for the warning
	-- a collapsed section shows (core/filterpanel_shared.lua,
	-- UpdateSectionWarning): both boxes empty, which GetNumber reads as 0.
	-- GetNumber is documented Nilable (SimpleEditBoxAPIDocumentation.lua:288),
	-- so a nil counts as empty, as it does in FilterSnapshot.
	local boxesAtDefaults = section.IsAtDefaults
	function section:IsAtDefaults()
		local minLevel, maxLevel = range:GetLevelRange()
		return boxesAtDefaults(self) and (minLevel or 0) == 0 and (maxLevel or 0) == 0
	end

	panel.LevelLabel = label
	panel.LevelRange = range
end

--- The two bulk toggles that fill the cells beside the last class.
---
--- PLACED FROM THE ROWS, NOT FROM A HARDCODED CELL. On this client
--- CLASS_SORT_ORDER is the vanilla NINE (Camelot/Constants.lua:1-11) and the
--- grid is four wide, so the last row holds Hunter alone and three cells go
--- spare. Deriving the position from `rows` means a different class list moves
--- the buttons rather than stranding them on an empty third row -- and it is no
--- more code than writing 3 and 2.
---
--- NOT HANDLED, because it cannot happen here and guessing at it would be
--- worse than saying so: a class list that exactly fills its last row leaves no
--- free cell, and these would land on top of the first two classes. Nine over
--- four always leaves three. A spec asserts there are spare cells, so a change
--- to CLASSES_PER_ROW or to the class list fails loudly instead of overlapping.
---
--- THEY WALK PlayerClassChecks AND NOTHING ELSE. Three sections share one
--- builder, so a bulk toggle that reached for the wrong list would look right
--- on the classes and quietly wreck a neighbour.
local function BuildClassBulkButtons(panel, rows)
	local lastRow = #rows
	local firstFreeColumn = #rows[lastRow] + 1

	--- One link in the cell at `column`, centred in the row's band -- the
	--- checkbox beside it is the full ROLE_ROW_HEIGHT, so a shorter control
	--- anchored flush to the cell top would sit above its neighbours' middles.
	local function Build(column, label, checked)
		local link = LFGF.CreateRowLink(panel.ClassSection.Content, label)

		local x, y = GridCell(column, lastRow, panel.Layout.playerColumn)
		link:SetPoint("TOPLEFT", panel.ClassSection.Content, "TOPLEFT",
			x + CLASS_LINK_INSET_X, y - (ROLE_ROW_HEIGHT - link:GetHeight()) / 2)

		link:SetScript("OnClick", function()
			LFGF.PlayClick()
			for _, check in ipairs(panel.PlayerClassChecks) do
				check:SetChecked(checked)
			end
		end)

		return link
	end

	panel.UnselectAllClasses =
		Build(firstFreeColumn, LFGF.UNSELECT_ALL_CLASSES_LABEL, false)
	panel.SelectAllClasses =
		Build(firstFreeColumn + 1, LFGF.SELECT_ALL_CLASSES_LABEL, true)
end

--- What one row of boxes currently says.
local function RowSnapshot(checks)
	local snapshot = {}
	for _, check in ipairs(checks) do
		snapshot[check.roleField] = check:GetChecked()
	end
	return snapshot
end

--- Every section's state, as a plain table the list panel can consume.
---
--- ONE payload with a key per section rather than an argument per section: a
--- third filter is then another key, and the list panel keeps one thing to
--- store.
---
--- A FRESH TABLE every time. What travels with the search must be a snapshot --
--- a live reference would let a later search retroactively change what an
--- earlier one was filtered by.
local function FilterSnapshot(panel)
	-- 0 is "no limit" on that side. GetNumber is documented Nilable
	-- (SimpleEditBoxAPIDocumentation.lua:288), so a nil is read as 0 too.
	local minLevel, maxLevel = panel.LevelRange:GetLevelRange()
	return {
		playerRoles = RowSnapshot(panel.PlayerRoleChecks),
		playerClasses = RowSnapshot(panel.PlayerClassChecks),
		playerLevels = { min = minLevel or 0, max = maxLevel or 0 },
		groupFilters = RowSnapshot(panel.GroupFilterChecks),
		-- The Miscellaneous section's two dropdowns, each a fresh copy
		-- (core/filterpanel_miscellaneous.lua).
		playstyles = panel.MiscellaneousSection:GetPlaystyles(),
		languages = panel.MiscellaneousSection:GetLanguages(),
		-- The Groups section's class dropdown, a fresh copy naming every class
		-- (core/filterpanel_groupclasses.lua).
		groupExcludedClasses = panel.GroupSection:GetGroupExcludedClasses(),
	}
end

--- One level box: a number, or EMPTY for 0. Blizzard's SetMinLevel/SetMaxLevel
--- call SetNumber (InputBoxTemplates.lua:419-425), which would show "0" -- and
--- an empty box, not a 0, is what "no limit" looks like, as Reset leaves it
--- (:427-430).
local function SetLevelBox(box, level)
	if level > 0 then
		box:SetNumber(level)
	else
		box:SetText("")
	end
end

--- Put the Filters tab into the state `filters` describes: the shape
--- LFGF.SavedFilters answers, or nil for the defaults.
---
--- BOX BY BOX: a box the record does not name keeps the default it was built
--- with (defaultChecked), so a record from before a box existed, or one that
--- names a class this client does not have, still restores what it can.
--- LFGF.SavedFilters has already dropped anything that is not a boolean.
---
--- Neither searches nor saves: restoring is not asking, and not choosing.
local function ApplyFilters(panel, filters)
	for key, checks in pairs({
		groupFilters = panel.GroupFilterChecks,
		playerRoles = panel.PlayerRoleChecks,
		playerClasses = panel.PlayerClassChecks,
	}) do
		local section = filters and filters[key]
		for _, check in ipairs(checks) do
			local value = section and section[check.roleField]
			if type(value) == "boolean" then
				check:SetChecked(value)
			else
				check:SetChecked(check.defaultChecked)
			end
		end
	end

	local levels = filters and filters.playerLevels
	SetLevelBox(panel.LevelRange.MinLevel, levels and levels.min or 0)
	SetLevelBox(panel.LevelRange.MaxLevel, levels and levels.max or 0)
	-- Search saves only after FixLevelRange, so a saved min above the max is a
	-- hand edit. Blizzard's own fix puts it right, as Search would have.
	panel.LevelRange:FixLevelRange()

	-- The Playstyle dropdown, the same way: a playstyle the record does not
	-- name takes its default, ticked.
	panel.MiscellaneousSection:SetPlaystyles(filters and filters.playstyles)
	-- And the Languages dropdown: only a language the record names with true is
	-- ticked beyond the locked ones, so nil, or an older record, is the default.
	panel.MiscellaneousSection:SetLanguages(filters and filters.languages)
	-- And the Groups section's class dropdown, the same way: only a class
	-- named with true is selected, so nil, or an older record, selects none.
	panel.GroupSection:SetGroupExcludedClasses(filters and filters.groupExcludedClasses)

	-- The only way a COLLAPSED section's boxes change (the restore at build,
	-- Reset filters, My filters, Defaults), so its warning follows here.
	for _, section in ipairs(panel.FilterSections) do
		UpdateSectionWarning(section)
	end
end

-------------------------------------------------------
---------- The Search button
-------------------------------------------------------
-- In the place of Blizzard's hand-rolled refresh button (Browse.xml:447-479):
-- a labelled UIPanelButtonTemplate, with Blizzard's "Search Again" as its
-- tooltip.

local function BuildSearchButton(panel)
	local button = S.Button(panel, LFGF.SEARCH_ACTION_LABEL, SEARCH_BUTTON_WIDTH, SEARCH_BUTTON_HEIGHT, "primary")
	button:HookScript("OnEnter", function(self) LFGF.ShowTextTooltip(self, L.SEARCH_AGAIN) end)
	button:HookScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function()
		LFGF.PlayClick()
		panel:RequestSearch()
	end)
	return button
end

local SEARCH_TIMEOUT_SECONDS = 15

local function FinishSearch(panel, message)
	panel.searching = false
	if panel.searchTimer then
		panel.searchTimer:Cancel()
		panel.searchTimer = nil
	end
	panel:UpdateSearchState()
	LFGF.SetSearchStatus(message)
end

-- Requête utilisateur de LFG Forever 2.2.0. Préparer les arguments puis appeler
-- le jeu dans le clic original, avant les notifications et le rafraîchissement.
local function RequestSearch(panel)
	local categoryID = panel.selectedCategoryID
	if Quintessence.GuildStatus() ~= "ok" or panel.searching or categoryID <= 0 then return false end
	local activityIDs = panel:SelectedActivityIDs()
	if #activityIDs == 0 then activityIDs = LFGF.Activities(categoryID) end
	if #activityIDs == 0 then
		LFGF.SetSearchStatus("Aucune activité disponible dans cette catégorie.")
		return false
	end

	panel.LevelRange:FixLevelRange()
	local filters = FilterSnapshot(panel)
	local languages = LFGF.LanguageSearchFilter(filters.languages)
	panel.searching = true
	panel.submitting = true
	panel.searchBlocked = false
	panel.searchFailed = false
	local ok, result = pcall(C_LFGList.Search, categoryID, 0, 0, languages, false, nil, activityIDs)
	panel.submitting = false
	if panel.searchBlocked or not ok or LFGF.Readable(result, nil) == false then
		FinishSearch(panel, "WoW a refusé la recherche. Utilise le Cherche-groupe du jeu.")
		return false
	end
	if panel.searchFailed then return false end

	LFGF.SaveFilters(filters)
	EventRegistry:TriggerEvent(LFGF.EVENT_FILTERS_APPLIED, filters, panel.searching)
	if panel.searching then
		panel:UpdateSearchState()
		LFGF.SetSearchStatus("Recherche en cours…")
		panel.searchTimer = C_Timer.NewTimer(SEARCH_TIMEOUT_SECONDS, function()
			panel.searchTimer = nil
			FinishSearch(panel, "WoW n’a pas répondu. Tu peux relancer la recherche.")
		end)
	end
	return true
end

-------------------------------------------------------
---------- The tabs
-------------------------------------------------------
-- THREE TABS over one column: FILTERS, holding the filter sections; WHISPERS,
-- holding the log core/whisperlog.lua builds; and PLAYER RATINGS, holding
-- Blizzard's Recent Allies (core/playerratings.lua), shown only while its
-- setting is on.
--
-- BLIZZARD'S TabSystem, not a pair of buttons of ours. Shared\TabSystem\ is
-- gated only [ExcludeLoadGameType vanilla tbc] (Blizzard_SharedXML.toc:131-134),
-- so all four files load here -- and Blizzard's own CAMELOT FriendsFrame is
-- built on them (Camelot/FriendsFrame.xml:411-418, FriendsFrame.lua:521-522),
-- which is better evidence than "the template exists".
--
-- IT IS FOUR PIECES AND THE SPLIT IS THE POINT:
--   TabSystemMixin        owns the BUTTONS  -- a pool, AddTab, selection art
--   TabSystemOwnerMixin   glues the two     -- AddNamedTab, SetTab
--   TabSystemTrackerMixin owns the CONTENT  -- tabID -> a set of frames
--
-- The tracker is what earns the dependency. On every SetTab it walks EVERY
-- registered element of EVERY tab and shows only the chosen tab's
-- (TabSystemOwner.lua:46-51). So "the class section belongs to Filters" is a
-- REGISTRATION, not a branch in a function someone has to remember to extend
-- when a fourth section arrives.
--
-- WHAT IS NOT ON A TAB: the category dropdown, the activity dropdown and the
-- Search button. They govern the LIST, which is on screen under both tabs, so
-- they sit above the strip and belong to neither. Registering them with a tab
-- is the mistake to avoid -- the tracker hides everything it knows about that
-- is not on the current tab, so one accidental registration takes the Search
-- button away whenever the player reads their whispers.

--- Put every checkbox on the Filters tab back the way the panel opened, and
--- empty the two level boxes (no limit either way, as the panel opens).
---
--- Run by the "Reset filters" link.
---
--- THE CHECKBOXES ONLY, by the author's decision. The link lives in the
--- "Find groups by role" header, among the filters it clears; the category and
--- activity dropdowns sit in the search row above, on neither tab, and keep
--- whatever the player chose. (When it was a button in their row it reset
--- those two as well.)
---
--- IT DOES NOT SEARCH. Resetting is not asking -- the same line the
--- auto-selected category draws.
---
--- IT SAVES, by the author's decision: the defaults become the saved Filters
--- tab, so the next session opens reset too. The list keeps the filters it
--- was searched with until the next Search; nothing is sent to it here.
local function ResetFilters(panel)
	ApplyFilters(panel, nil)
	LFGF.SaveFilters(FilterSnapshot(panel))
end

-------------------------------------------------------
---------- My filters
-------------------------------------------------------
-- The player's NAMED filters (QuinteLFGDB.myFilters, core/main.lua), reached
-- from the "Find groups by role" title line:
--
--   Find groups by role    [My filters v] | Save new filter | Reset filters
--
-- The author's decisions, one at a time (.claude/rules/my-filters.md):
--   * a filter is the Filters tab only -- boxes and level range, never the
--     category or activities -- the same record Search and Reset save;
--   * picking a name fills the boxes and SAVES them as the current filters,
--     like Reset; it does not search, and the list waits for Search;
--   * the x on a row deletes at once, with no question, and the menu stays
--     open;
--   * "Save new filter" adds to My filters only, with the level range as
--     typed; the current filters are not saved;
--   * a name already saved is OVERWRITTEN: the popup warns in red and Okay
--     stays on, and saving deletes the old filter and saves the new one last;
--   * 20 filters, 20 letters, names trimmed and case-sensitive.

-- The whisper log's gap around its separators (core/whisperlog.lua,
-- ACTION_LINK_GAP), so the two link lines in this addon read alike.
local HEADER_LINK_GAP = 4

-- Ours, like the labels (core/locale.lua). The limits are read from
-- core/main.lua rather than typed into the words, so they cannot drift.
local MY_FILTER_PROMPT = L.MY_FILTER_PROMPT
local MY_FILTERS_FULL = L.MY_FILTERS_FULL_FORMAT:format(LFGF.MY_FILTERS_MAX)

-- Each reason answers LFGF.MyFilterNameProblem. A function each, so only the
-- words that hold a %d are ever formatted: a % in the others reaches no
-- string.format.
local MY_FILTER_PROBLEMS = {
	empty = function() return L.MY_FILTER_EMPTY end,
	long = function() return L.MY_FILTER_TOO_LONG_FORMAT:format(LFGF.MY_FILTER_NAME_MAX_LETTERS) end,
	full = function() return MY_FILTERS_FULL end,
}

--- A name as it is SHOWN, every | doubled (core/main.lua). The saved name stays
--- as typed.
local ShownName = LFGF.ShownName

--- One chat line about a filter: 'LFG Forever: filter "Tanks" saved.'
--- `sentence` is the whole line after the title, with a %s for the name, so a
--- translation can put the name wherever its language wants it.
local function PrintAboutFilter(name, sentence)
	LFGF.Print(sentence:format(ShownName(name)))
end

--- Why Okay is off for what the box holds, or nil when it is on.
local function MyFilterReason(text)
	local problem = LFGF.MyFilterNameProblem(text)
	if problem == nil then
		return nil
	end
	return MY_FILTER_PROBLEMS[problem]()
end

--- Okay follows the name: on only when nothing is wrong with it. Blizzard's
--- own pattern for a popup that needs input (StaticPopup_StandardNonEmptyText-
--- Handler, StaticPopup.lua:146-150), with our rule in place of "not empty".
local function UpdateMyFilterOkay(dialog)
	dialog:GetButton1():SetEnabled(MyFilterReason(dialog:GetEditBox():GetText()) == nil)
end

-- THE OVERWRITE WARNING. A name already saved turns Okay off no more: the
-- popup says, in red, that saving will overwrite that filter (the author's
-- decisions, 2026-11-16, .claude/rules/my-filters.md). It goes on Blizzard's
-- own second line, the popup's SubText, small text ABOVE the box
-- (GameDialog.xml, parentKey="SubText"). Blizzard shows and lays out that line
-- only for a dialog that defines `subText` (GameDialogMixin:SetupText and
-- SetupElementAnchoring, GameDialog.lua), so the dialog below sets one, a
-- blank, and its text is ours from then on.
--
-- THE SPACE IS ALWAYS KEPT, so the popup never changes size while the player
-- types: as many lines as the longest warning any saved name can make,
-- counted when the popup opens, with every state padded to that many lines
-- ("\n " per line). Counting needs the line's real width, which Blizzard's
-- Resize gives it (SubText:SetDesiredWidth, GameDialog.lua), hence a Resize
-- before counting. After a change, Resize again, as Blizzard does after
-- changing a shown dialog's second line (StaticPopup_OnUpdate, StaticPopup.lua).
--
-- TAINT: nothing new. StaticPopup_Show runs from our click, so Blizzard's Init
-- and Resize already run in our call for this popup; Blizzard's SetupText puts
-- the line right for the next dialog in the frame (its own text, or hidden).
-- Nothing is written onto Blizzard's frame: what we remember about it is kept
-- in weak tables of ours.
local warningLines = setmetatable({}, { __mode = "k" })   -- dialog -> lines kept
local shownWarning = setmetatable({}, { __mode = "k" })   -- dialog -> the text last shown

-- The popup from its OnShow to its OnHide, so a delete from the menu (or
-- Blizzard's Defaults) can bring its Okay and its warning up to date. Cleared
-- on hide: the frame is one of Blizzard's four, and the next dialog shown in
-- it is not ours.
local openMyFilterPopup

--- Red, Blizzard's error colour, generated at load from the client's colour
--- table; plain text if it is ever missing.
local function Red(text)
	if RED_FONT_COLOR then
		return RED_FONT_COLOR:WrapTextInColorCode(text)
	end
	return text
end

--- The warning for overwriting the filter saved as `name` (trimmed already).
local function WarningFor(name)
	return Red(L.MY_FILTER_OVERWRITE_WARNING_FORMAT:format(ShownName(name)))
end

--- The warning for what the box holds, or nil when no filter has that name.
local function OverwriteWarning(text)
	if not LFGF.IsMyFilterSaved(text) then
		return nil
	end
	return WarningFor(LFGF.CleanMyFilterName(text))
end

--- How many lines `text` takes on `line`. GetNumLines is
--- SecretWhenAnchoringSecret (SimpleFontStringAPIDocumentation.lua); our own
--- text never is, but an unreadable answer counts as one line.
local function LinesOf(line, text)
	line:SetText(text)
	local lines = LFGF.ReadableNumbers(line:GetNumLines())
	return math.max(lines or 1, 1)
end

--- Count the lines to keep: the longest warning any saved name can make.
local function ReserveWarningLines(dialog)
	local most = 1
	for _, filter in ipairs(LFGF.MyFilters()) do
		most = math.max(most, LinesOf(dialog.SubText, WarningFor(filter.name)))
	end
	warningLines[dialog] = most
end

--- The warning for what the box holds, or the kept space blank, padded to the
--- kept lines. Resize only when the line changed.
local function UpdateOverwriteWarning(dialog)
	local line = dialog.SubText
	local warning = OverwriteWarning(dialog:GetEditBox():GetText())
	local text, used = " ", 1
	if warning then
		text, used = warning, LinesOf(line, warning)
	end
	text = text .. string.rep("\n ", (warningLines[dialog] or 1) - used)
	line:SetText(text)
	if shownWarning[dialog] ~= text then
		shownWarning[dialog] = text
		dialog:Resize()
	end
end

--- Okay and the warning, both following what the box holds.
local function UpdateMyFilterPopup(dialog)
	UpdateMyFilterOkay(dialog)
	UpdateOverwriteWarning(dialog)
end

--- After My filters changed under an open popup (a delete from the menu,
--- Blizzard's Defaults): Okay and the warning again.
local function RefreshMyFilterPopup()
	if openMyFilterPopup then
		UpdateMyFilterPopup(openMyFilterPopup)
	end
end

--- Save what the popup was opened for under the typed name, overwriting a
--- filter of that name. Checked again here, because My filters may have
--- changed since the box was last typed in. Returns true to keep the dialog
--- open (StaticPopup_OnClick hides it otherwise, StaticPopup.lua:728-752), so
--- a refused name stays on screen with Okay off and its reason one hover away.
local function SaveMyFilterFromPopup(dialog, data)
	local name = dialog:GetEditBox():GetText()
	local saved, overwritten = LFGF.SaveMyFilter(name, data.filters)
	if not saved then
		UpdateMyFilterPopup(dialog)
		return true
	end
	if overwritten then
		PrintAboutFilter(LFGF.CleanMyFilterName(name), L.MY_FILTER_OVERWRITTEN_FORMAT)
	else
		PrintAboutFilter(LFGF.CleanMyFilterName(name), L.MY_FILTER_SAVED_FORMAT)
	end
	data.panel:UpdateMyFilterControls()
	return false
end

-- THE OKAY TOOLTIP is the shared one (LFGF.HookPopupOkayTooltip, core/main.lua),
-- titled with what the popup is for, the same title as the Save new filter
-- link's own tooltip (the author's choice).

-- Defined once, at file scope: StaticPopupDialogs is a shared registry. The
-- data -- the panel and the snapshot taken when Save new filter was clicked --
-- is StaticPopup_Show's FOURTH argument, so OnShow already has it
-- (StaticPopup.lua:309).
--
-- maxLetters IS REQUIRED, not decoration: the edit box belongs to the reused
-- frame and keeps the last dialog's limit unless this one sets its own
-- (GameDialog.lua:248-251).
--
-- Enter saves only a name Okay would accept, as Blizzard's own name-entry popup
-- does (GENERIC_INPUT_BOX, GameDialogDefs.lua:226-233). Theirs asks the button;
-- here SaveMyFilterFromPopup checks the very rule the button follows, so a
-- second check would be the same question twice.
StaticPopupDialogs[LFGF.MY_FILTER_POPUP] = {
	text = MY_FILTER_PROMPT,
	-- A blank: Blizzard then shows and lays out its second line, which holds
	-- the overwrite warning (above).
	subText = " ",
	button1 = L.OKAY,
	button2 = L.CANCEL,
	hasEditBox = 1,
	maxLetters = LFGF.MY_FILTER_NAME_MAX_LETTERS,
	OnShow = function(dialog)
		openMyFilterPopup = dialog
		LFGF.HookPopupOkayTooltip(dialog, LFGF.SAVE_NEW_FILTER_LABEL, MyFilterReason)
		dialog:Resize()   -- gives the second line its width before counting
		ReserveWarningLines(dialog)
		shownWarning[dialog] = nil
		dialog:GetEditBox():SetText("")
		dialog:GetEditBox():SetFocus()
		UpdateMyFilterPopup(dialog)
	end,
	OnHide = function(dialog)
		LFGF.RestorePopupOkay(dialog)
		warningLines[dialog], shownWarning[dialog] = nil, nil
		if openMyFilterPopup == dialog then
			openMyFilterPopup = nil
		end
	end,
	OnAccept = SaveMyFilterFromPopup,
	EditBoxOnTextChanged = function(editBox)
		UpdateMyFilterPopup(editBox:GetParent())
	end,
	EditBoxOnEnterPressed = function(editBox, data)
		local dialog = editBox:GetParent()
		if not SaveMyFilterFromPopup(dialog, data) then
			dialog:Hide()
		end
	end,
	EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
	hideOnEscape = 1,
	timeout = 0,
	whileDead = 1,
}

--- A name was picked: fill the boxes and save them as the current filters.
---
--- ApplyFilters is the same function that restores the saved Filters tab, so a
--- box the filter does not name takes its default, a 0 level is an empty box,
--- and a min above the max is put right. Then SaveFilters, as Reset does. No
--- search, and nothing is sent to the list: it keeps the filters it was
--- searched with until Search, by the author's decision.
local function ApplyMyFilter(panel, name)
	for _, filter in ipairs(LFGF.MyFilters()) do
		if filter.name == name then
			ApplyFilters(panel, filter.filters)
			LFGF.SaveFilters(FilterSnapshot(panel))
			PrintAboutFilter(name, L.MY_FILTER_APPLIED_FORMAT)
			return
		end
	end
end

--- The x on a row: delete at once, no question. The menu stays OPEN and is
--- rebuilt without the row -- GenerateMenu on an open dropdown hands the menu
--- its new description without closing it (DropdownButton.lua:195-200). With
--- nothing left, the menu closes and the dropdown goes.
local function DeleteMyFilter(panel, name)
	if not LFGF.DeleteMyFilter(name) then
		return
	end
	PrintAboutFilter(name, L.MY_FILTER_DELETED_FORMAT)
	RefreshMyFilterPopup()
	local dropdown = panel.MyFiltersDropdown
	if #LFGF.MyFilters() == 0 then
		dropdown:CloseMenu()
	elseif dropdown:IsMenuOpen() then
		dropdown:GenerateMenu()
	end
	panel:UpdateMyFilterControls()
end

--- The menu: one row per filter, in save order. A row is a plain button, not a
--- radio -- nothing is ever "selected", and the dropdown's text never changes
--- (WowStyle1FilterDropdownTemplate is Blizzard's fixed-text filter dropdown,
--- MenuTemplates.lua:1001-1005). A button's nil response closes the menu
--- (Menu.lua:2296).
---
--- THE x IS BLIZZARD'S, the recipe of their Cooldown Viewer layout menu
--- (CooldownViewerSettings.lua:1149-1165): an initializer attaches
--- MenuTemplates' auto-hide cancel button, shown while the row is hovered,
--- with DELETE as its tooltip. It takes the GEAR's anchor, RIGHT to the row's
--- RIGHT (MenuVariants.lua:9): the cancel anchor hangs it LEFT of whatever it
--- is given -- the gear, in Blizzard's rows -- which here would be outside the
--- menu. The menu sizes each row to everything attached to it
--- (MeasureExtents, Menu.lua:988-1050), so the x gets room of its own.
local function SetupMyFiltersMenu(panel)
	panel.MyFiltersDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_LFGF_MY_FILTERS")
		for _, filter in ipairs(LFGF.MyFilters()) do
			local name = filter.name
			local row = rootDescription:CreateButton(ShownName(name), function()
				ApplyMyFilter(panel, name)
			end)
			row:AddInitializer(function(button)
				local delete = MenuTemplates.AttachAutoHideCancelButton(button)
				MenuTemplates.SetUtilityButtonTooltipText(delete, L.DELETE)
				MenuTemplates.SetUtilityButtonAnchor(delete, MenuVariants.GearButtonAnchor, button)
				MenuTemplates.SetUtilityButtonClickHandler(delete, function()
					DeleteMyFilter(panel, name)
				end)
			end)
		end
	end)
end

--- The title line's two new controls and their separators, chained right to
--- left off Reset filters: each hangs its RIGHT off the LEFT of the one after
--- it, y 0, so the row is one anchor chain and rounds as one
--- (patterns-ui.md, "Controls In One Row Share One Anchor Chain").
---
--- All are children of the "Find groups by role" section, so the tab system
--- shows and hides them with it (TabSystemOwner.lua:46-51).
-- The caret after "My filters": Blizzard's small-dropdown arrow, 12x5
-- (AtlasInfo.lua, interface/common/commondropdown), MY_FILTERS_CARET_GAP
-- after the words.
local MY_FILTERS_CARET_ATLAS = "common-dropdown-c-button-hover-arrow"
local MY_FILTERS_CARET_WIDTH = 12
local MY_FILTERS_CARET_GAP = 2

local function BuildMyFilterControls(panel)
	local section = panel.GroupSection

	local function Separator(rightOf)
		local separator = S.Text(section, 12, S.colors.muted)
		separator:SetText(LFGF.SEPARATOR)
		separator:SetPoint("RIGHT", rightOf, "LEFT", -HEADER_LINK_GAP, 0)
		return separator
	end

	local rightSeparator = Separator(panel.ResetFiltersLink)

	local save = LFGF.CreateRowLink(section, LFGF.SAVE_NEW_FILTER_LABEL)
	save:SetPoint("RIGHT", rightSeparator, "LEFT", -HEADER_LINK_GAP, 0)
	save:SetScript("OnClick", function()
		LFGF.PlayClick()
		-- The boxes as they are NOW: ticking one while the popup is open does
		-- not change what this click saves.
		StaticPopup_Show(LFGF.MY_FILTER_POPUP, nil, nil,
			{ panel = panel, filters = FilterSnapshot(panel) })
	end)
	-- Never off, not even at 20: a name already saved overwrites, which adds
	-- none (the author's decision). A new name at 20 is refused by the
	-- popup's Okay, which says why.
	RaiseOverHeader(section, save)
	panel.SaveNewFilterLink = save

	local leftSeparator = Separator(save)

	-- "MY FILTERS" AND BLIZZARD'S DROPDOWN CARET, the author's choice
	-- (2026-10-01, after an in-game preview of eleven arrows). The caret is
	-- common-dropdown-c-button-hover-arrow, 12x5, the arrow Blizzard's own small
	-- dropdown shows (WowStyle2DropdownTemplate, MenuTemplates.xml:28). Before
	-- it: a framed WowStyle1FilterDropdownTemplate (foreign beside two text
	-- links), then the Damage Meter's round arrow button (too big).
	--
	-- ONE DropdownButton WITH NO TEMPLATE holds both, sized to them, the way
	-- Blizzard builds the Minimap tracking button (Mainline/MinimapTrackingButton.xml:3).
	-- The intrinsic brings the menu and opens it on mouse down
	-- (DropdownButton.lua:100-106); the words are inside the button, so they
	-- are as clickable as the caret with no hit-rect trick. Like a link, it is
	-- exactly as wide as what it shows and a link's height, and the words turn
	-- white on hover. HookScript, not SetScript: the intrinsic's own scripts
	-- must stay.
	local dropdown = CreateFrame("DropdownButton", nil, section)
	dropdown:SetPoint("RIGHT", leftSeparator, "LEFT", -HEADER_LINK_GAP, 0)

	local label = S.Text(dropdown, 12, S.colors.gold)
	label:SetText(LFGF.MY_FILTERS_LABEL)
	label:SetPoint("LEFT", dropdown, "LEFT", 0, 0)
	dropdown.Label = label

	local caret = dropdown:CreateTexture(nil, "OVERLAY")
	caret:SetAtlas(MY_FILTERS_CARET_ATLAS, TextureKitConstants.UseAtlasSize)
	caret:SetPoint("RIGHT", dropdown, "RIGHT", 0, 0)
	dropdown.Arrow = caret

	dropdown:SetSize(label:GetStringWidth() + MY_FILTERS_CARET_GAP + MY_FILTERS_CARET_WIDTH,
		save:GetHeight())

	dropdown:HookScript("OnEnter", function(self)
		self.Label:SetTextColor(unpack(S.colors.text))
	end)
	dropdown:HookScript("OnLeave", function(self)
		self.Label:SetTextColor(unpack(S.colors.gold))
	end)
	-- Its menu opens on mouse DOWN, and the header under it must not see that
	-- press either: lifted like the links.
	RaiseOverHeader(section, dropdown)
	panel.MyFiltersDropdown = dropdown

	panel.MyFiltersSeparators = { leftSeparator, rightSeparator }

	--- Show the dropdown and its separator only when something is saved.
	function panel:UpdateMyFilterControls()
		local count = #LFGF.MyFilters()
		self.MyFiltersDropdown:SetShown(count > 0)
		leftSeparator:SetShown(count > 0)
	end

	SetupMyFiltersMenu(panel)
	panel:UpdateMyFilterControls()

	-- Blizzard's Defaults button forgot them all (core/settings.lua ->
	-- LFGF.ForgetMyFilters): close an open menu and hide the dropdown.
	EventRegistry:RegisterCallback(LFGF.EVENT_MY_FILTERS_FORGOTTEN, function()
		dropdown:CloseMenu()
		panel:UpdateMyFilterControls()
		RefreshMyFilterPopup()
	end, panel)
end

local function BuildTabs(panel)
	local function section(title)
		local frame = BuildSection(panel, title)
		frame:SetHeight(frame.Title:GetStringHeight() + SECTION_TITLE_TO_RULE_GAP + SECTION_RULE_HEIGHT)
		frame:SetPoint("TOPLEFT", panel.CategoryDropdown, "BOTTOMLEFT", 0, -(FILTER_ROW_OVERHANG + SECTION_TOP_GAP))
		return frame
	end
	local function place(frame, header)
		frame:SetPoint("TOPLEFT", header.Divider, "BOTTOMLEFT", 0, -SECTION_RULE_TO_CONTENT_GAP)
		frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -ROW_PADDING, ROW_PADDING)
	end

	local whispersSection = section(LFGF.WHISPERS_SECTION_TITLE)
	local whispers = LFGF.CreateWhisperLog(panel)
	place(whispers, whispersSection)
	panel.WhispersSection, panel.WhisperLog = whispersSection, whispers

	local pages = {
		filters = { panel.GroupSection, panel.RoleSection, panel.ClassSection, panel.MiscellaneousSection },
		whispers = { whispersSection, whispers },
	}
	local defs = {
		{ id = "filters", label = LFGF.FILTERS_TAB_TITLE, w = 108 },
		{ id = "whispers", label = LFGF.WHISPERS_TAB_TITLE, w = 150 },
	}
	panel.filtersTabID, panel.whispersTabID = "filters", "whispers"
	if LFGF.RatingsAvailable then
		local header = section(L.RECENT_ALLIES_SECTION_TITLE)
		local ratings = LFGF.CreatePlayerRatings(panel)
		place(ratings, header)
		panel.RatingsSection, panel.PlayerRatings = header, ratings
		panel.ratingsTabID = "ratings"
		pages.ratings = { header, ratings }
		defs[#defs + 1] = { id = "ratings", label = L.PLAYER_RATINGS, w = 160 }
		panel.ClearPlayerRatingLink = AddHeaderLink(header, L.CLEAR_PLAYER_RATING, LFGF.ShowClearPlayerRating)
	end

	local bar = CreateFrame("Frame", nil, panel)
	bar:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 3)
	bar:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 3)
	bar:SetHeight(30)
	local tabs = S.Tabs(bar, defs, function(selected)
		for id, frames in pairs(pages) do
			for _, frame in ipairs(frames) do frame:SetShown(id == selected) end
		end
	end)
	function panel:SetTab(id) tabs:Select(id) end

	if LFGF.RatingsAvailable then
		local function showRatings()
			local shown = LFGF.ShowPlayerRatings()
			if not shown and tabs:Selected() == "ratings" then tabs:Select("filters") end
			tabs.buttons.ratings:SetShown(shown)
		end
		showRatings()
		EventRegistry:RegisterCallback(LFGF.EVENT_PLAYER_RATINGS_CHANGED, showRatings, panel)
	end

	panel.ResetFiltersLink = AddHeaderLink(panel.GroupSection,
		LFGF.RESET_FILTERS_LABEL, function() ResetFilters(panel) end)
	BuildMyFilterControls(panel)
	panel.ClearChatLink = AddHeaderLink(whispersSection,
		LFGF.CLEAR_CHAT_LABEL, function() whispers:Clear() end)

	EventRegistry:RegisterCallback(LFGF.EVENT_WHISPER_RECEIVED, function()
		if tabs:Selected() ~= "whispers" then tabs:SetBadge("whispers", 1) end
	end, panel)
	tabs.buttons.whispers:HookScript("OnClick", function() tabs:SetBadge("whispers", 0) end)
	tabs:Select("filters")
end

-------------------------------------------------------
---------- The Role Check button
-------------------------------------------------------
-- BLIZZARD'S OWN, from the Listing tab of their camelot Group Finder
-- (Mainline/Blizzard_LFGVanilla_Listing.xml:413-433,
-- Blizzard_LFGVanilla_Listing.lua:612-637): a UIPanelButtonTemplate reading
-- ROLE_POLL, enabled for a group's leader or assistant, calling
-- InitiateRolePoll(). The API carries no HasRestrictions and no secret
-- annotation (UnitRoleDocumentation.lua:29-36); every member then gets
-- Blizzard's RolePollPopup (Blizzard_FrameXML/Mainline/RolePoll.lua), which
-- loads here and is in the running-client frame dump.
--
-- IT SITS IN THE SEARCH ROW, ON NEITHER TAB: it is about the group, not about
-- the filters or the whispers, so the player should not have to pick a tab to
-- find it.
--
-- ITS OWN LOCK, NOT THE ROW ACTIONS'. After a click it is disabled for
-- LFGF.ACTION_COOLDOWN_SECONDS, the addon's one delay (core/main.lua). Joining
-- the shared lock would have been less code and wrong: unlocking that one
-- enables every control it holds, and this button must stay off afterwards
-- for anyone who is no longer the leader. So its state is one rule, "may lead
-- a role check and not cooling down", re-applied from every input.

--- May the player start a role check? Blizzard's rule, Listing.lua:631-637.
---
--- UnitIsGroupLeader and UnitIsGroupAssistant are
--- SecretWhenUnitIdentityRestricted (UnitDocumentation.lua:2023, :2039) -- not
--- a combat predicate, so the out-of-combat assumption does not cover it. A
--- secret boolean cannot be tested from addon code, so each answer is checked
--- first, and an unreadable one FAILS OPEN: a non-leader's click only earns the
--- server's own refusal, while a leader shut out of the button has no way
--- round it. IsInGroup carries no documentation at all (it is in the client
--- dump, GlobalAPI.lua) and is guarded the same way.
local function CanStartRoleCheck()
	local inGroup = IsInGroup()
	if not canaccessvalue(inGroup) then
		return false
	end
	if not inGroup then
		return false
	end
	local leader = UnitIsGroupLeader("player")
	local assistant = UnitIsGroupAssistant("player")
	if not canaccessvalue(leader) or not canaccessvalue(assistant) then
		return false
	end
	return leader or assistant
end

local function UpdateRoleCheckButton(button)
	button:SetEnabled(not button.coolingDown and CanStartRoleCheck())
end

local function BuildRoleCheckButton(panel)
	local button = S.Button(panel, L.ROLE_CHECK, panel.Layout.roleCheckWidth, SEARCH_BUTTON_HEIGHT, "ghost")
	-- As Blizzard's XML does (Listing.xml:413): the tooltip below is the reason
	-- the button is off, so it has to show while the button is off.
	button:SetMotionScriptsWhileDisabled(true)
	button.coolingDown = false

	-- HUNG OFF THE SEARCH BUTTON, the way Search hangs off the activity
	-- dropdown, so both are centred on one chain and round to the same pixels.
	-- It was anchored TOPRIGHT to the panel at the same computed top, and at a
	-- UI scale of about 1.16 the two routes snapped differently: in the client
	-- its top edge and label sat one pixel above Search's. The gap is whatever
	-- the row leaves over once the button's own width is taken out, so its
	-- right edge sits the settings gear and its gap in from the row's end; the
	-- gear (BuildSettingsGear) takes the last ROW_PADDING-inset spot.
	button:SetPoint("LEFT", panel.SearchButton, "RIGHT",
		panel.Layout.searchRowSpare - button:GetWidth()
			- SETTINGS_GEAR_GAP - SETTINGS_GEAR_SIZE, 0)

	button:SetScript("OnClick", function(self)
		-- The lock is checked here as well as enforced by Disable(), as the
		-- row actions do (core/main.lua, RunAction).
		if self.coolingDown or InCombatLockdown() or not CanStartRoleCheck() then
			return
		end
		LFGF.PlayClick()
		InitiateRolePoll()

		self.coolingDown = true
		UpdateRoleCheckButton(self)
		C_Timer.After(LFGF.ACTION_COOLDOWN_SECONDS, function()
			self.coolingDown = false
			UpdateRoleCheckButton(self)
		end)
	end)

	-- Blizzard's text, ERR_LFG_ROLE_CHECK_ONLY_LEADER (Listing.xml:422-428),
	-- shown only when that is actually why: during the cooldown it would be
	-- wrong, and while the button works it needs no explaining.
	button:HookScript("OnEnter", function(self)
		if CanStartRoleCheck() then
			return
		end
		-- The addon's shared tooltip (LFGF.ShowTooltip): the button's name,
		-- then Blizzard's reason.
		LFGF.ShowTooltip(self, L.ROLE_CHECK, L.ROLE_CHECK_ONLY_LEADER)
	end)
	button:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Blizzard's two events (Listing.lua:613-614) and the roster, because
	-- Blizzard's panel picks up joining or leaving a group by being rebuilt on
	-- show, and this button never goes away.
	button:RegisterEvent("GROUP_ROSTER_UPDATE")
	button:RegisterEvent("PARTY_LEADER_CHANGED")
	button:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	button:SetScript("OnEvent", UpdateRoleCheckButton)

	UpdateRoleCheckButton(button)
	return button
end

-------------------------------------------------------
---------- The settings gear
-------------------------------------------------------
-- OPENS OPTIONS > ADDONS > LFG FOREVER, through LFGF.OpenSettings
-- (core/main.lua): the same call as the minimap button's and the compartment
-- entry's right click. That function owns the combat refusal (Blizzard refuses
-- the panel from addon code in combat, observed in the client) and the "page
-- not registered yet" case, so the gear has no combat code of its own.
--
-- Showing Blizzard's Settings panel closes this window: it is a centre UI
-- panel (Blizzard_Registration.lua:3-10), and showing one runs CloseWindows,
-- which hides every UISpecialFrames window (UIParentPanelManager.lua:288-289,
-- :1168). Accepted by the author, as for the minimap's right click.
--
-- On neither tab, like Role Check: the tab system only hides what is
-- registered with a tab.

local function BuildSettingsGear(panel)
	local gear = CreateFrame("Button", nil, panel)
	gear:SetSize(SETTINGS_GEAR_SIZE, SETTINGS_GEAR_SIZE)
	-- Off Role Check on the same chain, so the whole row rounds alike (the
	-- reason Role Check hangs off Search). Its right edge lands ROW_PADDING in
	-- from the panel's, because Role Check's offset leaves exactly that room.
	gear:SetPoint("LEFT", panel.RoleCheckButton, "RIGHT", SETTINGS_GEAR_GAP, 0)

	local icon = gear:CreateTexture(nil, "ARTWORK")
	icon:SetAtlas(SETTINGS_GEAR_ATLAS)
	icon:SetSize(SETTINGS_GEAR_SIZE, SETTINGS_GEAR_SIZE)
	icon:SetPoint("CENTER", gear, "CENTER", 0, 0)
	icon:SetAlpha(SETTINGS_GEAR_ALPHA)
	icon:SetVertexColor(unpack(S.colors.gold))
	gear.Icon = icon

	gear:SetScript("OnEnter", function(self)
		self.Icon:SetAlpha(SETTINGS_GEAR_HOVER_ALPHA)
		LFGF.ShowTextTooltip(self, L.SETTINGS)
	end)
	gear:SetScript("OnLeave", function(self)
		self.Icon:SetAlpha(SETTINGS_GEAR_ALPHA)
		GameTooltip:Hide()
	end)
	-- The press, as LFGOptionsButton:OnMouseDown / OnMouseUp do it.
	gear:SetScript("OnMouseDown", function(self)
		self.Icon:AdjustPointsOffset(SETTINGS_GEAR_PRESS_X, SETTINGS_GEAR_PRESS_Y)
	end)
	gear:SetScript("OnMouseUp", function(self)
		self.Icon:AdjustPointsOffset(-SETTINGS_GEAR_PRESS_X, -SETTINGS_GEAR_PRESS_Y)
	end)
	gear:SetScript("OnClick", function()
		LFGF.OpenSettings()
	end)
	return gear
end

-------------------------------------------------------
---------- Room for the words
-------------------------------------------------------
-- THE PANEL IS SIZED FOR ITS WORDS, never below the widths above. English fits
-- every minimum, so in English nothing here moves a pixel; a language pack
-- (core/locale.lua) can bring longer words, and then a grid's columns, the
-- panel, or both widen just enough. Nothing is ever narrowed. The window is
-- not resized: the list column takes whatever the filter panel leaves
-- (core/window.lua), so a wider panel only narrows the list.
--
-- Measured with hidden font strings in the fonts the real controls use, before
-- anything is built, because every section's width comes from the answer.
-- GetStringWidth is readable: these are our own strings, never secret.

-- Where a checkbox's label starts in its cell: the 32-wide box
-- (CheckButtonTemplates.xml:51), the gap, the icon and the gap after it --
-- the chain BuildRoleCheck anchors.
local CHECK_LABEL_X = 32 + ROLE_BOX_TO_ICON_GAP + ROLE_ICON_SIZE + ROLE_ICON_TO_LABEL_GAP

-- The least room between Role Check and Search, and between a section's title
-- and the links at its right end, when the words are long: Blizzard's own
-- activity-to-refresh gap (ACTIVITY_TO_SEARCH_GAP), so it reads as one row.
local MIN_ROW_GAP = ACTIVITY_TO_SEARCH_GAP

--- How wide the panel and its grids must be for the words they hold.
local function MeasureLayout(panel)
	local probes = {}
	local function Width(text, fontObject)
		local probe = probes[fontObject]
		if not probe then
			probe = S.Text(panel, fontObject == "GameFontNormalLarge" and 16 or 12, S.colors.text)
			probe:Hide()
			probes[fontObject] = probe
		end
		probe:SetText(text)
		return probe:GetStringWidth()
	end

	--- The column width a grid needs: its widest label's end, never below
	--- `minimum`. Checkbox labels are GameFontNormalSmall, UICheckButtonTemplate's
	--- own (CheckButtonTemplates.xml:54).
	local function Column(rows, minimum)
		local width = minimum
		for _, row in ipairs(rows) do
			for _, cell in ipairs(row) do
				width = math.max(width, CHECK_LABEL_X + Width(cell.label, "GameFontNormalSmall"))
			end
		end
		return width
	end

	local function MostColumns(rows)
		local most = 0
		for _, row in ipairs(rows) do
			most = math.max(most, #row)
		end
		return most
	end

	local classRows = BuildClassRows()

	-- The player grid also holds the two bulk links, each nudged into its cell
	-- (BuildClassBulkButtons) and as wide as its words.
	local playerColumn = math.max(Column(PLAYER_ROLE_ROWS, PLAYER_COLUMN_WIDTH),
		Column(classRows, PLAYER_COLUMN_WIDTH),
		CLASS_LINK_INSET_X + Width(LFGF.UNSELECT_ALL_CLASSES_LABEL, "GameFontNormalSmall"),
		CLASS_LINK_INSET_X + Width(LFGF.SELECT_ALL_CLASSES_LABEL, "GameFontNormalSmall"))
	local groupColumn = Column(GROUP_FILTER_ROWS, GROUP_COLUMN_WIDTH)

	-- The search row: Role Check is fitted to its words plus its padding
	-- (BuildRoleCheckButton; UIPanelButtonTemplate's text is GameFontNormal),
	-- and the settings gear follows it.
	local roleCheckWidth = Width(L.ROLE_CHECK, "GameFontNormal") + ROLE_CHECK_LABEL_PADDING
	local searchRow = SEARCH_ROW_FIXED_WIDTH + MIN_ROW_GAP + roleCheckWidth
		+ SETTINGS_GEAR_GAP + SETTINGS_GEAR_SIZE

	-- The two title lines: the title on the left, the links on the right
	-- (AddHeaderLink, BuildMyFilterControls), with everything that can show.
	local link, separator = "GameFontNormalSmall", "GameFontDisableSmall"
	local separatorWidth = HEADER_LINK_GAP + Width(LFGF.SEPARATOR, separator) + HEADER_LINK_GAP
	-- Every Filters-tab title starts after its +/- and the gap, and is followed
	-- by room for the warning a collapsed section can show (BuildHeader,
	-- core/filterpanel_shared.lua). The Whispers and Recent allies titles have
	-- neither.
	local headerIcons = Shared.COLLAPSE_ICON_WIDTH + Shared.COLLAPSE_ICON_TO_TITLE_GAP
		+ Shared.TITLE_TO_WARNING_GAP + Shared.WARNING_ICON_SIZE
	local function TitleWidth(text) return headerIcons + Width(text, "GameFontNormalLarge") end
	local groupTitleLine = TitleWidth(LFGF.GROUP_SECTION_TITLE) + MIN_ROW_GAP
		+ Width(LFGF.MY_FILTERS_LABEL, link) + MY_FILTERS_CARET_GAP + MY_FILTERS_CARET_WIDTH
		+ separatorWidth + Width(LFGF.SAVE_NEW_FILTER_LABEL, link)
		+ separatorWidth + Width(LFGF.RESET_FILTERS_LABEL, link)
	local whispersTitleLine = Width(LFGF.WHISPERS_SECTION_TITLE, "GameFontNormalLarge")
		+ MIN_ROW_GAP + Width(LFGF.CLEAR_CHAT_LABEL, link)
	local ratingsTitleLine = LFGF.RatingsAvailable and (Width(L.RECENT_ALLIES_SECTION_TITLE, "GameFontNormalLarge")
		+ MIN_ROW_GAP + Width(L.CLEAR_PLAYER_RATING, link)) or 0
	-- The Miscellaneous row (core/filterpanel_miscellaneous.lua): the Playstyle
	-- label in the checkbox labels' font, the gap and its dropdown's fixed
	-- width; then the least gap, and the Languages label, gap and dropdown,
	-- flush right.
	local playstyleRow = Shared.ROW_LABEL_INSET_X
		+ Width(LFGF.PLAYSTYLE_ROW_LABEL, "GameFontNormalSmall")
		+ Shared.ROW_LABEL_TO_CONTROL_GAP + LFGF.PLAYSTYLE_DROPDOWN_WIDTH
		+ MIN_ROW_GAP
		+ Width(LFGF.LANGUAGES_ROW_LABEL, "GameFontNormalSmall")
		+ Shared.ROW_LABEL_TO_CONTROL_GAP + LFGF.LANGUAGES_DROPDOWN_WIDTH
	-- The Groups section's class dropdown (core/filterpanel_groupclasses.lua):
	-- the cells before it, its inset into its cell, its text insets, and the
	-- widest text it can show, in the template's own font, GameFontHighlight
	-- (Mainline/MenuTemplates.xml:18). It reaches the content's right edge, so
	-- a longer text widens the panel rather than being cut short.
	local groupClassText = 0
	for _, text in ipairs(LFGF.GroupClassFilterTexts()) do
		groupClassText = math.max(groupClassText, Width(text, "GameFontHighlight"))
	end
	local groupClassRow = #GROUP_FILTER_ROWS[#GROUP_FILTER_ROWS] * groupColumn
		+ LFGF.GROUP_CLASS_DROPDOWN_INSET + LFGF.GROUP_CLASS_DROPDOWN_TEXT_INSETS
		+ groupClassText

	local content = math.max(MostColumns(PLAYER_ROLE_ROWS) * playerColumn,
		MostColumns(classRows) * playerColumn,
		MostColumns(GROUP_FILTER_ROWS) * groupColumn,
		searchRow, groupTitleLine, whispersTitleLine, ratingsTitleLine, playstyleRow,
		groupClassRow,
		TitleWidth(LFGF.ROLE_SECTION_TITLE), TitleWidth(LFGF.CLASS_SECTION_TITLE),
		TitleWidth(LFGF.MISCELLANEOUS_SECTION_TITLE))
	local panelWidth = math.max(FILTER_PANEL_WIDTH, 2 * ROW_PADDING + content)

	return {
		panelWidth = panelWidth,
		playerColumn = playerColumn,
		groupColumn = groupColumn,
		classRows = classRows,
		-- What the search row leaves for Role Check, the settings gear and
		-- their gaps.
		searchRowSpare = panelWidth - 2 * ROW_PADDING - SEARCH_ROW_FIXED_WIDTH,
		roleCheckWidth = roleCheckWidth,
	}
end

--- Build the filter panel. Returns it unanchored -- the caller places it.
function LFGF.CreateFilterPanel(parent)
	local panel = S.Box(parent, S.colors.panel, S.colors.line)
	-- Measured before anything is built: every section, grid and the search
	-- row lay out from it.
	panel.Layout = MeasureLayout(panel)
	panel:SetWidth(panel.Layout.panelWidth)

	panel.selectedCategoryID = 0
	panel.selectedActivityIDs = {}
	panel:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
	panel:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
	panel:RegisterEvent("LFG_LIST_SEARCH_FAILED")
	panel:RegisterEvent("ADDON_ACTION_BLOCKED")
	panel:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	panel:SetScript("OnEvent", function(self, event, owner, action)
		if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
			if not self.submitting or LFGF.Readable(owner, nil) ~= Q.name then return end
			action = LFGF.Readable(action, "")
			self.searchBlocked = action == "C_LFGList.Search" or action == "C_LFGList.Search()"
				or action == "UNKNOWN" or action == "UNKNOWN()" or self.searchBlocked
			return
		end
		if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
			FinishSearch(self, "")
			return
		elseif event == "LFG_LIST_SEARCH_FAILED" then
			self.searchFailed = true
			FinishSearch(self, "WoW signale un échec de la recherche.")
			return
		end
		SelectFirstCategory(self)
		if self.selectedCategoryID > 0
			and DropUnofferedActivities(self, LFGF.Activities(self.selectedCategoryID))
			and self.ActivityDropdown:IsMenuOpen() then
			self.ActivityDropdown:GenerateMenu()
		end
	end)

	function panel:IsAnyActivitySelectedInGroup(activityGroupID)
		for _, activityID in ipairs(LFGF.Activities(self.selectedCategoryID, activityGroupID)) do
			if ActivityIsSelected(self, activityID) then
				return true
			end
		end
		return false
	end

	function panel:SetAllActivitiesInGroup(activityGroupID, selected)
		for _, activityID in ipairs(LFGF.Activities(self.selectedCategoryID, activityGroupID)) do
			if ActivityIsSelected(self, activityID) ~= selected then
				ActivityToggle(self, activityID)
			end
		end
	end

	--- Browse.lua:1242-1254: default text, the single activity's name, or a count.
	--- One difference: GetActivityInfoTable is MayReturnNothing
	--- (LFGListInfoDocumentation.lua:186) and LFGUtil_GetActivityInfoName
	--- indexes what it is handed (ParentFrame.lua:284), so a single activity
	--- the client no longer describes shows the count ("1 activity selected")
	--- instead of raising an error.
	function panel:UpdateActivityHeader()
		local selected = self.selectedActivityIDs
		local activityInfo = #selected == 1 and C_LFGList.GetActivityInfoTable(selected[1])
		if #selected == 0 then
			self.ActivityDropdown:OverrideText(L.ACTIVITY_HEADER_DEFAULT)
		elseif activityInfo then
			self.ActivityDropdown:OverrideText(LFGUtil_GetActivityInfoName(activityInfo))
		else
			self.ActivityDropdown:OverrideText(string.format(L.ACTIVITY_HEADER_FORMAT, #selected))
		end
	end

	function panel:SetupActivityMenu() LFGF.SetupActivityMenu(self) end

	function panel:UpdateSearchState()
		self.SearchButton:SetEnabled(self.selectedCategoryID > 0 and not self.searching)
	end

	function panel:RequestSearch() return RequestSearch(self) end

	--- What the Filters tab says right now, as a fresh snapshot: what Search
	--- would send. core/window.lua hands it to the list when both are built,
	--- so the list starts filtered the way the restored boxes say.
	function panel:CurrentFilters() return FilterSnapshot(self) end

	--- The activities ticked in the activity dropdown RIGHT NOW, in the order
	--- they were ticked, as a fresh copy: nothing outside can change the
	--- selection through it. Not a search snapshot -- a tick counts before
	--- Search is clicked. core/window.lua hands this to the invite whisper
	--- (LFGF.SetInviteActivitySource, core/main.lua), which names them when the
	--- player has no listing. Deliberately NOT part of FilterSnapshot: that
	--- shape is what is saved and what My filters keep, and activities are
	--- neither (.claude/rules/saved-filters.md).
	function panel:SelectedActivityIDs() return CopyTable(self.selectedActivityIDs) end

	--- Switch to the Player ratings tab, while its setting shows it. Called by
	--- LFGF.OpenPlayerRatings (core/window.lua). SetTab, so the tab's list is
	--- shown and the other tabs' content hidden (TabSystemOwner.lua:46-51).
	function panel:ShowPlayerRatingsTab()
		if LFGF.ShowPlayerRatings() then
			self:SetTab(self.ratingsTabID)
		end
	end

	local category = LFGF.CreateDropdown(panel)
	category:SetWidth(CATEGORY_DROPDOWN_WIDTH)
	category:SetDefaultText(L.CATEGORY)
	category:SetPoint("TOPLEFT", panel, "TOPLEFT", ROW_PADDING, -ROW_PADDING)
	panel.CategoryDropdown = category

	local activity = LFGF.CreateDropdown(panel)
	activity:SetWidth(ACTIVITY_DROPDOWN_WIDTH)
	activity:SetDefaultText(L.ACTIVITY_HEADER_DEFAULT)
	activity:SetPoint("LEFT", category, "RIGHT", CATEGORY_TO_ACTIVITY_GAP, 0)
	panel.ActivityDropdown = activity

	panel.SearchButton = BuildSearchButton(panel)
	panel.SearchButton:SetPoint("LEFT", activity, "RIGHT", ACTIVITY_TO_SEARCH_GAP, 0)

	panel.RoleCheckButton = BuildRoleCheckButton(panel)
	panel.SettingsGear = BuildSettingsGear(panel)

	-- NOTHING BETWEEN THE FILTER ROW AND THE SECTIONS. A one-line notice with a
	-- link to the settings page ("You can configure the addon and report bugs
	-- in LFG Forever settings") sat here from 0.3.0 until 0.10.0-dev.1, when the
	-- author removed it to give the role section room for its Level row. The
	-- settings page is still one click away: right-click the minimap button or
	-- the addon compartment entry (core/minimap.lua), or Options > AddOns.

	-- Anchored to the CATEGORY dropdown, not the Search button: the dropdown
	-- is the row's left edge, which is where a section should line up. The
	-- Search button's overhang (FILTER_ROW_OVERHANG) is added so the rule
	-- clears it.
	-- GROUPS, PLAYER ROLES, PLAYER CLASSES, MISCELLANEOUS -- top to bottom.
	--
	-- Groups lead because browsing for a group is the common case, and the
	-- class grid follows the role sections because it is much the tallest and
	-- the least often touched. Miscellaneous, the catch-all, comes last
	-- (0.22.0-dev.1); the bottom of the stack is the only place a section's
	-- height costs nothing, since nothing hangs off it.
	--
	-- THE ORDER LIVES HERE AND NOWHERE ELSE: panel.FilterSections, below.
	-- LayOutSections hangs each section off the one above it through its
	-- StackAnchor, so reordering is reordering that list -- no section knows
	-- what precedes it, which is the whole point of BuildSection.
	--
	-- EACH IS COLLAPSIBLE (0.22.0-dev.2): its +/- header saves its key under
	-- QuinteLFGDB.collapsedFilterSections and calls LayOutSections, which
	-- hangs the next section off a collapsed one's rule instead of its content.
	-- .claude/rules/collapsible-filter-sections.md
	--
	-- ALL OFF for the group filters: these AND together, and "available" with
	-- "has" for the same role is a contradiction, so every box ticked would
	-- show nothing at all. No group filter until the player asks for one.
	local groupChecks
	panel.GroupSection, groupChecks = BuildRoleCheckSection(panel, LFGF.GROUP_SECTION_TITLE,
		GROUP_FILTER_ROWS, false, panel.Layout.groupColumn, "groups")
	panel.GroupFilterChecks = groupChecks.group
	-- The class filter takes the cell after the last box ("Has healer"),
	-- PLACED FROM THE ROWS, as the class section's bulk links are, centred on
	-- that row like the boxes' labels (core/filterpanel_groupclasses.lua).
	do
		local lastRow = #GROUP_FILTER_ROWS
		local x, rowTop = GridCell(#GROUP_FILTER_ROWS[lastRow] + 1, lastRow, panel.Layout.groupColumn)
		LFGF.BuildGroupClassFilter(panel, panel.GroupSection, x, rowTop - ROLE_ROW_HEIGHT / 2)
	end

	-- ALL ON for both player sections: every role and every class ticked means
	-- "show everyone", which is the right start for a filter nobody has
	-- touched.
	local roleChecks
	panel.RoleSection, roleChecks = BuildRoleCheckSection(panel, LFGF.ROLE_SECTION_TITLE,
		PLAYER_ROLE_ROWS, true, panel.Layout.playerColumn, "roles")
	panel.PlayerRoleChecks = roleChecks.roles
	-- The Level row is the role section's second row: it narrows the same
	-- solo players the role boxes do, so it shares their heading.
	BuildLevelRow(panel, panel.RoleSection)

	local classChecks
	local classRows = panel.Layout.classRows
	panel.ClassSection, classChecks = BuildRoleCheckSection(panel, LFGF.CLASS_SECTION_TITLE,
		classRows, true, panel.Layout.playerColumn, "classes")
	panel.PlayerClassChecks = classChecks.classes
	BuildClassBulkButtons(panel, classRows)

	-- Built by its own file (core/filterpanel_miscellaneous.lua), stacked here
	-- with the rest.
	panel.MiscellaneousSection = LFGF.BuildMiscellaneousSection(panel)

	panel.FilterSections = { panel.GroupSection, panel.RoleSection,
		panel.ClassSection, panel.MiscellaneousSection }

	--- Stack the sections, top to bottom, each off the one above's StackAnchor
	--- (its content, or its rule while collapsed) at SECTION_TOP_GAP. Run at
	--- build and by every section header's click. ClearAllPoints first, so a
	--- section only ever has the one anchor.
	---
	--- THE LEADING SECTION hangs off the category dropdown -- the filter row,
	--- which sits above the tabs and is never hidden by them -- and it is the
	--- one that clears the Search button's overhang.
	function panel:LayOutSections()
		local above, gap = self.CategoryDropdown, FILTER_ROW_OVERHANG + SECTION_TOP_GAP
		for _, section in ipairs(self.FilterSections) do
			section:ClearAllPoints()
			section:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
			above, gap = section.StackAnchor, SECTION_TOP_GAP
		end
	end

	-- THE SAVED COLLAPSED SECTIONS, restored here and only here, once a
	-- session like the saved Filters tab below. A key no section has is
	-- ignored.
	local collapsed = LFGF.CollapsedFilterSections()
	for _, section in ipairs(panel.FilterSections) do
		if collapsed[section.collapseKey] then
			SetSectionCollapsed(section, true)
		end
	end
	panel:LayOutSections()

	BuildTabs(panel)

	SetupCategoryMenu(panel)
	panel:SetupActivityMenu()
	panel:UpdateActivityHeader()
	SelectFirstCategory(panel)
	panel:UpdateSearchState()

	-- The panel is the owner, so one panel registers once however often the
	-- setting changes -- the whisper log's pattern (core/whisperlog.lua).
	EventRegistry:RegisterCallback(LFGF.EVENT_LEVEL_RANGES_CHANGED, function()
		LevelRangesChanged(panel)
	end, panel)

	-- THE SAVED FILTERS TAB, restored here and only here. The panel is built
	-- once a session (core/window.lua builds the window lazily and never
	-- again), so this is "load once per session" by construction: a change
	-- not searched survives closing the window, and a /reload brings back
	-- what was last searched or reset. See .claude/rules/saved-filters.md.
	ApplyFilters(panel, LFGF.SavedFilters())

	-- Blizzard's Defaults button forgot the record (core/settings.lua ->
	-- LFGF.ForgetSavedFilters): put the boxes back to match. Nothing is saved,
	-- so the record stays forgotten, and the list is left to the next Search.
	EventRegistry:RegisterCallback(LFGF.EVENT_FILTERS_FORGOTTEN, function()
		ApplyFilters(panel, nil)
	end, panel)

	-- Blizzard's Defaults button forgot the collapsed sections too
	-- (LFGF.ForgetCollapsedFilterSections): expand them all. Nothing is saved,
	-- so the record stays forgotten.
	EventRegistry:RegisterCallback(LFGF.EVENT_FILTER_SECTIONS_FORGOTTEN, function()
		for _, section in ipairs(panel.FilterSections) do
			SetSectionCollapsed(section, false)
		end
		panel:LayOutSections()
	end, panel)

	return panel
end

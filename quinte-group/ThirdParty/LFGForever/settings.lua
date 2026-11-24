-- QuinteLFG -- core/settings.lua
--
-- The addon's page under Options -> AddOns, and the saved tables behind it
-- (QuinteLFGDB account-wide; QuinteLFGCharDB per character, for the Ask to
-- Join and Invite messages): the whisper log size, Auto-whisper on Ask to Join
-- and on Invite, each with its message; a Search section (Show all level
-- activities, Show suggested level ranges, the two guild / friend mark
-- options, Sort players by); and a Miscellaneous section (the Open LFG Forever
-- key binding, Player ratings, Show minimap button, a sentence about the
-- language packs, a Report a bug button, a Reset window position and size
-- button).
--
-- BLIZZARD'S OWN SETTINGS PANEL, BUILT FROM ITS OWN CONTROLS -- the pattern
-- BugSack uses on this very client (examples/BugSack/config.lua, whose Forever
-- build loads it with no game-type condition). No layout code of ours: the
-- category, the setting and the slider are all Blizzard's, so the page looks
-- and behaves like every other one in the panel. No libraries either
-- (AceConfig would draw the same panel through the same API).
--
-- THE API LOADS ON CAMELOT: `element_check.py global Settings` ->
-- Blizzard_Settings_Shared/Blizzard_Settings.lua:6, LOADS; and SettingsPanel is
-- in the running-client frame dump (Frames.lua:311).
--
-- IT WAITS FOR ADDON_LOADED because the saved table does not exist before it:
-- the client assigns QuinteLFGDB from disk just before that event, or leaves it
-- nil on a first install. RegisterAddOnSetting asserts it is handed a table
-- (Blizzard_Setting.lua:418), so registering at file scope would error.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

-- EVERY SAVED KEY, its Settings variable, its saved table, type and default
-- come from core/db.lua (LFGF.SAVED_KEYS, loaded second). This page only says
-- which rows to build, in which order, with which words.
local SAVED = {}
for _, entry in ipairs(LFGF.SAVED_KEYS) do
	SAVED[entry.key] = entry
end

-- core/db.lua's Lua type names, as Blizzard's Settings.VarType names them
-- (Blizzard_Settings.lua; the three kinds this page uses).
local VAR_TYPE_NAMES = { boolean = "Boolean", number = "Number", string = "String" }

--- Register one saved key as a Blizzard add-on setting. Blizzard writes the
--- entry's default into its table when the key is nil -- `== nil`, so a saved
--- false, 0 or "" survives (Blizzard_Setting.lua:398-402, :426).
local function RegisterSetting(category, key, label)
	local entry = assert(SAVED[key], key)
	return Settings.RegisterAddOnSetting(category,                          -- :174
		entry.variable, entry.key, LFGF.SavedTable(entry.scope),
		Settings.VarType[VAR_TYPE_NAMES[entry.type]], label, entry.default)
end

-- 50 to 500 in steps of 50, around the default of 200 -- a slider rather than a
-- text box, so no value outside the range can be entered at all.
local WHISPER_LOG_SIZE_MIN, WHISPER_LOG_SIZE_MAX, WHISPER_LOG_SIZE_STEP = 50, 500, 50

local WHISPER_LOG_SIZE_LABEL = L.SETTINGS_WHISPER_LOG_SIZE_LABEL
local WHISPER_LOG_SIZE_TOOLTIP = L.SETTINGS_WHISPER_LOG_SIZE_TOOLTIP

-------------------------------------------------------
---------- Auto-whisper on Ask to Join
-------------------------------------------------------
-- A checkbox, and under it the message it sends. ON by default, keeping what
-- Ask to Join has always done. Off -- or on with an empty message -- Ask to Join
-- opens a whisper for the player to type in (LFGF.AskToJoinMessage, main.lua).
local AUTO_WHISPER_LABEL = L.SETTINGS_ASK_TO_JOIN_AUTO_WHISPER_LABEL
local AUTO_WHISPER_TOOLTIP = L.SETTINGS_ASK_TO_JOIN_AUTO_WHISPER_TOOLTIP

-- THE MESSAGE IS SAVED PER CHARACTER (since 0.11.0), in QuinteLFGCharDB --
-- ## SavedVariablesPerCharacter in QuinteLFG.toc -- so each character can
-- introduce itself in its own words. The Auto-whisper checkbox above it stays
-- account-wide. The variable and the key kept the names they shipped with
-- (core/db.lua).
local MESSAGE_LABEL = L.SETTINGS_ASK_TO_JOIN_MESSAGE_LABEL
local MESSAGE_TOOLTIP = L.SETTINGS_ASK_TO_JOIN_MESSAGE_TOOLTIP
-- What the row's "?" lists: each placeholder and what it becomes, in order.
local MESSAGE_PLACEHOLDERS = {
	{ "%class%", L.SETTINGS_PLACEHOLDER_CLASS },
	{ "%level%", L.SETTINGS_PLACEHOLDER_LEVEL },
	{ "%talents%", L.SETTINGS_PLACEHOLDER_TALENTS },
	{ "%role%", L.SETTINGS_PLACEHOLDER_ROLE },
}
local MESSAGE_MAX_LETTERS = 200

-------------------------------------------------------
---------- Auto-whisper on Invite
-------------------------------------------------------
-- Since 0.12.0-dev.1 (.claude/rules/invite-whisper.md): the players list's
-- invite button also whispers the player (LFGF.InviteWhisperMessage, main.lua).
-- The same shape as Ask to Join, right under it: the checkbox account-wide and
-- ON by default, the message its child row, saved PER CHARACTER from the start
-- -- so, unlike Ask to Join's, there is no account-wide message to copy, and
-- RegisterAddOnSetting writes the default into a character with none.
local INVITE_AUTO_WHISPER_LABEL = L.SETTINGS_INVITE_AUTO_WHISPER_LABEL
local INVITE_AUTO_WHISPER_TOOLTIP = L.SETTINGS_INVITE_AUTO_WHISPER_TOOLTIP

local INVITE_MESSAGE_LABEL = L.SETTINGS_INVITE_MESSAGE_LABEL
local INVITE_MESSAGE_TOOLTIP = L.SETTINGS_INVITE_MESSAGE_TOOLTIP
local INVITE_MESSAGE_PLACEHOLDERS = {
	{ "%dungeon%", L.SETTINGS_PLACEHOLDER_DUNGEON },
	{ "%dungeon_en%", L.SETTINGS_PLACEHOLDER_DUNGEON_EN },
}

-- EVERY OLDER DEFAULT OF THE INVITE MESSAGE, exactly as RegisterAddOnSetting
-- wrote it into each character on its first load (Blizzard_Setting.lua:398-402).
-- A character holding one of these never edited it, so it moves to the
-- current default; anything else the player typed is theirs. Kept for as long
-- as a character not played since 2.1.0 may still hold one
-- (.claude/rules/addon-settings.md, item 4;
-- .claude/rules/dungeon-en-placeholder.md).
local INVITE_OLD_DEFAULT_MESSAGES = {
	"Hey! Want to join %dungeon%?",   -- 0.12.0 to 2.1.0
}

-- THE MESSAGE FIELD IS OUR OWN ROW: Blizzard ships no text-input settings row
-- (none of the Settings.Create* / CreateSettings*Initializer helpers makes one).
-- The template, core/settings.xml, is laid out like Blizzard's rows -- a label,
-- a hover area with its tooltip -- and adds an InputBoxTemplate EditBox where
-- Blizzard's own controls sit, at the row's centre - 80
-- (Blizzard_SettingControls.lua:592). It inherits none of Blizzard's rows.
local MESSAGE_ROW_TEMPLATE = "QuinteLFGSettingsMessageRowTemplate"

-- THE "?" LIST'S LOOK, Blizzard's own. Each placeholder is one line: the quest
-- bullet, the very markup this client's strings use for a list
-- (HOUSING_ADD_NEIGHBORHOOD_MANAGER_CONFIRMATION, GlobalStrings/enUS.lua
-- :11260), then the keyword in the tooltip's highlight white -- WoW text has no
-- bold, and white in a gold line is how Blizzard marks a word out
-- (CROSS_FACTION_INVITE_TOOLTIP, :5502) -- then its description in gold.
local PLACEHOLDER_BULLET = "|TInterface/QuestFrame/UI-Quest-BulletPoint.blp:0|t "

--- A keyword in the tooltip's highlight white. HIGHLIGHT_FONT_COLOR is made at
--- load from the client's colour table, so no file assigns it; the plain
--- keyword is kept if it is ever missing.
local function Highlight(text)
	if HIGHLIGHT_FONT_COLOR then
		return HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(text)
	end
	return text
end

--- The message row's behaviour. A GLOBAL because core/settings.xml attaches it
--- by name (mixin="..."), and XML resolves mixins through _G; namespaced
--- because every addon's globals share one table.
---
--- ONLY THE FOUR METHODS BLIZZARD CALLS INSIDE ITS PROTECTED CALLS: Init and
--- Release (ScrollUtil.lua's ScrollBoxFactoryInitializerMixin InitFrame /
--- Resetter, run under securecallfunction, Blizzard_SettingsList.lua:57-66),
--- and SetValue and EvaluateState, which run from Init or from setting
--- callbacks (secureexecuterange, CallbackRegistry.lua:184-214). Blizzard's
--- list reads a row outside its protection too (ScrollBoxListView.lua:111,
--- :361-395), so the row carries no Blizzard row method as a value of ours;
--- .claude/rules/settings-list-taint.md. What Blizzard's
--- SettingsListElementMixin and SettingsControlMixin do for a row
--- (Blizzard_SettingControls.lua:284-555) is done below by local functions:
--- the label, its tooltip, following the setting and the checkbox above,
--- greying out. Left out: the new-feature badge, kiosk mode, narration and
--- gamepad navigation, which these rows never use.
QuinteLFGSettingsMessageRowMixin = {}
local MessageRow = QuinteLFGSettingsMessageRowMixin

-- A row under a checkbox: indented by Blizzard's own step (`local indentSize
-- = 15;`, Blizzard_SettingControls.lua:1) before the 37 every label starts at
-- (:340).
local CHILD_ROW_INDENT = 15
local LABEL_INSET = 37

--- The setting changed from elsewhere (Defaults, another row). A callback is
--- called as (owner, setting, value) (CallbackRegistry.lua:208-213).
local function OnSettingChanged(row, _, value)
	row:SetValue(value)
end

--- The checkbox above was ticked or unticked.
local function OnParentSettingChanged(row)
	row:EvaluateState()
end

--- What an OnLoad would do, done on the row's first Init, inside Blizzard's
--- protected call: the callback container Blizzard's rows make in theirs
--- (Blizzard_SettingControls.lua:286-288), Blizzard's hover frame behind the
--- label's tooltip and the "?" (DefaultTooltipMixin, :3-58), and the box's own
--- scripts. The panel pools rows, so a frame keeps them for every later Init.
local function SetUpOnFirstInit(row)
	if row.cbrHandles then
		return
	end
	row.cbrHandles = Settings.CreateCallbackHandleContainer()
	for _, hover in ipairs({ row.Tooltip, row.Help }) do
		Mixin(hover, DefaultTooltipMixin)
		hover:OnLoad()
	end

	local editBox = row.EditBox
	editBox:SetMaxLetters(MESSAGE_MAX_LETTERS)
	editBox:SetAutoFocus(false)

	-- SAVE ONLY WHAT THE PLAYER TYPED. OnTextChanged also fires when the code
	-- sets the text (Init, Defaults), and saving that back would be a loop that
	-- achieves nothing. userInput tells the two apart.
	editBox:SetScript("OnTextChanged", function(box, userInput)
		if userInput and row.data then
			row.data.setting:SetValue(box:GetText())
		end
	end)

	-- Enter just finishes editing; Escape is InputBoxTemplate's own
	-- (EditBox_ClearFocus, InputBoxTemplates.xml:7). Each keystroke is already
	-- saved, so there is nothing to commit. Nothing of ours may run on show,
	-- hide, resize or focus loss: Blizzard's list causes those itself, outside
	-- its protection.
	editBox:SetScript("OnEnterPressed", function(box)
		box:ClearFocus()
	end)
end

function MessageRow:Init(initializer)
	SetUpOnFirstInit(self)
	self.data = initializer.data

	-- The label, as Blizzard's rows set theirs: a child row's smaller font,
	-- indented under its checkbox (Blizzard_SettingControls.lua:337-341), and
	-- the row's tooltip over it (:347, :60-62). The checkbox is the row's own
	-- data.parentSetting, not Blizzard's parent link (see the call site).
	local parentSetting = self.data.parentSetting
	local indent = parentSetting and CHILD_ROW_INDENT or 0
	self.Text:SetFontObject(parentSetting and "GameFontNormalSmall" or "GameFontNormal")
	self.Text:SetText(initializer:GetName())
	self.Text:SetPoint("LEFT", self, "LEFT", indent + LABEL_INSET, 0)
	self.Text:SetPoint("RIGHT", self, "CENTER", -85, 0)
	self.Tooltip:SetTooltipFunc(function()
		Settings.InitTooltip(initializer:GetName(), initializer:GetTooltip())
	end)

	-- Follow the checkbox above (:315-321) and the setting itself (:503-506).
	if parentSetting then
		self.cbrHandles:SetOnValueChangedCallback(parentSetting:GetVariable(), OnParentSettingChanged, self)
	end
	local setting = self.data.setting
	self.cbrHandles:SetOnValueChangedCallback(setting:GetVariable(), OnSettingChanged, self)
	self.EditBox:SetText(setting:GetValue() or "")

	-- The "?" lists this row's placeholders in the panel's own tooltip, as the
	-- label shows its tooltip: a white title, as Settings.InitTooltip writes
	-- one (Blizzard_Settings.lua:289-298), then one gold, wrapped line per
	-- placeholder. Set on every Init: one pooled frame serves both messages.
	local placeholders = self.data.placeholders
	self.Help:SetTooltipFunc(function()
		GameTooltip_AddHighlightLine(SettingsTooltip, L.SETTINGS_PLACEHOLDERS_TITLE)
		for _, placeholder in ipairs(placeholders) do
			GameTooltip_AddNormalLine(SettingsTooltip,
				PLACEHOLDER_BULLET .. Highlight(placeholder[1]) .. " - " .. placeholder[2])
		end
	end)
	self:EvaluateState()
end

--- The setting changed from elsewhere -- the Defaults button, or another row.
function MessageRow:SetValue(value)
	value = value or ""
	if self.EditBox:GetText() ~= value then
		self.EditBox:SetText(value)
	end
end

--- Usable only while the checkbox above is ticked (data.parentSetting), and
--- greyed out as Blizzard's rows are
--- (Blizzard_SettingControls.lua:290-300). Every ColorMixin colour has r, g
--- and b fields (Color.lua:45-50). Not Blizzard's SetShown(ShouldShow())
--- (Blizzard_SettingControls.lua:397-400): the list
--- itself shows only rows whose ShouldShow is true (Blizzard_SettingsList.lua
--- :118, :143), and these rows have no shown predicate.
function MessageRow:EvaluateState()
	local parentSetting = self.data.parentSetting
	local enabled = not parentSetting or not not parentSetting:GetValue()
	self.EditBox:SetEnabled(enabled)
	local color = enabled and NORMAL_FONT_COLOR or GRAY_FONT_COLOR
	self.Text:SetTextColor(color.r, color.g, color.b)
	self:DesaturateHierarchy(enabled and 0 or 1)
end

--- The panel let the frame go: drop focus and every callback, so a pooled
--- frame no longer follows this row's settings (Blizzard_SettingControls.lua
--- :361-365).
function MessageRow:Release()
	self.EditBox:ClearFocus()
	self.cbrHandles:Unregister()
	self.data = nil
end

-------------------------------------------------------
---------- Search
-------------------------------------------------------
-- One of Blizzard's checkbox rows under a header: LFG Forever's own copy of
-- the "Show All Level Ranges" option Blizzard keeps in its Group Finder's gear
-- menu (Blizzard_LFGVanilla_Browse.lua:1274-1280). Saved in QuinteLFGDB, NOT
-- in Blizzard's CVar -- see showAllLevelRanges in core/db.lua for why -- so
-- the two finders' options are independent. Its change is re-announced over EventRegistry, and core/filterpanel.lua
-- rebuilds its dropdowns at once.
local SEARCH_HEADER = L.SETTINGS_SEARCH_HEADER
-- The label is our own, in the page's sentence case. Until 0.9.0-dev.7 it
-- was Blizzard's string for the same checkbox, LFG_LIST_IGNORE_SUGGESTED_LEVEL
-- ("Show All Level Ranges", GlobalStrings/enUS.lua:13597), whose Title Case
-- stood out among this page's labels. The wording is the author's
-- (0.9.0-dev.9), kept within the ~28 characters a row label fits: one line,
-- no wrap, from x = 37 to 85 short of the row's centre
-- (Blizzard_SettingControls.lua:338-341). A spec holds it to that.
local SHOW_ALL_LEVEL_RANGES_LABEL = L.SETTINGS_SHOW_ALL_LEVELS_LABEL
local SHOW_ALL_LEVEL_RANGES_TOOLTIP = L.SETTINGS_SHOW_ALL_LEVELS_TOOLTIP

-- The section's second checkbox: each activity's suggested level range after
-- its name in the activity menu (LFGF.ActivityMenuText, core/filterpanel.lua).
-- Read when the menu is built, and the menu is rebuilt on every open, so a
-- change needs no announcement. The label is our own, in the author's wording
-- (0.9.0-dev.9), and kept under the ~28 characters a row label fits on one
-- line (Blizzard_SettingControls.lua:338-341).
local SHOW_ACTIVITY_LEVEL_RANGES_LABEL = L.SETTINGS_SHOW_LEVEL_RANGES_LABEL
local SHOW_ACTIVITY_LEVEL_RANGES_TOOLTIP = L.SETTINGS_SHOW_LEVEL_RANGES_TOOLTIP

-------------------------------------------------------
---------- Guild and friends (in the Search section)
-------------------------------------------------------
-- Two of Blizzard's own checkbox rows, the last two of Search. They had their
-- own "Guild and friends" header until 0.8.0-dev.3. Each governs its mark in
-- BOTH lists -- the icon and the moving up -- and, when off, every call to its
-- API; core/relations.lua reads them through LFGF.MarkGuildmates /
-- LFGF.MarkFriends (core/main.lua); the defaults are in core/db.lua.
--
-- A change shows on the NEXT search, and on a whisper row the next time it is
-- drawn -- the same rule the marks already follow, so nothing listens here.

-- The row reads "Mark guild members"; the variable and the saved key keep the
-- names they shipped with (core/db.lua), so a choice already saved is not lost
-- to a relabel.
local MARK_GUILDMATES_LABEL = L.SETTINGS_MARK_GUILDMATES_LABEL
local MARK_GUILDMATES_TOOLTIP = L.SETTINGS_MARK_GUILDMATES_TOOLTIP

-- Until 0.21.0-dev.7 this row read "Mark friends (Experimental)", the tag and a
-- tooltip warning in Blizzard's warning colour, because the friend system was
-- disabled in the Forever beta. Confirmed working in the client (2026-10-12),
-- it is a plain row like the guild one. .claude/rules/relation-icons.md
local MARK_FRIENDS_LABEL = L.SETTINGS_MARK_FRIENDS_LABEL
local MARK_FRIENDS_TOOLTIP = L.SETTINGS_MARK_FRIENDS_TOOLTIP

-------------------------------------------------------
---------- Sort players by (the last row of Search)
-------------------------------------------------------
-- Blizzard's own dropdown row (Settings.CreateDropdown, Blizzard_Settings.lua
-- :410), built the way BugSack builds its font-size dropdown on this client.
-- Each option's tooltip becomes a line of the row's own tooltip (:416-496).
-- It orders the Players box of the list (core/listpanel.lua), which sorts
-- again on the announcement below. .claude/rules/player-sort-order.md

--- The options, in LFGF.PLAYER_SORT_ORDERS' order. A FUNCTION, as Blizzard's
--- menu calls it every time it is built (CreateDropdownOptionInserter,
--- :524-526); each option is saved by its name (core/main.lua).
local function PlayerSortOptions()
	local words = {
		newest = { L.PLAYER_SORT_NEWEST, L.PLAYER_SORT_NEWEST_TOOLTIP },
		oldest = { L.PLAYER_SORT_OLDEST, L.PLAYER_SORT_OLDEST_TOOLTIP },
		levelHigh = { L.PLAYER_SORT_LEVEL_HIGH, L.PLAYER_SORT_LEVEL_HIGH_TOOLTIP },
		levelLow = { L.PLAYER_SORT_LEVEL_LOW, L.PLAYER_SORT_LEVEL_LOW_TOOLTIP },
		class = { L.PLAYER_SORT_CLASS, L.PLAYER_SORT_CLASS_TOOLTIP },
	}
	local container = Settings.CreateControlTextContainer()                 -- :261
	for _, order in ipairs(LFGF.PLAYER_SORT_ORDERS) do
		container:Add(order, words[order][1], words[order][2])
	end
	return container:GetData()
end

-------------------------------------------------------
---------- Miscellaneous
-------------------------------------------------------
-- The last section, six rows in the author's order: the key binding, Player
-- ratings, Show minimap button, the language packs sentence, Report a bug,
-- Reset window position. Headed with Blizzard's own string by
-- default (MISCELLANEOUS, GlobalStrings/enUS.lua:14324, through core/locale.lua),
-- so it is translated with the client unless a language pack replaces it.
-- Until 0.8.0-dev.3 the first two had headers of their own, Minimap and
-- Report a bug.

-- The key binding: "Open LFG Forever" and a Keybindings button that opens
-- Blizzard's own Keybindings page at the LFG Forever section
-- (LFGF.OpenKeybindings, core/main.lua), where Blizzard's code picks, unbinds
-- and saves the key. A button row like Blizzard's own link to its Ping
-- keybindings, which also stays out of the settings search
-- (PingSystem.lua:89-90): the search finds the key itself on Blizzard's page.
-- The button never uses the binding, so the row is there whatever the client
-- knows: with Bindings.xml missing, Blizzard's page has no section to scroll to.
--
-- NEVER BLIZZARD'S KEY ROW HERE (CreateKeybindingEntryInitializer). That
-- helper writes MatchesSearchTags and GetBindingText onto the row in its
-- caller's code (Blizzard_Keybindings.lua:537-563), so from here they are our
-- values, and the settings search calls MatchesSearchTags on every row
-- outside its protected calls (Blizzard_SettingsPanel.lua:628). A client
-- taint log proved it: one keystroke in the search box tainted Blizzard's
-- settings list, and Blizzard's Keybindings page then could not change any
-- key in combat (SetBinding() blocked). .claude/rules/keybinding.md, *Taint*.
local function KeybindingRow()
	return CreateSettingsButtonInitializer(L.BINDING_OPEN_WINDOW, L.KEYBINDINGS,
		LFGF.OpenKeybindings, L.SETTINGS_KEYBINDING_TOOLTIP, false)
end

-- Show minimap button: one of Blizzard's checkbox rows. core/minimap.lua builds
-- the button either way and only shows or hides it, so the change is immediate
-- rather than waiting for a reload.
local SHOW_MINIMAP_BUTTON_LABEL = L.SETTINGS_MINIMAP_BUTTON_LABEL
local SHOW_MINIMAP_BUTTON_TOOLTIP = L.SETTINGS_MINIMAP_BUTTON_TOOLTIP

-- The language packs: one gold sentence, right above Report a bug, saying the
-- other languages are separate addons on CurseForge and naming one by its
-- exact title. The title is a name, so not a key (like "Discord"): the
-- translated sentence takes it as its %s, quote marks and all, so no pack can
-- change it. The same text whether or not a pack is on, by the author's
-- decision. .claude/rules/language-packs-row.md
local LANGUAGE_PACK_EXAMPLE = "LFG Forever - Language Pack Korean"

-- OUR OWN TEXT ROW (core/settings.xml): Blizzard has no row whose text can be
-- set. Its mixin is a global, namespaced, for the XML to name, and holds Init
-- alone: Blizzard calls a row's Init only when it has one, inside its
-- protected call (ScrollUtil.lua:1695-1699; Blizzard_SettingsList.lua:57-62),
-- and a Release only when there is one (ScrollUtil.lua:1703-1707). Set on
-- every Init, because the list pools rows by template.
QuinteLFGSettingsTextRowMixin = {}

function QuinteLFGSettingsTextRowMixin:Init(initializer)
	self.Text:SetText(initializer.data.text)
end

-- Report a bug: one of Blizzard's own button rows -- "Found a bug or have an
-- idea?" beside a Discord button. The whole
-- sentence does not fit: a row's label runs from x = 37 to 85 short of the
-- row's centre and does not wrap (Blizzard_SettingControls.lua:340-341,
-- SettingsListElementTemplate wordwrap="false"), about 200px on this 920-wide
-- panel. The button carries the "tell us on" half.
--
-- The button opens the Report a bug popup, which the window header's Report a
-- bug opens too (core/window.lua), so the popup lives in core/main.lua
-- (LFGF.ShowReportBug). .claude/rules/report-bug-header.md
local REPORT_BUG_LABEL = L.SETTINGS_REPORT_BUG_LABEL
-- A name, so not a key: it reads "Discord" in every language.
local REPORT_BUG_BUTTON = "Discord"
local REPORT_BUG_TOOLTIP = L.SETTINGS_REPORT_BUG_TOOLTIP

--- The Discord button's click. LFGF.ShowReportBug is looked up when the button
--- is clicked, not when the page is built.
local function ShowReportBug()
	LFGF.ShowReportBug()
end

-- Reset window position and size: one of Blizzard's own button rows, the last
-- on the page. The label names the thing and the button, Blizzard's own RESET
-- (GlobalStrings/enUS.lua:18662), the action -- the Report a bug row's shape.
-- It resets AT ONCE, with no popup, by the author's decision: it is harmless,
-- and a drag undoes it. LFGF.ResetWindowPosition (core/window.lua) forgets the
-- saved position and size and, if the window exists, gives it the default
-- size and moves it to where it first opens (centred across, top level with
-- Blizzard's Group Finder); it is resolved at CALL time because window.lua
-- loads after this file. "Window position" until the window could be resized.
local RESET_WINDOW_LABEL = L.SETTINGS_RESET_WINDOW_LABEL
local RESET_WINDOW_TOOLTIP = L.SETTINGS_RESET_WINDOW_TOOLTIP

local function ResetWindowPosition()
	LFGF.ResetWindowPosition()
end

--- What Blizzard's Defaults button resets beyond the registered settings: the
--- window position, the saved Filters tab (LFGF.ForgetSavedFilters,
--- core/main.lua), every filter in My filters (LFGF.ForgetMyFilters) and which
--- Filters-tab sections are collapsed (LFGF.ForgetCollapsedFilterSections, which
--- expands an already-built panel's sections), all by the author's decisions -- on All Settings too, from whatever page it was
--- pressed. Forgetting the filters also puts an already-built filter panel's
--- boxes back and hides its My filters dropdown; the list is left to the next
--- Search. See .claude/rules/saved-filters.md and my-filters.md.
local function ResetOnDefaults()
	ResetWindowPosition()
	LFGF.ForgetSavedFilters()
	LFGF.ForgetMyFilters()
	LFGF.ForgetCollapsedFilterSections()
end

EventUtil.ContinueOnPlayerLogin(function()
	-- A first install has no saved table yet, and a character's first load no
	-- character table. LFGF.SavedTable (core/db.lua) creates each as a global,
	-- which is what makes the client save it on logout.
	LFGF.SavedTable("account")
	LFGF.SavedTable("character")

	-- The layout is kept for rows no Settings.Create* helper builds -- the
	-- headers and button rows below (Blizzard_ImplementationReadme.lua:13).
	local category, layout = Settings.RegisterVerticalLayoutCategory(LFGF.TITLE) -- :154

	local setting = RegisterSetting(category, "whisperLogSize", WHISPER_LOG_SIZE_LABEL)

	local options = Settings.CreateSliderOptions(                           -- :309
		WHISPER_LOG_SIZE_MIN, WHISPER_LOG_SIZE_MAX, WHISPER_LOG_SIZE_STEP)
	-- The number beside the slider, where Blizzard's own sliders show it
	-- (:302, MinimalSlider.lua:43).
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	Settings.CreateSlider(category, setting, options, WHISPER_LOG_SIZE_TOOLTIP) -- :404

	-- Tell the log the moment the slider moves, so lowering the size trims at
	-- once rather than on the next whisper. The callback is invoked as
	-- (owner, setting, value) -- CallbackRegistry.lua:118-119, :212-214, the
	-- shape SettingMixin:SetValueChangedCallback unpacks (Blizzard_Setting.lua
	-- :265-267).
	Settings.SetOnValueChangedCallback(SAVED.whisperLogSize.variable, function(_, _, value) -- :665
		EventRegistry:TriggerEvent(LFGF.EVENT_WHISPER_LOG_SIZE_CHANGED, value)
	end)

	-- Auto-whisper on Ask to Join: Blizzard's own checkbox row (:388), then the
	-- message row under it, indented and usable only while it is ticked. The
	-- row follows the checkbox through its own data (parentSetting), NOT
	-- Blizzard's SetParentInitializer, which would leave parentInitializer and
	-- the predicate on Blizzard's initializer as our values, read by the
	-- settings search outside its protected calls (Blizzard_SettingsPanel.lua
	-- :712). Both are add-on settings, so Blizzard's Defaults button resets
	-- them too.
	local autoWhisper = RegisterSetting(category, "askToJoinAutoWhisper", AUTO_WHISPER_LABEL)
	Settings.CreateCheckbox(category, autoWhisper, AUTO_WHISPER_TOOLTIP)

	-- THIS CHARACTER ALWAYS LEAVES THIS BLOCK WITH A MESSAGE, so
	-- LFGF.AskToJoinMessage (core/main.lua) reads QuinteLFGCharDB and nothing
	-- else, with no default of its own. A character with none yet (nil) gets
	-- the default; a message the character emptied is kept, because it is not
	-- nil. Nothing else is ever rewritten: until 0.20.0 an exact old default
	-- was swapped for the current one, removed once no saved file could still
	-- hold one (.claude/rules/addon-settings.md, item 4).
	--
	-- From 0.11.0 to 0.13.0 a character with none got a copy of the
	-- account-wide QuinteLFGDB.askToJoinMessage instead. The copy was removed
	-- in 0.14.0, by the author's decision, once players had a release to move
	-- over. From 0.14.0 to 0.21.0-dev.4 the leftover key was also cleared on
	-- every load; that clean-up was removed in 0.21.0-dev.5, by the author's
	-- decision, so a file last saved by 0.13.0 or older keeps the old text,
	-- unread. .claude/rules/per-character-ask-to-join-message.md
	if LFGF.SavedValue("askToJoinMessage") == nil then
		LFGF.SaveValue("askToJoinMessage", LFGF.ASK_TO_JOIN_DEFAULT_MESSAGE)
	end

	-- The built-in default is what Blizzard's Defaults button resets it to
	-- (Blizzard_Setting.lua:138-146).
	local message = RegisterSetting(category, "askToJoinMessage", MESSAGE_LABEL)
	local messageData = Settings.CreateSettingInitializerData(message, nil, MESSAGE_TOOLTIP)  -- :331
	messageData.placeholders = MESSAGE_PLACEHOLDERS   -- read by MessageRow:Init
	messageData.parentSetting = autoWhisper           -- read by MessageRow:Init / EvaluateState
	layout:AddInitializer(Settings.CreateSettingInitializer(MESSAGE_ROW_TEMPLATE, messageData))  -- :346

	-- Auto-whisper on Invite: the same pair, built the same way, from the same
	-- row template (whose mixin reads whichever setting its initializer holds).
	local inviteAutoWhisper = RegisterSetting(category, "inviteAutoWhisper",
		INVITE_AUTO_WHISPER_LABEL)
	Settings.CreateCheckbox(category, inviteAutoWhisper, INVITE_AUTO_WHISPER_TOOLTIP)

	-- An older default is cleared first, so the next line writes the current
	-- one. Exact matches only: a message the player changed is never touched.
	local savedInvite = LFGF.SavedValue("inviteMessage")
	for _, old in ipairs(INVITE_OLD_DEFAULT_MESSAGES) do
		if savedInvite == old then
			LFGF.SaveValue("inviteMessage", nil)
		end
	end

	-- Writes the default into this character's table when the key is nil --
	-- `== nil`, so an emptied message is kept (Blizzard_Setting.lua:398-402).
	local inviteMessage = RegisterSetting(category, "inviteMessage", INVITE_MESSAGE_LABEL)
	local inviteMessageData = Settings.CreateSettingInitializerData(inviteMessage, nil,
		INVITE_MESSAGE_TOOLTIP)
	inviteMessageData.placeholders = INVITE_MESSAGE_PLACEHOLDERS
	inviteMessageData.parentSetting = inviteAutoWhisper
	layout:AddInitializer(Settings.CreateSettingInitializer(MESSAGE_ROW_TEMPLATE, inviteMessageData))

	-- Search: a header, then two checkboxes, both labelled with our own text:
	-- Show all level activities (Blizzard's Group Finder has the same option) and
	-- Show suggested level ranges (which it has not).
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(SEARCH_HEADER))

	local showAllLevelRanges = RegisterSetting(category, "showAllLevelRanges",
		SHOW_ALL_LEVEL_RANGES_LABEL)
	Settings.CreateCheckbox(category, showAllLevelRanges, SHOW_ALL_LEVEL_RANGES_TOOLTIP)
	Settings.SetOnValueChangedCallback(SAVED.showAllLevelRanges.variable, function(_, _, value)
		EventRegistry:TriggerEvent(LFGF.EVENT_LEVEL_RANGES_CHANGED, value)
	end)

	local showActivityLevelRanges = RegisterSetting(category, "showActivityLevelRanges",
		SHOW_ACTIVITY_LEVEL_RANGES_LABEL)
	Settings.CreateCheckbox(category, showActivityLevelRanges, SHOW_ACTIVITY_LEVEL_RANGES_TOOLTIP)

	-- Guild and friends: the last two rows of Search, both Blizzard's own
	-- checkbox rows. Add-on settings, so Blizzard's Defaults button resets
	-- them too.
	local markGuildmates = RegisterSetting(category, "markGuildmates", MARK_GUILDMATES_LABEL)
	Settings.CreateCheckbox(category, markGuildmates, MARK_GUILDMATES_TOOLTIP)

	local markFriends = RegisterSetting(category, "markFriends", MARK_FRIENDS_LABEL)
	Settings.CreateCheckbox(category, markFriends, MARK_FRIENDS_TOOLTIP)

	-- Sort players by: after the two marks, which decide who is pinned above
	-- the chosen order. Its change is re-announced over EventRegistry, so the
	-- list sorts again without knowing the Settings API.
	local playerSortOrder = RegisterSetting(category, "playerSortOrder", L.SETTINGS_PLAYER_SORT_LABEL)
	Settings.CreateDropdown(category, playerSortOrder, PlayerSortOptions,     -- :410
		L.SETTINGS_PLAYER_SORT_PARTS_TOOLTIP)
	Settings.SetOnValueChangedCallback(SAVED.playerSortOrder.variable, function(_, _, value)
		EventRegistry:TriggerEvent(LFGF.EVENT_PLAYER_SORT_ORDER_CHANGED, value)
	end)

	-- Miscellaneous: the header, then the key binding, Player ratings, Show
	-- minimap button, the language packs sentence, Report a bug and Reset
	-- window position.
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.MISCELLANEOUS))

	layout:AddInitializer(KeybindingRow())

	-- Player ratings: one of Blizzard's checkbox rows, on by default. While it
	-- is on, the window has a third tab where recent allies are rated
	-- (core/playerratings.lua); its change is announced, the minimap button's
	-- way, so the tab comes and goes at once. The label is the tab's own title,
	-- and the tooltip one sentence on what the feature is for.
	-- .claude/rules/player-ratings.md
	if LFGF.RatingsAvailable then
		local showPlayerRatings = RegisterSetting(category, "showPlayerRatings", L.PLAYER_RATINGS)
		Settings.CreateCheckbox(category, showPlayerRatings, L.SETTINGS_PLAYER_RATINGS_TOOLTIP)
		Settings.SetOnValueChangedCallback(SAVED.showPlayerRatings.variable, function(_, _, value)
			EventRegistry:TriggerEvent(LFGF.EVENT_PLAYER_RATINGS_CHANGED, value)
		end)
	end

	-- Show minimap button. Its change is re-announced over EventRegistry, the
	-- whisper log size's pattern above, so core/minimap.lua shows or hides the
	-- button without knowing the Settings API.

	local showMinimapButton = RegisterSetting(category, "showMinimapButton",
		SHOW_MINIMAP_BUTTON_LABEL)
	Settings.CreateCheckbox(category, showMinimapButton, SHOW_MINIMAP_BUTTON_TOOLTIP)
	Settings.SetOnValueChangedCallback(SAVED.showMinimapButton.variable, function(_, _, value)
		EventRegistry:TriggerEvent(LFGF.EVENT_MINIMAP_BUTTON_CHANGED, value)
	end)

	-- The language packs sentence: an element row (Blizzard_Settings.lua:342),
	-- whose data table is ours. Nothing of ours is written onto Blizzard's
	-- initializer, and it carries no search tags, so the Options search does
	-- not find it.
	layout:AddInitializer(Settings.CreateElementInitializer("QuinteLFGSettingsTextRowTemplate",
		{ text = L.SETTINGS_LANGUAGE_PACKS_FORMAT:format(LANGUAGE_PACK_EXAMPLE) }))

	-- Report a bug, then Reset window position: Blizzard's own button rows
	-- (Blizzard_SettingControls.lua:1014), added the way BugSack adds its Wipe
	-- button on this client. The fifth argument must not be nil (:1019).
	-- FALSE, so the settings search does not find these rows: true would have
	-- Blizzard's function add search tags from our call (:1020-1023), our
	-- values, which the search reads outside its protected calls
	-- (Blizzard_SettingsPanel.lua:627-628). .claude/rules/settings-list-taint.md
	-- The section header is Blizzard's element too (:112), added the way
	-- Blizzard adds its own (Mainline/AudioOverrides.lua:5).
	layout:AddInitializer(CreateSettingsButtonInitializer(REPORT_BUG_LABEL,
		REPORT_BUG_BUTTON, ShowReportBug, REPORT_BUG_TOOLTIP, false))
	layout:AddInitializer(CreateSettingsButtonInitializer(RESET_WINDOW_LABEL,
		L.RESET, ResetWindowPosition, RESET_WINDOW_TOOLTIP, false))

	-- BLIZZARD'S DEFAULTS BUTTON RESETS THE WINDOW POSITION AND FORGETS THE
	-- SAVED FILTERS AND MY FILTERS TOO, by the author's decisions
	-- (ResetOnDefaults above). None is a registered setting, so Defaults does
	-- not touch them on its own. Its popup offers All Settings or These Settings
	-- (Blizzard_Dialogs.lua:2-17); each resets the registered settings and then
	-- announces it over EventRegistry -- Settings.Defaulted
	-- (Blizzard_SettingsPanel.lua:496) and Settings.CategoryDefaulted with the
	-- defaulted category (:550). Blizzard's own state that is not a setting row
	-- listens to exactly these two, comparing category IDs
	-- (Mainline/ColorblindOverrides.lua:82-89). EventRegistry runs each callback
	-- through securecallfunction (CallbackRegistry.lua:198-205), so nothing here
	-- runs inside Blizzard's defaults loop.
	--
	-- Owned by the category: one callback per owner per event
	-- (CallbackRegistry.lua:112-130), so the pair belongs to this page.
	EventRegistry:RegisterCallback("Settings.Defaulted", ResetOnDefaults, category)
	EventRegistry:RegisterCallback("Settings.CategoryDefaulted", function(_, defaulted)
		if defaulted and defaulted:GetID() == category:GetID() then
			ResetOnDefaults()
		end
	end, category)

	Settings.RegisterAddOnCategory(category)                                -- :134

	-- Published for LFGF.OpenSettings (core/main.lua), which the minimap
	-- button's and the compartment entry's right click call.
	LFGF.settingsCategory = category
end)

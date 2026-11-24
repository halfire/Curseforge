-- QuinteLFG -- core/playerratings.lua
--
-- The Player ratings tab's content: Blizzard's Recent Allies, one row each in
-- the players list's own shape (the listing row, core/playerrow.lua), most
-- recent first, with one to three stars to rate each ally, the whisper log's
-- right-click menu, and the Clear player rating popup, which clears one
-- player's rating by name. Phases 1 and 2 of four: the list and the rating. The
-- players list and the whisper log mark rated players (Phase 3) through the
-- shared marks in core/main.lua.
-- On top, the players from LFG Forever's own list of the last five party
-- members (core/recentparty.lua) that Blizzard's first ten rows do not have
-- yet: Blizzard's list can take a while to catch up.
-- The tab is shown only while the "Player ratings" setting is on;
-- core/filterpanel.lua owns the tab. .claude/rules/player-ratings.md
--
-- BLIZZARD'S FLOW, LESS THE REQUEST. Blizzard's Recent Allies list registers
-- RECENT_ALLIES_CACHE_UPDATE on show, calls TryRequestRecentAlliesData,
-- refreshes, unregisters on hide, and refreshes on the event
-- (Blizzard_RecentAlliesTemplates.lua:44-76). The request is FORBIDDEN to addon
-- code: the Forever client raised ADDON_ACTION_FORBIDDEN for it from /run, out
-- of combat. So this file never makes it. It reads what the client holds, which
-- the same probe found ready right after /reload, on every show, and redraws
-- when Blizzard's own Recent Allies tab refreshes the cache.
--
-- Same factory contract as the other panels: create, then return UNANCHORED,
-- unsized, and here HIDDEN, so nothing is read before the tab is first shown.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
local StaticPopupDialogs, StaticPopup_Show = LFGF.Dialogs, LFGF.ShowDialog
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

local Row = LFGF.PlayerRow

-- Registered only while the list is shown, as Blizzard's list does with the
-- first (Templates.lua:3-5, :44-57). The second is the one Blizzard's camelot
-- Friends frame shows its Recent Allies tab by (Camelot/FriendsFrame.lua:607),
-- so the "not available" notice follows the system too. The third says one
-- ally's data changed (RecentAlliesDocumentation.lua:234-241); the sources do
-- not say whether setting a note (the menu's Set Note) fires it or the first,
-- so the list follows both and its tooltip shows the new note either way.
local EVENTS = { "RECENT_ALLIES_CACHE_UPDATE", "RECENT_ALLIES_SYSTEM_STATUS_UPDATED",
	"RECENT_ALLY_DATA_UPDATED" }

-- "2 hours ago": Blizzard's own rule (RecentAlliesUtil.GetFormattedTime,
-- Blizzard_RecentAlliesUtil.lua:44-59) -- under an hour approximated, hours
-- under a day, days after -- on a formatter of OUR OWN. Blizzard's function
-- writes the min interval onto a formatter Blizzard shares with its own Friends
-- tooltip (SetMinInterval, TimeUtil.lua:182-184), so calling it from here would
-- leave a value of ours on Blizzard's object.
local timeFormatter = CreateFromMixins(SecondsFormatterMixin)
timeFormatter:Init(SECONDS_PER_HOUR, SecondsFormatter.Abbreviation.None)

local function FormattedTime(seconds)
	timeFormatter:SetMinInterval(seconds < SECONDS_PER_DAY and SecondsFormatter.Interval.Hours
		or SecondsFormatter.Interval.Days)
	return timeFormatter:Format(seconds)
end

--- The ally's name the way Blizzard's list shows it: fullName while regional
--- unique names are on ("Water Boi" on Forever), the first name otherwise.
---
--- BLIZZARD'S RULE (RecentAlliesUtil.GetBestDisplayNameForCharacter,
--- Blizzard_RecentAlliesUtil.lua:40-42), written as a branch on the flag.
--- Theirs is `flag and fullName or name`, a truth test on the name itself, and
--- the sources do not say whether that errors on a hidden string. fullName is
--- never nil (RecentAlliesDocumentation.lua:267), so the two agree.
local function DisplayName(characterData)
	if RegionalUniqueNamesEnabled() then
		return characterData.fullName
	end
	return characterData.name
end

--- The second line: "<place> | <activity> | <how long ago>", as a solo
--- player's row in the players list reads "<activity> | <zone>", by the
--- author's decision ("Blackfang Deeps | Fought Together | 20 Hours ago").
---
--- THE PLACE IS WHERE IT HAPPENED, the interaction's own locationName
--- (RecentAlliesDocumentation.lua:302), not where the ally is now. The words are
--- Blizzard's as they come, the server's activity and Blizzard's own time
--- (RECENT_ALLY_INTERACTION_TIME_FORMAT around D_HOURS / D_DAYS), in their own
--- casing, so every language reads as its client does.
---
--- A PART THAT IS MISSING OR CANNOT BE READ IS LEFT OUT, with its separator:
--- the line is joined from readable strings, which joining needs.
local function ActivityLine(interaction)
	if interaction == nil then
		return ""
	end
	local parts = {}
	local place = LFGF.Readable(interaction.contextData.locationName, nil)
	if place ~= nil and place ~= "" then
		table.insert(parts, place)
	end
	local action = LFGF.Readable(interaction.description, nil)
	if action ~= nil and action ~= "" then
		table.insert(parts, action)
	end
	local time = LFGF.Readable(interaction.timestamp, nil)
	if time ~= nil then
		table.insert(parts, L.RECENT_ALLY_TIME_FORMAT:format(FormattedTime(GetServerTime() - time)))
	end
	return table.concat(parts, " " .. LFGF.SEPARATOR .. " ")
end

--- One list entry: what the row shows, plus what the order and the tooltip
--- need.
---
--- THE NEWEST INTERACTION IS interactions[1], as Blizzard's list assumes
--- (Templates.lua:227-231). It makes the second line, and its time, read
--- through LFGF.Readable, the order.
---
--- THE CLASS: C_CreatureInfo.GetClassInfo(classID).classFile, which every
--- class table here is keyed by. GetClassInfo is AllowedWhenUntainted
--- (CreatureInfoDocumentation.lua:13), so a hidden classID is never handed to
--- it; the row then has no class colour or icon.
local function Entry(ally, position)
	local character = ally.characterData
	local interaction = ally.interactionData.interactions[1]

	local classID = LFGF.Readable(character.classID, nil)
	local classInfo = classID ~= nil and C_CreatureInfo.GetClassInfo(classID) or nil

	local time = nil
	if interaction ~= nil then
		time = LFGF.Readable(interaction.timestamp, nil)
	end

	return {
		name = DisplayName(character),
		-- The rating's key is the fullName, "Firstname Surname", whatever the row
		-- shows: the name the player listings carry too. Nil when it cannot be
		-- read, and the row then offers no stars.
		key = LFGF.PlayerKey(character.fullName),
		-- The name the menu opens for, whatever the row shows.
		fullName = character.fullName,
		guid = character.guid,
		classFilename = classInfo and classInfo.classFile or nil,
		level = character.level,
		text = ActivityLine(interaction),
		-- For the tooltip, which reads Blizzard's own fields at hover time.
		ally = ally,
		interaction = interaction,
		time = time,
		position = position,
	}
end

--- MOST RECENT FIRST, by the newest interaction's time. An ally with no
--- interaction, or a time that cannot be read, goes last. Ties keep Blizzard's
--- order (its position in GetRecentAllies), which also keeps table.sort, which
--- is not stable, from reordering them.
local function MostRecentFirst(a, b)
	if (a.time == nil) ~= (b.time == nil) then
		return a.time ~= nil
	end
	if a.time ~= nil and a.time ~= b.time then
		return a.time > b.time
	end
	return a.position < b.position
end

-------------------------------------------------------
---------- The last party members, on top
-------------------------------------------------------
-- THE AUTHOR'S RULE (2026-11-13): Blizzard's first TEN rows, most recent
-- first, are checked; each player of the list of the last five party members
-- they do not have goes on top, the list's newest first. One Blizzard has
-- below its tenth row shows twice, as asked. Matched by LFGF.PlayerKey, the
-- ratings' own key, so a row's stars and its twin's agree.
local CHECKED_ALLY_ROWS = 10

--- The name the row shows, by Blizzard's own rule for its rows
--- (DisplayName, below): the whole name while regional unique names are on,
--- the first name otherwise.
local function PartyDisplayName(fullName)
	if RegionalUniqueNamesEnabled() then
		return fullName
	end
	return string.match(fullName, "^(%S+)") or fullName
end

--- One entry for a listed player, in the shape the row and the tooltip read.
--- The second line and the tooltip's activity come from a stand-in for
--- Blizzard's own "party member" activity (Enum.RolodexType.PartyMember, whose
--- context string is the description and its place, Blizzard_RecentAlliesUtil.lua,
--- GenerateBasicContextString), so they read "Westfall | Grouped Together |
--- 2 Hours ago" and "Grouped Together - Westfall" through Blizzard's own rules.
local function PartyEntry(member, key)
	local interaction = {
		type = Enum.RolodexType.PartyMember,
		description = L.PARTY_MEMBER_ACTIVITY,
		timestamp = member.time,
		contextData = { locationName = member.zone },
	}
	return {
		party = true,
		name = PartyDisplayName(member.name),
		fullName = member.name,
		key = key,
		guid = member.guid,
		classFilename = member.class,
		level = member.level,
		text = ActivityLine(interaction),
		interaction = interaction,
	}
end

--- The listed players Blizzard's first ten rows (already sorted) miss, newest
--- first.
local function PartyEntries(allies)
	local listed = {}
	for index = 1, math.min(CHECKED_ALLY_ROWS, #allies) do
		local key = allies[index].key
		if key ~= nil then
			listed[key] = true
		end
	end
	local entries = {}
	for _, member in ipairs(LFGF.RecentPartyMembers()) do
		local key = LFGF.PlayerKey(member.name)
		if key ~= nil and not listed[key] then
			table.insert(entries, PartyEntry(member, key))
		end
	end
	return entries
end

--- Blizzard's own note on the ally, if any and readable, ready to show. It is
--- text the player typed, so every | is doubled: shown as itself, never as the
--- start of an escape (|c, |T, |H).
local function Note(note)
	note = LFGF.Readable(note, nil)
	if note == nil or note == "" then
		return nil
	end
	return L.RECENT_ALLY_NOTE_FORMAT:format((string.gsub(note, "|", "||")))
end

--- The newest activity and how long ago, for the tooltip's last two lines
--- (Templates.lua:197-209): "X ago", then the activity with its place, from
--- RecentAlliesUtil.GenerateContextStringForInteraction (Blizzard_RecentAlliesUtil.lua
--- :156-163, which only reads and formats). Nil when there is no interaction,
--- or when anything it formats cannot be read.
---
--- AN ACTIVITY WITH AN ITEM shows its description alone. Blizzard's tooltip
--- adds the item's name, loading the item first and showing the tooltip again
--- when it arrives (:275-285); the description says what happened without it.
local function Activity(interaction)
	if interaction == nil or interaction.timestamp == nil then
		return nil
	end
	local context = interaction.contextData
	if not canaccessallvalues(interaction.type, interaction.description, interaction.timestamp,
		context.itemID, context.locationName, context.activityDifficultyID,
		context.activityDifficultyLevel) then
		return nil
	end

	local text
	if context.itemID ~= nil then
		text = interaction.description
	else
		text = RecentAlliesUtil.GenerateContextStringForInteraction(interaction)
	end
	return L.RECENT_ALLY_TIME_FORMAT:format(FormattedTime(GetServerTime() - interaction.timestamp)), text
end

--- The tooltip's last block (Templates.lua:197-209): a blank line, "Recent
--- Activities" with how long ago in Blizzard's two colours (:206), then the
--- activity with its place. Answers whether it was added.
local function AddActivity(interaction)
	local when, activity = Activity(interaction)
	if when == nil then
		return false
	end
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip:AddDoubleLine(L.RECENT_ACTIVITIES, when,
		NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
		DISABLED_FONT_COLOR.r, DISABLED_FONT_COLOR.g, DISABLED_FONT_COLOR.b)
	GameTooltip_AddHighlightLine(GameTooltip, activity)
	return true
end

-- The thin divider between the level and the race (Templates.lua:165).
local LEVEL_RACE_DIVIDER = CreateAtlasMarkup("charactercreate-customize-dropdown-linemouseover-middle", 1, 10)

--- The tooltip of a player from the list of the last party members, the
--- author's choice: Blizzard's shape with what the list holds. The full name
--- (gold), "Level 30" and the class (white), then the activity block, "Grouped
--- Together - Westfall". A line with no value is left out. Every value is the
--- addon's own, checked when it was saved (core/recentparty.lua).
local function ShowPartyTooltip(row, entry)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip_AddNormalLine(GameTooltip, entry.fullName)
	if entry.level ~= nil then
		GameTooltip_AddHighlightLine(GameTooltip, L.PARTY_MEMBER_LEVEL_FORMAT:format(entry.level))
	end
	local className = entry.classFilename ~= nil and L["CLASS_" .. entry.classFilename] or nil
	if className ~= nil then
		GameTooltip_AddHighlightLine(GameTooltip, className)
	end
	AddActivity(entry.interaction)
	GameTooltip:Show()
end

--- The row's tooltip: BLIZZARD'S WHOLE RECENT ALLIES TOOLTIP, by the author's
--- decision, line for line as RecentAlliesEntryMixin:BuildRecentAllyTooltip
--- builds it (Templates.lua:153-225):
---   the name (gold), level and race, class, faction, where they are now
---   (white), Blizzard's note (gold), then a blank line, "Recent Activities"
---   with how long ago, and the activity with its place.
---
--- EVERY VALUE IS READ BEFORE IT IS SHOWN, and a line whose value is missing or
--- cannot be read is left out: a tooltip's AddLine is not documented, so
--- nothing says it takes a hidden value. Blizzard adds the class and faction
--- lines empty when it has none; here they are left out. The name is fullName,
--- as Blizzard's tooltip has it (:159-161), whatever the row shows. The class
--- line is the class name alone: Blizzard's RECENT_ALLY_TOOLTIP_CLASS_FORMAT is
--- "%s" in every client language here (GlobalStrings/*.lua). A player from the
--- list of the last party members gets ShowPartyTooltip's instead.
local function ShowTooltip(row)
	local entry = row.entry
	if not entry then
		return
	end
	if entry.party then
		ShowPartyTooltip(row, entry)
		return
	end
	local ally = entry.ally
	local character = ally.characterData

	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local added = 0
	local function Add(add, text)
		add(GameTooltip, text)
		added = added + 1
	end

	local name = LFGF.Readable(character.fullName, nil)
	if name ~= nil then
		Add(GameTooltip_AddNormalLine, name)
	end

	local raceID = LFGF.Readable(character.raceID, nil)
	local raceInfo = raceID ~= nil and C_CreatureInfo.GetRaceInfo(raceID) or nil
	local level = LFGF.Readable(character.level, nil)
	if level ~= nil then
		Add(GameTooltip_AddHighlightLine, L.RECENT_ALLY_LEVEL_RACE_FORMAT:format(level,
			LEVEL_RACE_DIVIDER, raceInfo and raceInfo.raceName or ""))
	end

	local classID = LFGF.Readable(character.classID, nil)
	local classInfo = classID ~= nil and C_CreatureInfo.GetClassInfo(classID) or nil
	if classInfo then
		Add(GameTooltip_AddHighlightLine, classInfo.className)
	end

	local factionInfo = raceID ~= nil and C_CreatureInfo.GetFactionInfo(raceID) or nil
	if factionInfo then
		Add(GameTooltip_AddHighlightLine, factionInfo.name)
	end

	local location = LFGF.Readable(ally.stateData.currentLocation, nil)
	if location ~= nil and location ~= "" then
		Add(GameTooltip_AddHighlightLine, location)
	end

	local note = Note(ally.interactionData.note)
	if note ~= nil then
		Add(GameTooltip_AddNormalLine, note)
	end

	if AddActivity(entry.interaction) then
		added = added + 1
	end

	if added == 0 then
		GameTooltip:Hide()
		return
	end
	GameTooltip:Show()
end

-------------------------------------------------------
---------- The rating stars
-------------------------------------------------------
-- BLIZZARD'S FAVOURITE STARS, by the author's decision: the empty star
-- (auctionhouse-icon-favorite-off) at full opacity with the gold star
-- (auctionhouse-icon-favorite) over it, shown `index <= rating`. Blizzard's
-- own on/off pair for a favourite (its stable, Blizzard_StableUI.lua:439-440,
-- shows the -off art at full opacity, Blizzard_StableUI.xml:335). The art is
-- 40 x 36 (AtlasInfo.lua), drawn at exactly half, so it shrinks instead of
-- stretching: the recipe stars it replaced were 20 x 19 art drawn at their own
-- size, and looked pixelated at any UI scale above 1. The rules file has the
-- history (.claude/rules/player-ratings.md).
--
-- The author's layout: 20 x 18, 4 apart, centred at the row's right end, the
-- second line ending 8 before them.
-- Hovering star N lights stars 1 to N in gold, a preview of the rating; the
-- saved rating shows again when the mouse leaves. The stars only change a
-- rating; Clear player rating clears one, by name (below).
local STAR_WIDTH, STAR_HEIGHT = 20, 18
local STAR_GAP = 4
local STAR_COUNT = 3
local STARS_WIDTH = STAR_COUNT * STAR_WIDTH + (STAR_COUNT - 1) * STAR_GAP
-- The second line's own inset from the row's right edge (core/playerrow.lua).
local STARS_INSET_RIGHT = 8
local STARS_TO_TEXT_GAP = 8
local STAR_ATLAS, EMPTY_STAR_ATLAS = "auctionhouse-icon-favorite", "auctionhouse-icon-favorite-off"

local function LightStars(stars, count)
	for index, star in ipairs(stars.Buttons) do
		star.Earned:SetShown(index <= (count or 0))
	end
end

--- The stars' tooltip, the author's choice (option A of six calmer drafts, in
--- place of a busier one with stars and colour codes in it): their sentence on
--- how the player listings mark rated players, a blank line, then one gold
--- line per rating, written out. The sentence is the tooltip's FIRST line, so
--- Blizzard draws it white and in its larger header font (textLeft1Font,
--- GameTooltipHeaderText, SharedTooltipTemplates.xml:12), and
--- GameTooltip_SetTitle wraps it. The same on every star, and read from the
--- language strings on every hover.
local function ShowStarsTooltip(stars)
	GameTooltip:SetOwner(stars, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, L.PLAYER_RATING_MARKED)
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip_AddNormalLine(GameTooltip, L.PLAYER_RATING_ONE_STAR_LINE)
	GameTooltip_AddNormalLine(GameTooltip, L.PLAYER_RATING_TWO_STARS_LINE)
	GameTooltip_AddNormalLine(GameTooltip, L.PLAYER_RATING_THREE_STARS_LINE)
	GameTooltip:Show()
end

local function StarOnEnter(star)
	local stars = star:GetParent()
	LightStars(stars, star.index)
	ShowStarsTooltip(stars)
end

local function StarOnLeave(star)
	LightStars(star:GetParent(), star:GetParent().rating)
	GameTooltip_Hide()
end

--- SET NOTE, the author's decision (2026-11-13): Blizzard's own Recent Allies
--- note window, the one its Friends > Recent Allies menu opens
-- La note est enregistrée par WoW depuis un formulaire dans l’onglet.
local ALLY_NOTE = "QUINTELFG_ALLY_NOTE"
StaticPopupDialogs[ALLY_NOTE] = {
	ratingsOnly = true,
	text = "Note sur le joueur",
	subText = " ",
	button1 = L.OKAY,
	button2 = L.CANCEL,
	maxLetters = 127,
	OnShow = function(dialog, data)
		dialog.title:SetText("Note sur « " .. Q.Safe(data.name) .. " »")
		dialog.SubText:SetText(" ")
		dialog:GetEditBox():SetMaxLetters(math.max(127, #data.note))
		dialog:GetEditBox():SetText(data.note)
		dialog:GetEditBox():SetFocus()
	end,
	OnAccept = function(dialog, data)
		local ok, allowed = Q.Call(C_RecentAllies.CanSetRecentAllyNote, data.guid)
		if ok and LFGF.Readable(allowed, false) and Q.Call(C_RecentAllies.SetRecentAllyNote, data.guid, dialog:GetEditBox():GetText()) then
			return false
		end
		dialog.SubText:SetText("WoW a refusé d’enregistrer la note.")
		return true
	end,
}

local function SetNoteEntry(guid)
	if not LFGF.ShowPlayerRatings() or not C_RecentAllies.SetRecentAllyNote or guid == nil then return nil end
	local ok, allowed = Q.Call(C_RecentAllies.CanSetRecentAllyNote, guid)
	if not ok or LFGF.Readable(allowed, false) ~= true then
		return nil
	end
	return function(rootDescription)
		rootDescription:CreateButton(RECENT_ALLIES_MENU_BUTTON_LABEL_SET_NOTE, function()
			local ally = LFGF.Readable(C_RecentAllies.GetRecentAllyByGUID(guid), nil)
			local character = ally and LFGF.Readable(ally.characterData, nil)
			local info = ally and LFGF.Readable(ally.interactionData, nil)
			local name = character and LFGF.Readable(DisplayName(character), nil)
			if not name then return end
			local note = info and LFGF.Readable(info.note, nil)
			StaticPopup_Show(ALLY_NOTE, nil, nil, { guid = guid, name = name, note = note or "" })
		end)
	end
end

--- Blizzard's player menu on a row, for the ally it shows: the menu the
--- whisper log opens (Row.OpenMenu, core/playerrow.lua), named and keyed the
--- way Blizzard's own Recent Allies list opens one -- fullName and guid
--- (Blizzard_RecentAlliesTemplates.lua:345-358). The same FRIEND menu for an
--- offline ally, by the author's decision: Whisper and Invite then get the
--- server's own "not online" answer. No chat type or chat line: a recent ally
--- is no whisper, so the menu reports the player by the GUID
--- (UnitPopupReportFriendButtonMixin:CanShow, UnitPopupSharedButtonMixins.lua
--- :1450-1461).
local function ShowRowMenu(row)
	local entry = row.entry
	if not entry then
		return
	end
	local guid = LFGF.Readable(entry.guid, nil)
	Row.OpenMenu(row, entry.fullName, { guid = guid }, SetNoteEntry(guid))
end

local function RowOnClick(row)
	LFGF.PlayClick()
	ShowRowMenu(row)
end

--- A left click saves that many stars for the ally. A right click opens the
--- row's menu, as anywhere else on the row, and rates nothing.
local function StarOnClick(star, button)
	local stars = star:GetParent()
	if button == "RightButton" then
		RowOnClick(stars:GetParent())
		return
	end
	if LFGF.SetPlayerRating(stars.key, star.index, stars.guid) then
		stars.rating = star.index
		LFGF.PlayClick()
	end
	LightStars(stars, star.index)
end

--- Build a row's three stars, once per pooled frame. Each star's hit rect
--- reaches half the gap to its neighbour, so a hover never drops between two.
local function BuildStars(row)
	local stars = CreateFrame("Frame", nil, row)
	stars:SetSize(STARS_WIDTH, STAR_HEIGHT)
	stars:SetPoint("RIGHT", row, "RIGHT", -STARS_INSET_RIGHT, 0)
	stars.Buttons = {}

	local previous
	for index = 1, STAR_COUNT do
		local star = CreateFrame("Button", nil, stars)
		star:SetSize(STAR_WIDTH, STAR_HEIGHT)
		if previous then
			star:SetPoint("LEFT", previous, "RIGHT", STAR_GAP, 0)
		else
			star:SetPoint("LEFT", stars, "LEFT", 0, 0)
		end
		star:SetHitRectInsets(-STAR_GAP / 2, -STAR_GAP / 2, 0, 0)

		local unearned = star:CreateTexture(nil, "BACKGROUND")
		unearned:SetAtlas(EMPTY_STAR_ATLAS)
		unearned:SetAllPoints()
		star.Unearned = unearned

		local earned = star:CreateTexture(nil, "OVERLAY")
		earned:SetAtlas(STAR_ATLAS)
		earned:SetAllPoints()
		earned:Hide()
		star.Earned = earned

		star.index = index
		-- Both buttons: a Button reports only LeftButtonUp until told otherwise.
		-- Without the right one, a right-click on the stars would be a dead
		-- spot in the row's menu.
		star:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		star:SetScript("OnEnter", StarOnEnter)
		star:SetScript("OnLeave", StarOnLeave)
		star:SetScript("OnClick", StarOnClick)
		stars.Buttons[index] = star
		previous = star
	end
	row.Stars = stars
end

--- Write a row's stars for its ally, on every fill: rows are pooled, so a
--- frame that showed one ally's rating shows the next one's.
local function FillStars(stars, entry)
	stars.key = entry.key
	stars.guid = entry.guid
	stars.rating = LFGF.PlayerRating(entry.key)
	stars:SetShown(entry.key ~= nil)
	LightStars(stars, stars.rating)
end

--- Fill a row: the listing row and its stars, built once per pooled frame,
--- and the entry stamped on it for the tooltip, which reads it at hover time.
---
--- THE ROW TAKES A RIGHT CLICK ONLY, which opens the menu: RegisterForClicks
--- turns the right button on and leaves the left one off, so the handler needs
--- no check of which button it was (the whisper log's row does the same). The
--- stars take both buttons themselves.
local function FillRow(row, entry)
	if not row.Name then
		Row.BuildListing(row, STARS_WIDTH + STARS_TO_TEXT_GAP)
		BuildStars(row)
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:RegisterForClicks("RightButtonUp")
		row:SetScript("OnClick", RowOnClick)
	end
	row.entry = entry
	Row.FillListing(row, entry)
	FillStars(row.Stars, entry)
end

-------------------------------------------------------
---------- Clear player rating
-------------------------------------------------------
-- THE AUTHOR'S DECISIONS (2026-11-14), .claude/rules/player-ratings.md: a link
-- at the right end of the Recent allies title line (core/filterpanel.lua),
-- always on, opens this popup, built like Save new filter's: a label, a box
-- for the player's name, Okay and Cancel.
--   * Okay is on only for a name with a saved rating, off with its reason on
--     hover otherwise;
--   * the name is matched exactly, case and all, through LFGF.PlayerKey, so
--     extra spaces and the "Firstname-Surname" form are forgiven;
--   * Okay clears that one rating and says so in chat.

LFGF.CLEAR_PLAYER_RATING_POPUP = "QUINTELFG_CLEAR_PLAYER_RATING"

-- Blizzard's own limit for typing a player's name, its Ignore popup's:
-- `maxLetters = 12 + 1 + 64, --name space realm (77 max)`
-- (Blizzard_StaticPopup_Game/GameDialogDefs.lua, ADD_IGNORE).
local PLAYER_NAME_MAX_LETTERS = 12 + 1 + 64

--- Why Okay is off for what the box holds, or nil when the name has a rating
--- to clear. The name is shown with every | doubled (LFGF.ShownName).
local function ClearRatingReason(text)
	local key = LFGF.PlayerKey(text)
	if key == nil then
		return L.CLEAR_PLAYER_RATING_EMPTY
	end
	if LFGF.PlayerRating(key) == nil then
		return L.CLEAR_PLAYER_RATING_UNKNOWN_FORMAT:format(LFGF.ShownName(key))
	end
	return nil
end

local function UpdateClearRatingOkay(dialog)
	dialog:GetButton1():SetEnabled(ClearRatingReason(dialog:GetEditBox():GetText()) == nil)
end

--- Clear the rating of the name typed. Checked again here: the rating may have
--- gone since the box was last typed in. Returns true to keep the dialog open
--- (StaticPopup_OnClick hides it otherwise, StaticPopup.lua:728-752), so a
--- name with nothing left to clear stays on screen with Okay off.
local function ClearRatingFromPopup(dialog)
	local key = LFGF.PlayerKey(dialog:GetEditBox():GetText())
	if not LFGF.ClearPlayerRating(key) then
		UpdateClearRatingOkay(dialog)
		return true
	end
	LFGF.Print(L.PLAYER_RATING_CLEARED_FORMAT:format(LFGF.ShownName(key)))
	return false
end

-- Defined once, at file scope: StaticPopupDialogs is a shared registry. The
-- same shape as Save new filter's (core/filterpanel.lua), maxLetters included:
-- the edit box belongs to the reused frame and keeps the last dialog's limit
-- unless this one sets its own (GameDialog.lua:248-251). Enter clears only a
-- name Okay would take, as Blizzard's own name-entry popup does
-- (GENERIC_INPUT_BOX, GameDialogDefs.lua:226-233).
StaticPopupDialogs[LFGF.CLEAR_PLAYER_RATING_POPUP] = {
	ratingsOnly = true,
	text = L.CLEAR_PLAYER_RATING_PROMPT,
	button1 = L.OKAY,
	button2 = L.CANCEL,
	hasEditBox = 1,
	maxLetters = PLAYER_NAME_MAX_LETTERS,
	OnShow = function(dialog)
		LFGF.HookPopupOkayTooltip(dialog, L.CLEAR_PLAYER_RATING, ClearRatingReason)
		dialog:GetEditBox():SetText("")
		dialog:GetEditBox():SetFocus()
		UpdateClearRatingOkay(dialog)
	end,
	OnHide = LFGF.RestorePopupOkay,
	OnAccept = ClearRatingFromPopup,
	EditBoxOnTextChanged = function(editBox)
		UpdateClearRatingOkay(editBox:GetParent())
	end,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		if not ClearRatingFromPopup(dialog) then
			dialog:Hide()
		end
	end,
	EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
	hideOnEscape = 1,
	timeout = 0,
	whileDead = 1,
}

--- Open the Clear player rating popup. Opened again while it shows, Blizzard
--- reuses that dialog (StaticPopup_Show -> StaticPopup_FindVisible). Works in
--- combat: StaticPopup_Show has no combat check.
function LFGF.ShowClearPlayerRating()
	StaticPopup_Show(LFGF.CLEAR_PLAYER_RATING_POPUP)
end

--- Build the Player ratings tab's content. Returned unanchored, unsized and
--- hidden.
function LFGF.CreatePlayerRatings(parent)
	local ratings = CreateFrame("Frame", nil, parent)
	ratings:Hide()

	-- The menu's one fix (Copy Character Name greyed out), registered once per
	-- session by whichever list is built first.
	Row.RegisterMenuModifier()

	local scrollBox, scrollBar, empty = LFGF.CreateScrollList(ratings)
	ratings.ScrollBox = scrollBox
	ratings.ScrollBar = scrollBar
	ratings.EmptyText = empty

	-- A LINEAR view of rows as tall as the players list's (LISTING_HEIGHT), with
	-- no padding or spacing, as that list's (Browse.lua:66-68): the band each
	-- row draws is the gap. The VIEW sets the height, before the initializer
	-- runs (ScrollBoxListView.lua:383).
	local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 0)
	view:SetElementExtent(Row.LISTING_HEIGHT)
	view:SetElementInitializer("Button", FillRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	--- Draw the list from what the client holds now, the last party members
	--- Blizzard's first ten rows miss on top.
	---
	--- SYSTEM OFF: the RequiresRecentAllies calls answer nothing
	--- (RecentAlliesDocumentation.lua:332-339), so nothing is read. NOT READY:
	--- Blizzard's list shows a spinner while its own request runs
	--- (Templates.lua:65-70); no request of ours is running, so the notice
	--- points to Blizzard's tab, whose request fills the cache, and the cache
	--- event then draws the list here. Either way the last party members still
	--- show, by the author's decision, and the notice only when nobody does.
	function ratings:Refresh(retainScrollPosition)
		local notice = L.NO_RECENT_ALLIES
		local allies = {}
		if not C_RecentAllies.IsSystemEnabled() then
			notice = L.RECENT_ALLIES_UNAVAILABLE
		elseif C_RecentAllies.IsRecentAllyDataReady() ~= true then
			notice = L.RECENT_ALLIES_NOT_READY_FORMAT:format(L.FRIENDS, L.RECENT_ALLIES)
		else
			for position, ally in ipairs(C_RecentAllies.GetRecentAllies() or {}) do
				table.insert(allies, Entry(ally, position))
			end
			table.sort(allies, MostRecentFirst)
		end

		local entries = PartyEntries(allies)
		for _, entry in ipairs(allies) do
			table.insert(entries, entry)
		end

		scrollBox:SetDataProvider(CreateDataProvider(entries), retainScrollPosition)
		empty:SetText(notice)
		empty:SetShown(#entries == 0)
	end

	ratings:SetScript("OnShow", function(self)
		FrameUtil.RegisterFrameForEvents(self, EVENTS)
		self:Refresh(ScrollBoxConstants.DiscardScrollPosition)
	end)
	ratings:SetScript("OnHide", function(self)
		FrameUtil.UnregisterFrameForEvents(self, EVENTS)
	end)
	ratings:SetScript("OnEvent", function(self)
		self:Refresh(ScrollBoxConstants.RetainScrollPosition)
	end)

	-- A rating saved or cleared (Clear player rating): the drawn rows light
	-- their stars again, in place. A star click already lit its own row; this
	-- is for a rating cleared by name, and costs a redraw of the stars only.
	EventRegistry:RegisterCallback(LFGF.EVENT_PLAYER_RATING_CHANGED, function()
		scrollBox:ForEachFrame(function(row)
			if row.Stars and row.entry then
				FillStars(row.Stars, row.entry)
			end
		end)
	end, ratings)

	-- A player who joins your party shows at once while the tab is up; a
	-- hidden tab reads nothing, and draws them on its next show.
	EventRegistry:RegisterCallback(LFGF.EVENT_RECENT_PARTY_MEMBERS_CHANGED, function()
		if ratings:IsVisible() then
			ratings:Refresh(ScrollBoxConstants.RetainScrollPosition)
		end
	end, ratings)

	return ratings
end

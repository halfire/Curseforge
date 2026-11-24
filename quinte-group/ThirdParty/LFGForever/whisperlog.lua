-- QuinteLFG -- core/whisperlog.lua
--
-- The Whispers tab's content: every whisper RECEIVED since the window was first
-- opened this session, newest last. The log is built with the window, lazily,
-- so whispers before the first open are not listed (accepted by the author,
-- 2026-10-11). Whispers the player sends are not listed.
--
-- Same factory contract as core/listpanel.lua and core/filterpanel.lua --
-- create, fill, return UNANCHORED and unsized, and let the caller place it.
-- Here the caller is core/filterpanel.lua, which owns the tabs.
--
-- IN MEMORY ONLY, by decision. There is no SavedVariables entry and no
-- persistence: the log is a live view of this session, and it starts empty
-- after a /reload. That keeps the addon's saved state empty, which is worth
-- something on its own -- nothing to migrate, nothing to corrupt.
--
-- THE SECRET-VALUE CONSTRAINT IS THE WHOLE DESIGN, not a detail.
-- CHAT_MSG_WHISPER is SecretInChatMessagingLockdown = true
-- (ChatInfoDocumentation.lua:2596), and of its 18 payload fields most carry
-- NeverSecret -- but NOT `text` (:2600), NOT `playerName` (:2601) and NOT
-- `guid` (:2611). So in a dungeon, a raid, an encounter or on a restricted map
-- the two fields this file exists to show are both secret.
--
-- A setter accepts a secret, so they can be DISPLAYED. Everything else on one
-- errors: no string.format to build "Jaina whispers: ...", no concatenation, no
-- comparison, no use as a table key. That rules out the obvious designs --
-- Blizzard's own CHAT_WHISPER_GET = "%s whispers: " (GlobalStrings/enUS.lua
-- :3999) cannot be used at all, and neither can grouping a conversation by
-- sender, which would need the name as a key.
--
-- What survives is a row of INDEPENDENT FontStrings -- the name, the level, the
-- message -- each filled with one SetText and never combined.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

-- INCOMING ONLY: CHAT_MSG_WHISPER (ChatInfoDocumentation.lua:2595). Its
-- outgoing twin, CHAT_MSG_WHISPER_INFORM, is deliberately NOT registered -- the
-- log is what other people said to you, so every row is the same kind of row.
local WHISPER_EVENT = "CHAT_MSG_WHISPER"

-- HOW MANY ARE KEPT is a setting now: LFGF.WhisperLogSize() in core/main.lua,
-- default 200, set from Options -> AddOns by core/settings.lua. A cap is still
-- needed: a session can run for hours, and every entry holds two strings the
-- garbage collector cannot drop while the log does.

-- Published so the tab's title and this file cannot drift.
LFGF.WHISPERS_TAB_TITLE = L.WHISPERS_TAB_TITLE

-- The title of the one section on that tab, above the log. Parallel in shape
-- to the Filters tab's "Find groups by role", whose header carries Reset
-- filters where this one carries Clear chat (core/filterpanel.lua). Ours, not a
-- GlobalString: English unless a language pack replaces it (core/locale.lua).
LFGF.WHISPERS_SECTION_TITLE = L.WHISPERS_SECTION_TITLE

-- THE ROW is the shared one-line player row (core/playerrow.lua): name,
-- guild / friend icon, level, class icon and the text slot, which holds the
-- whisper. This file adds the action line under it, the tooltip and the menu.
local Row = LFGF.PlayerRow

-- THE ACTION LINE: "Remove | Location | Invite" under every whisper,
-- right-aligned to the row's end, on a line that starts at the name's column.
-- The height of every link the addon draws (LFGF.CreateRowLink), so the
-- links are the same controls at the same size wherever they appear. Every row
-- carries one -- Remove is on every row -- so every row is the same height.
local ACTION_LINE_HEIGHT = 16
local ACTIONS_ROW_HEIGHT = Row.HEIGHT + ACTION_LINE_HEIGHT
local ACTION_LINK_GAP = 4

-- No global says it, so the addon does -- as ASK_TO_JOIN_LABEL does in
-- core/listpanel.lua. Invite and Remove are Blizzard's own INVITE and REMOVE
-- (enUS.lua:12570, :18462). REMOVE is Blizzard's word for taking an entry out
-- of a list -- a friend, an ignore, a raid member, a calendar invitee
-- (UnitPopupSharedButtonMixins.lua:2150, Blizzard_Calendar.lua:3896) -- where
-- HIDE is a visibility toggle and DELETE destroys data.
local LOCATION_LABEL = L.LOCATION

-- Two separators at most: between Remove and Location, and between Location and
-- Invite. Fewer links show fewer of them.
local MAX_SEPARATORS = 2

local EMPTY_TEXT = L.NO_WHISPERS

-- The row stays ONE LINE, so a long whisper is cut off on screen and the
-- tooltip is where the rest of it lives.
--
-- The cap is ours. Nothing in the sources states a tooltip line limit, and a
-- whisper cannot reach this length today -- the server caps a chat message at
-- 255 bytes (Blizzard's own editbox does SetMaxBytes(255),
-- ChatFrameEditBox.lua) -- so this is a guard against a payload that is not
-- one, not an expected case. Big enough that it never fires on a real whisper,
-- small enough that a hostile one cannot paint over the screen.
local TOOLTIP_MAX_CHARS = 1000
LFGF.WHISPER_TOOLTIP_MAX_CHARS = TOOLTIP_MAX_CHARS

--- Open Blizzard's player menu on this row: the shared one both lists open
--- (Row.OpenMenu, core/playerrow.lua), with what only a whisper carries.
---
--- WHAT WE PASS THAT THE WHO LIST CANNOT:
---   * lineID -- the 11th payload field, NeverSecret
---     (ChatInfoDocumentation.lua:2610). UnitPopupReportChatButtonMixin:CanShow
---     needs a playerLocation that IsChatLineID (:1479-1490), so this is what
---     puts REPORT PLAYER in the menu, against this very whisper.
---   * guid -- the 12th, which is what a playerLocation is built from.
---   * chatType "WHISPER", which UnitPopupPopoutChatButtonMixin:CanShow tests
---     for (:412-424), earning Pop Out Chat a place.
---
--- In chat-messaging lockdown the sender's name cannot be read, and the menu
--- does not open at all (Row.OpenMenu says why).
local function ShowRowMenu(row)
	local entry = row.entry
	if not entry then
		return
	end

	Row.OpenMenu(row, entry.name, {
		chatType = "WHISPER",
		lineID = LFGF.Readable(entry.lineID, nil),
		guid = LFGF.Readable(entry.guid, nil),
	})
end

--- Cut a whisper down to something a tooltip can hold.
---
--- MEASURING IS THE PART THAT CAN FAIL. A whisper's text is secret in
--- chat-messaging lockdown (ChatInfoDocumentation.lua:2596 -- `text` carries no
--- NeverSecret), which is exactly the raid the Group Finder is used from, and
--- secretwrap is documented as "preventing most operations on them from
--- occurring on tainted code paths" (FrameScriptDocumentation.lua:430).
--- string.sub on one is certainly out; the sources do not enumerate whether `#`
--- is, so both sit behind the same guard rather than one being reasoned about.
---
--- THE HARNESS CANNOT SEE THE `#`, so do not trust a green suite here: Lua 5.1
--- ignores __len for tables, and WowMocks.Secret is a table
--- (element_mocks.lua:564), so `#secret` silently answers 0 instead of erroring.
--- Modelling it would mean asserting a client behaviour the sources do not
--- state. Dropping this guard therefore costs nothing in a spec and may cost
--- the whole tooltip in a raid.
---
--- A SECRET MESSAGE IS SHOWN WHOLE, not dropped: SetText is a setter and takes
--- a secret happily, so the choice is between the real message untruncated and
--- no tooltip at all. Untruncated wins, and it is safe for the reason above --
--- a real whisper is 255 bytes, so there is nothing to truncate.
---
--- CONTINUED is Blizzard's own ellipsis string (GlobalStrings/enUS.lua:5091),
--- not "..." typed out, so it is whatever the player's locale uses.
local function TruncateForTooltip(text)
	local readable = LFGF.Readable(text, nil)
	if readable == nil or #readable <= TOOLTIP_MAX_CHARS then
		return text
	end
	return string.sub(readable, 1, TOOLTIP_MAX_CHARS) .. L.CONTINUED
end

--- Build a row, once per pooled frame: the shared player row
--- (core/playerrow.lua), then the action line and the row's own scripts.
---
--- NO SetHeight HERE, deliberately. The VIEW sizes each row, from the extent
--- in CreateWhisperLog, BEFORE it runs this initializer
--- (ScrollBoxListView.lua:383, :397-421) -- so a height set here would override
--- the view's on a new frame, and flatten every two-line row built from scratch.
local function BuildRow(row)
	Row.Build(row)

	-- PLAYER RATINGS, PHASE 3: the sender's rating as a 2 px strip over the
	-- band's left edge (LFGF.CreateRatingStrip, core/main.lua), written on every
	-- fill.
	if LFGF.RatingsAvailable then row.RatingStrip = LFGF.CreateRatingStrip(row) end

	-- THE ACTION LINE, under the name: Remove | Location | Invite. Text links
	-- drawn the way the filter panel draws its links. Location and Invite come
	-- from the shared action factory in core/main.lua -- the same cooldown as
	-- the players list's plus. Remove is a plain link: it touches only this log,
	-- so it is not paced (see below).
	--
	-- A FRAME for the line, and a plain one: it does not take the mouse, so a
	-- right-click between the links still reaches the row. Two corner anchors
	-- and a height make it rectangle-valid without a centre-bearing point.
	local actions = CreateFrame("Frame", nil, row)
	actions:SetPoint("TOPLEFT", row, "TOPLEFT", Row.NAME_INSET_X, -Row.HEIGHT)
	-- MIRRORS THE NAME: the line ends Row.NAME_INSET_X in from the row's right edge,
	-- as the name starts that far in from its left -- so the rightmost link
	-- sits as far inside the row's background box as the name does.
	actions:SetPoint("TOPRIGHT", row, "TOPRIGHT", -Row.NAME_INSET_X, -Row.HEIGHT)
	actions:SetHeight(ACTION_LINE_HEIGHT)
	row.Actions = actions

	-- REMOVE TAKES THIS WHISPER OUT OF THE LOG, and nothing else: nothing is sent
	-- to anyone, so it is NOT on the shared action cooldown -- that cooldown
	-- paces what reaches other players, and clearing several whispers in a row
	-- is exactly what Remove is for. The row's log and entry are read at CLICK
	-- time, because rows are pooled and both are re-stamped on every fill.
	local remove = LFGF.CreateRowLink(actions, L.REMOVE)
	remove:SetScript("OnClick", function()
		LFGF.PlayClick()
		if row.log and row.entry then
			row.log:Remove(row.entry)
		end
	end)
	row.RemoveLink = remove

	row.LocationLink = LFGF.CreateRowActionLink(actions, LOCATION_LABEL)
	row.InviteLink = LFGF.CreateRowActionLink(actions, L.INVITE)

	-- The addon's one separator (core/main.lua), the same pipe the players
	-- list puts between an activity and a zone. Placed by LayOutActions.
	row.Separators = {}
	for index = 1, MAX_SEPARATORS do
		local separator = actions:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		separator:SetText(LFGF.SEPARATOR)
		row.Separators[index] = separator
	end

	-- BLIZZARD'S OWN TOOLTIP, and as little of ours as the job allows: the
	-- message alone, word-wrapped (LFGF.ShowTextTooltip), or a long whisper
	-- renders as one endless line off the edge of the screen.
	row:SetScript("OnEnter", function(self)
		local entry = self.entry
		if not entry or entry.text == nil then
			return
		end
		LFGF.ShowTextTooltip(self, TruncateForTooltip(entry.text), true)
		-- PLAYER RATINGS, PHASE 3: under the message, the sender's rating as the
		-- stars tooltip words it, in the rating's colour (the author's decisions,
		-- 2026-11-13). Nothing for a sender not rated or not readable.
		local line, r, g, b = LFGF.PlayerRatingLine(entry.name)
		if line then
			GameTooltip:AddLine(line, r, g, b, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)

	-- RIGHT ONLY, and RegisterForClicks is the whole of that restriction --
	-- a Button reports only LeftButtonUp until told otherwise, so this both
	-- turns the right button on and leaves the left one off. Left-click has no
	-- behaviour of ours yet, here or in the list.
	--
	-- NO `if button ~= "RightButton"` INSIDE, unlike core/listpanel.lua's row.
	-- There the check is load-bearing: that row inherits Blizzard's template,
	-- whose OnLoad registers BOTH buttons (Browse.lua:502), so the handler
	-- really does see left clicks. Here it would be a branch nothing can reach.
	-- Anyone adding LeftButtonUp below must add the check back with it.
	--
	-- RegisterForClicks is not an event registration, so UnregisterAllEvents
	-- does not undo it.
	row:RegisterForClicks("RightButtonUp")
	row:SetScript("OnClick", function(self)
		LFGF.PlayClick()
		ShowRowMenu(self)
	end)
end

--- Open the chat box with `/who "Firstname Surname"` typed in.
---
--- IT DOES NOT SEND THE /who, and cannot. The first version did, with
--- C_FriendList.SendWho straight from this click, and the client refused it:
---     [ADDON_ACTION_BLOCKED] AddOn 'QuinteLFG' tried to call the protected
---     function 'SendWho()'.
--- The sources say only HasRestrictions = true (FriendListDocumentation.lua
--- :330-334), and RunMacroText is the same (UIMacrosDocumentation.lua:41-44).
--- So the addon stops one step short: the player presses Enter, and Blizzard's
--- chat box runs its own /who handler (ChatFrameEditBox.lua:442-446 ->
--- ParseText -> SlashCommands.lua:1106-1117), which sends it. ChatFrameUtil
--- .OpenChat (ChatFrameUtil.lua:433) is how ChatFrameUtil.SendTell pre-fills a
--- whisper (:367-386), which the players list already uses.
---
--- IT NEVER OPENS BLIZZARD'S GROUP FINDER. The version before this opened the
--- Who tab from this click. Blizzard's LFGParentFrameMixin:OnShow then wrote
--- LFGParentFrame.selectedTab inside our call (ParentFrame.lua:56-57 ->
--- PanelTemplates_SetTab, SharedUIPanelTemplates.lua:442), so the field
--- carried our taint. LFGVanilla_ToggleFrame reads it before ShowUIPanel
--- (:138), so from then on the player's own Group Finder key and micro button
--- were refused in combat (UIParentPanelManager.lua:854-861) with "Interface
--- action failed because of an AddOn". Reproduced in the client.
---
--- THE QUERY IS THE QUOTED FULL NAME. Tested in the client: `/who "Firstname
--- Surname"` finds the player, while Blizzard's own exact-name tag, x- (what a
--- shift-click on a name sends, ItemRefHandlers.lua:38), and n- do not. A name
--- here has two parts (CHARACTERNAME_SURNAME_SEPARATOR is a space,
--- LuaEnum.lua:9533), and the quotes keep them one term.
local function OpenWhoFor(name)
	ChatFrameUtil.OpenChat('/who "' .. name .. '"')
end

--- Place the shown links, RIGHT-ALIGNED and so BUILT RIGHT TO LEFT: the last
--- one takes the line's right end, and each earlier one hangs its RIGHT off a
--- separator hung off the LEFT of the one after it. `links` is left to right.
---
--- RE-ANCHORED ON EVERY FILL, not once at build time, because which links show
--- changes from row to row: an anchor to a hidden region still resolves, so a
--- fixed chain would leave a gap where a hidden link was. Everything not in
--- `links` is hidden, so a pooled row keeps nothing from its last whisper.
local function LayOutActions(row, links)
	for _, link in ipairs({ row.RemoveLink, row.LocationLink, row.InviteLink }) do
		link:Hide()
	end
	for _, separator in ipairs(row.Separators) do
		separator:Hide()
	end

	local right = nil
	for index = #links, 1, -1 do
		local link = links[index]
		link:ClearAllPoints()
		if right == nil then
			link:SetPoint("RIGHT", row.Actions, "RIGHT", 0, 0)
		else
			local separator = row.Separators[#links - index]
			separator:ClearAllPoints()
			separator:SetPoint("RIGHT", right, "LEFT", -ACTION_LINK_GAP, 0)
			separator:Show()
			link:SetPoint("RIGHT", separator, "LEFT", -ACTION_LINK_GAP, 0)
		end
		link:Show()
		right = link
	end
end

--- Decide which links this row gets, and wire them.
---
--- REMOVE IS ON EVERY ROW: it needs nothing from the whisper.
---
--- LOCATION AND INVITE need entry.actionName, decided when the whisper was
--- recorded: a sender whose name can be read.
---
--- THE NAME MUST BE READABLE for both: C_PartyInfo.InviteUnit is
--- SecretArguments = "AllowedWhenUntainted" (PartyInfoDocumentation.lua:360),
--- and the Who query is built by concatenating the name. In chat-messaging
--- lockdown a row therefore shows Remove alone -- a link that errors when
--- clicked is worse than none.
---
--- LOCATION IS DROPPED WHEN BLIZZARD'S /who CANNOT RUN: under
--- IngameWhoListDisabled, the rule it checks first and then does nothing
--- (SlashCommands.lua:1107-1110), and while WhoFrameEditBox does not exist. The
--- handler writes that box with no nil check (:1116), and it belongs to the
--- LoadOnDemand Group Finder (WhoList.xml:141), so pressing Enter without it
--- would raise an error in Blizzard's code.
---
--- Set on EVERY fill, because rows are pooled. The lock is re-applied for the
--- same reason -- a row filled mid-cooldown must show it.
local function UpdateActions(row, entry)
	local invite, location = row.InviteLink, row.LocationLink
	invite.action, location.action = nil, nil
	LFGF.ApplyActionLockTo(invite)
	LFGF.ApplyActionLockTo(location)

	local links = { row.RemoveLink }

	local name = entry.actionName
	if name ~= nil then
		if WhoFrameEditBox
			and not C_GameRules.IsGameRuleActive(Enum.GameRule.IngameWhoListDisabled) then
			location.action = function()
				OpenWhoFor(name)
			end
			table.insert(links, location)
		end

		invite.action = function()
			if not InCombatLockdown() then Quintessence.Invite(name) end
		end
		table.insert(links, invite)
	end

	LayOutActions(row, links)
end

--- Fill a row from one entry: the shared player row's regions
--- (core/playerrow.lua, which says why every property is written on every
--- pass), then the action line.
---
--- The entry's class and level came from GetPlayerInfoByGUID when the whisper
--- was recorded, and its level is Nilable even when the class is known
--- (PlayerScriptDocumentation.lua:856), which the shared row's "both or
--- neither" rule covers.
local function FillRow(row, entry)
	if not row.Name then
		BuildRow(row)
	end

	-- ON THE ROW, because the menu is built long after this returns and rows are
	-- pooled: without re-stamping, right-clicking an old row would offer to
	-- whisper whoever last occupied that frame.
	row.entry = entry

	Row.Fill(row, entry)
	if row.RatingStrip then LFGF.ShowRatingStrip(row.RatingStrip, entry.name) end

	UpdateActions(row, entry)
end

--- Whether a whisper arriving now should scroll the log to it: the view sits at
--- the newest whisper, or the list cannot scroll at all.
---
--- BLIZZARD'S EVENT TRACE RULE (Blizzard_EventTrace.lua:667-685): asked BEFORE
--- the insert, because adding a row moves the percentage -- the ScrollBox keeps
--- the scroll offset in pixels across a data change (ScrollBox.lua:164-185), so
--- after the insert a view that was at the end no longer is. So a player who
--- scrolled up to read stays where they are, and one who scrolls back down is
--- followed again.
---
--- "CANNOT SCROLL" COUNTS AS FOLLOWING: while every row fits there is no range,
--- the ScrollBox sits at the top (:183-184) and IsAtEnd is false, yet the
--- whisper that first makes the list scroll must still be shown.
local function FollowsNewest(scrollBox)
	return scrollBox:IsAtEnd() or not scrollBox:HasScrollableExtent()
end

--- Record one whisper, then trim the log to its size (log:Trim).
local function Record(log, text, name, guid, lineID)
	-- THE GUID IS THE ONLY ROUTE TO CLASS AND LEVEL: the chat payload carries
	-- neither. GetPlayerInfoByGUID hands back englishClass and level
	-- (PlayerScriptDocumentation.lua:849, :856), and it is on the
	-- SecretArguments = "AllowedWhenTainted" whitelist (:840), so a secret guid
	-- may be passed to it from addon code -- which matters, because the guid
	-- carries no NeverSecret (ChatInfoDocumentation.lua:2611).
	--
	-- What it ANSWERS for a secret guid is not settled by the sources, and it is
	-- MayReturnNothing (:772) besides, so both returns are captured into locals
	-- and neither is trusted. Resolved ONCE here rather than on every render:
	-- the answer does not change, and a pooled row is filled many times.
	local _, classFilename, _, _, _, _, _, level = GetPlayerInfoByGUID(guid)

	-- WHO GETS LOCATION AND INVITE, decided once: anyone whose name can be
	-- read, a whisper from yourself included
	-- (.claude/rules/whisper-location-lookup.md).
	local actionName = LFGF.Readable(name, nil)

	local follow = FollowsNewest(log.ScrollBox)

	log.Provider:Insert({
		text = text, name = name,
		classFilename = classFilename, level = level,
		actionName = actionName,
		-- Kept for the row's menu, which is opened long after this returns.
		guid = guid, lineID = lineID,
	})

	log:Trim()

	-- Follow the conversation, unless the player has scrolled up to read. At
	-- the size cap a paused view still moves up one row per whisper, because
	-- the trim takes a row from above it and the offset is kept: accepted by the
	-- author (.claude/rules/whisper-log-follow.md).
	if follow then
		log.ScrollBox:ScrollToEnd()
	end

	-- SAY SO, so the tab can flash. This file owns the log, not the tab strip,
	-- so it announces rather than reaching across.
	EventRegistry:TriggerEvent(LFGF.EVENT_WHISPER_RECEIVED)
end

--- Build the Whispers tab's content. Returned unanchored and unsized.
function LFGF.CreateWhisperLog(parent)
	local log = CreateFrame("Frame", nil, parent)

	local scrollBox, scrollBar, empty = LFGF.CreateScrollList(log)
	log.ScrollBox = scrollBox
	log.ScrollBar = scrollBar
	empty:SetText(EMPTY_TEXT)
	log.EmptyText = empty

	-- A LINEAR view, not the tree one core/listpanel.lua uses: a whisper log has
	-- no grouping to express, and grouping by sender is exactly what a secret
	-- name forbids.
	local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 0)
	-- Every row carries the action line, so every row is the same height. The
	-- VIEW sets it, before the initializer runs (ScrollBoxListView.lua:383) --
	-- which is why BuildRow sizes nothing.
	view:SetElementExtent(ACTIONS_ROW_HEIGHT)
	-- A BUTTON, not a Frame: the row takes a right-click. Same reason
	-- LFGBrowseSearchEntryTemplate is one.
	-- The row learns its log here, for Remove: rows are pooled, so it is
	-- re-stamped on every fill like the entry is.
	view:SetElementInitializer("Button", function(row, entry)
		row.log = log
		FillRow(row, entry)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	log.Provider = CreateDataProvider()
	scrollBox:SetDataProvider(log.Provider)

	--- Throw the session's whispers away.
	---
	--- THE EMPTY NOTICE IS SHOWN EXPLICITLY, because Flush does not run Record
	--- and Record is the only other place that maintains it. Leaving it out is
	--- the easy bug here: a blank panel with no explanation, which reads as the
	--- log having broken rather than having been cleared.
	function log:Clear()
		self.Provider:Flush()
		self.EmptyText:Show()
	end

	--- Keep no more whispers than LFGF.WhisperLogSize() says.
	---
	--- OLDEST FIRST: new whispers go on the end, so index 1 is always the
	--- oldest, and removing from the front keeps the newest in view at the
	--- bottom. One RemoveIndexRange on the provider, not a rebuild and not one
	--- removal per whisper: it fires OnSizeChanged once, after the loop
	--- (DataProvider.lua:170-185), and that one event is what re-renders the
	--- ScrollBox (the list view subscribes to it, ScrollBoxListView.lua:324).
	---
	--- Called after every whisper, and whenever the size setting changes -- so
	--- lowering it trims at once, while raising it removes nothing.
	function log:Trim()
		local excess = self.Provider:GetSize() - LFGF.WhisperLogSize()
		if excess > 0 then
			self.Provider:RemoveIndexRange(1, excess)
		end
		self.EmptyText:SetShown(self.Provider:GetSize() == 0)
	end

	-- A RATING SAVED OR CLEARED, or the Player ratings setting switched: the
	-- drawn rows are re-marked in place. Hidden or not: the log is on another
	-- tab than the Player ratings tab where a rating is made or cleared, and its
	-- rows are not refilled when the tab comes back.
	local function RemarkRows()
		scrollBox:ForEachFrame(function(row, entry)
			if row.RatingStrip and entry then
				LFGF.ShowRatingStrip(row.RatingStrip, entry.name)
			end
		end)
	end
	EventRegistry:RegisterCallback(LFGF.EVENT_PLAYER_RATING_CHANGED, RemarkRows, log)
	EventRegistry:RegisterCallback(LFGF.EVENT_PLAYER_RATINGS_CHANGED, RemarkRows, log)

	-- The size setting moved (core/settings.lua). The log is the owner, so one
	-- log registers once however often the setting changes.
	EventRegistry:RegisterCallback(LFGF.EVENT_WHISPER_LOG_SIZE_CHANGED, function()
		log:Trim()
	end, log)

	--- Drop one whisper -- what a row's Remove link does. By identity, through
	--- DataProviderMixin:Remove (DataProvider.lua:125-145), whose OnSizeChanged
	--- re-renders the list. The empty notice is maintained here for the same
	--- reason Clear maintains it: Record is the only other place that does.
	function log:Remove(entry)
		self.Provider:Remove(entry)
		self.EmptyText:SetShown(self.Provider:GetSize() == 0)
	end

	-- BACK TO THE NEWEST WHISPER WHENEVER IT IS HIDDEN: switching to the Filters
	-- tab hides it (TabSystemOwner.lua:46-51), and so does closing the window,
	-- since OnHide reaches a shown child whose parent hides. So it comes back on
	-- the newest whisper, and a whisper that arrives meanwhile is followed.
	-- OnHide, not OnShow: a window closed on the Filters tab hides nothing here,
	-- because the tab switch already did.
	log:SetScript("OnHide", function(self)
		self.ScrollBox:ScrollToEnd()
	end)

	-- The menu's one fix (Copy Character Name greyed out), registered once per
	-- session by whichever list is built first.
	Row.RegisterMenuModifier()

	-- REGISTERED ON THE LOG, NOT ON WHATEVER IS SHOWING. It lives in a tab, so
	-- most of the time it is hidden -- and a frame that is hidden still receives
	-- the events it registered for. A log that only listened while visible would
	-- be empty the first time anyone opened the tab.
	log:RegisterEvent(WHISPER_EVENT)
	-- The payload is 18 arguments and the guid is the TWELFTH
	-- (ChatInfoDocumentation.lua:2611), so the unused ten in between are skipped
	-- with select rather than named as a run of underscores -- assigning to a
	-- bare global _ is a taint hazard this repo bans outright. One event is
	-- registered, so the event name itself is not needed.
	log:SetScript("OnEvent", function(self, _, text, name, ...)
		if Quintessence.GuildStatus() ~= "ok" then return end
		local lineID, guid = select(9, ...)
		Record(self, text, name, guid, lineID)
	end)

	return log
end

-- QuinteLFG -- core/listpanel.lua
--
-- The left-hand column: the list of groups and players.
--
-- Same factory contract as core/filterpanel.lua -- create, fill, return
-- unanchored, and let core/window.lua place it.
--
-- SHAPE, copied from Blizzard's camelot Browse panel (Blizzard_LFGVanilla_
-- Browse.lua:52-137, :184-231, :364-498):
--   * a TREE view, not a linear one, because results are grouped into
--     collapsible "Players" and "Groups" subtrees;
--   * Blizzard's own row templates, so rows look identical;
--   * one row per result, plus one divider per category.
--
-- IT LISTENS, IT IS NOT TOLD. core/filterpanel.lua runs the search; this panel
-- registers for the same game events. Neither panel knows the other exists.
--
-- SECRET VALUES -- the reason this file is more careful than the filter panel.
-- GetSearchResultInfo, GetSearchResultLeaderInfo and GetSearchResultPlayerInfo
-- are all SecretInChatMessagingLockdown = true (LFGListInfoDocumentation.lua
-- :397, :414, :431). That is a per-FUNCTION flag: it makes the WHOLE return
-- secret while the predicate holds, and the opt-out is a per-field
-- NeverSecret = true. LfgSearchResultData has exactly one (partyGUID, :1009);
-- LfgSearchResultPlayerInfo has NONE. So in lockdown even numMembers and
-- isDelisted are secret, not just the obvious name and comment.
--
-- Three operations error on a secret, and this file does all three carefully:
--   comparing  (numMembers <= 1)          -> guard, then compare
--   concatenating (LEVEL_ABBR .. level)   -> pass the value to a setter instead
--   indexing a table BY the value
--       (RAID_CLASS_COLORS[classFilename]) -> guard, else fall back
--
-- The guard is canaccessvalue, which is the question Blizzard's own chat filter
-- registry asks (ChatFrameFilters.lua:115-118) and is stricter than
-- issecretvalue: false for a secret AND for a value the caller may not touch.
-- Where a guard fails this file FAILS OPEN -- it shows the listing rather than
-- hiding it, because hiding what you could not verify is the worse mistake.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L
local S = Quintessence.Style

-- Blizzard's row template is 312x48 and its divider is shorter
-- (Mainline/Blizzard_LFGVanilla_Browse.xml).
local ROW_TEMPLATE = "LFGBrowseSearchEntryTemplate"
local DIVIDER_TEMPLATE = "LFGBrowseSearchEntryGroupingTemplate"

-- Browse.lua:210-213 -- the two buckets results are split into.
local DIVIDER_SOLO, DIVIDER_GROUP = "solo", "group"

-- A row with an inline note is Blizzard's three-line row: 72 against the
-- template's 52 (Mainline/Blizzard_LFGVanilla_Browse.xml:140, :241). The
-- buttons and roles stay centred on the whole row: their RIGHT anchor
-- follows its height.
local NOTE_LINE_EXTENT = 20

-------------------------------------------------------
---------- Reading a result safely
-------------------------------------------------------

-- Both guards live in core/main.lua now: core/whisperlog.lua reads chat data
-- with exactly the same three hazards, and one copy is better than two that can
-- drift. Localised here because this file calls Readable eighteen times.
local Readable = LFGF.Readable
local ClassIconAtlas = LFGF.ClassIconAtlas

-------------------------------------------------------
---------- The row action buttons
-------------------------------------------------------

-- TWO ACTIONS, ONE SLOT. What a listing is decides which of them makes sense,
-- and they are never both right at once:
--
--   a PLAYER listing  ->  invite them into your party   (a plus)
--   a GROUP  listing  ->  ask to be let into theirs     (a speech bubble)
--
-- So the two buttons occupy the SAME rect at the right end of the row rather
-- than two side by side. That is not only tidier: the row's roles column is
-- anchored to the left of that rect, so one slot means the roles line up in a
-- single column across every row, instead of stepping in and out by a button's
-- width as the list mixes players and groups.
--
-- The speech bubble is natively 13x13 in the running client's atlas dump
-- (AtlasInfo.lua:25094), the same size as the plus the shared factory wears
-- (:3276), so the pair is drawn 1:1 and reads as one set. That it comes off the
-- transmog art sheet is irrelevant at this size -- what matters is that the
-- dump proves it exists here, which is the only evidence an atlas name can have.
local ASK_TO_JOIN_ICON_ATLAS = "transmog-icon-chat"

-- No Blizzard global says this, so the addon says it, in the same plain English
-- as its filter-section titles.
local ASK_TO_JOIN_LABEL = L.ASK_TO_JOIN

-- A GROUP ALREADY ASKED keeps its bubble and gains a small check on the
-- bubble's lower right, and its tooltip says "Ask to join again". No atlas in
-- the running client's dump is a bubble with a check, so the check is a second
-- texture. It is Blizzard's own Group Finder check, which their retail finder
-- puts on this same button template (Blizzard_GroupFinder/Mainline/
-- LFGList.xml:384); 11x13 in the dump, drawn at 9x11, the author's choice, so
-- the bubble still reads. The offset is by eye. .claude/rules/asked-to-join-mark.md.
local ASKED_CHECK_ATLAS = "groupfinder-icon-greencheckmark"
local ASKED_CHECK_WIDTH, ASKED_CHECK_HEIGHT = 9, 11

-- The groups asked this session, partyGUID -> true. Only a click on the Ask to
-- Join button adds one, by the author's decision: nothing listens to whispers.
-- Keyed by the GROUP'S ID, not the leader's name and not the searchResultID:
-- partyGUID is NeverSecret (LFGListInfoDocumentation.lua:1013), and Blizzard's
-- retail finder remembers declined groups across searches by it (Blizzard_
-- GroupFinder/Mainline/LFGList.lua:321, :2842), while nothing says a
-- searchResultID survives the next search. In memory only: a /reload forgets.
local askedParties = {}

-- THE WHISPER IS A SETTING NOW: "Auto-whisper on Ask to Join" and its message,
-- under Options -> AddOns -> LFG Forever (core/settings.lua). The text, with
-- its placeholders (%class%, %level%, %talents%, %role%) filled in, comes from
-- LFGF.AskToJoinMessage in core/main.lua at CLICK time.

-- THE BUTTON SHAPE AND THE ACTION COOLDOWN NOW LIVE IN core/main.lua, because
-- core/whisperlog.lua puts the same plus on an incoming whisper. Sharing the
-- SHAPE is tidiness; sharing the LOCK is correctness -- two copies would be two
-- independent cooldowns, and the property that makes it worth having is that
-- one action paces every button the player can see.
local CreateRowButton = LFGF.CreateRowActionButton
local ApplyLockTo = LFGF.ApplyActionLockTo
local INVITE_ICON_ATLAS = LFGF.INVITE_ICON_ATLAS

--- Build the row's two buttons, once per row frame.
---
--- THE DATA DISPLAY IS RE-ANCHORED to make room. The template hangs it off the
--- row's own RIGHT (Browse.xml:192), so without this a button would sit on top
--- of the role icons. It is anchored to the invite button because both buttons
--- share that rect; the space is reserved whether or not either is showing.
local function EnsureRowButtons(row)
	if row.LFGFInvite then
		return
	end

	row.LFGFInvite = CreateRowButton(row, INVITE_ICON_ATLAS, L.GROUP_INVITE)
	row.LFGFAskToJoin = CreateRowButton(row, ASK_TO_JOIN_ICON_ATLAS, ASK_TO_JOIN_LABEL)
	row.DataDisplay:SetPoint("RIGHT", row.LFGFInvite, "LEFT", -2, -1)

	-- Anchored to the bubble, so the template's press nudge, which moves only
	-- self.Icon (SharedUIPanelTemplates.lua:929-945), moves the check too.
	-- ApplyActionLockTo (core/main.lua) dims it with the bubble.
	local button = row.LFGFAskToJoin
	local check = button:CreateTexture(nil, "OVERLAY")
	check:SetAtlas(ASKED_CHECK_ATLAS)
	check:SetSize(ASKED_CHECK_WIDTH, ASKED_CHECK_HEIGHT)
	check:SetPoint("CENTER", button.Icon, "BOTTOMRIGHT", -1, 3)
	check:Hide()
	button.Check = check
end

--- Show whether the group on this row was asked: the check and the tooltip,
--- both ways, because rows are pooled. The template reads tooltipText when it
--- is hovered (SharedUIPanelTemplates.lua:956-962).
local function ShowAsked(button, asked)
	button.Check:SetShown(asked)
	button.tooltipText = asked and L.ASK_TO_JOIN_AGAIN or ASK_TO_JOIN_LABEL
end

--- Whether a row's actions (Invite, Ask to Join) may show at all: a live
--- listing, not the player's own, whose leader's name can be read. Both
--- actions hand that name to an AllowedWhenUntainted API (InviteUnit,
--- PartyInfoDocumentation.lua:360; SendChatMessage, ChatInfoDocumentation.lua:
--- 568), so an unreadable one hides them rather than offering a click the
--- client would refuse.
local function CanActOnRow(row, info, isDelisted)
	return not isDelisted and not row.hasSelf and canaccessvalue(info.leaderName)
end

--- Decide whether this row may be invited, and wire the click if so.
---
--- WHO IS ELIGIBLE IS BLIZZARD'S CALL. LFGBrowseUtil_GetInviteActionForResult
--- (Browse.lua:1456-1472) hands back a function only for a SOLO listing and
--- only when the player can invite -- in a group they do not lead, nobody can.
--- Reusing it keeps this icon and their right-click menu item agreeing about
--- who is invitable, instead of two rules that drift.
---
--- OUR OWN GUARD ON TOP (CanActOnRow), and it is the one place this does
--- better than the menu it shortcuts: a leaderName that cannot be read here
--- would be refused, and an icon that errors when clicked is worse than no
--- icon, so it is hidden. Blizzard's menu item checks only that the name is
--- non-nil (:1016) and still offers it.
---
--- THEN THE WHISPER (.claude/rules/invite-whisper.md):
--- after Blizzard's invite, the click whispers the player
--- LFGF.InviteWhisperMessage() (core/main.lua) when that answers text --
--- "Hey! Want to join Deadmines?". Invite first, by the author's decision, so
--- the whisper arrives with the invite popup. Neither call says whether it
--- worked (InviteUnit returns nothing and may wait on a confirmation,
--- PartyInfoDocumentation.lua:361), so the whisper does not wait on the
--- invite. Read at CLICK time, as Ask to Join's is. Only this button: the
--- whisper log's Invite link and Blizzard's right-click Group Invite never send
--- it.
---
--- The target is the row's leaderName, readable by CanActOnRow, and checked
--- again inside the click by LFGF.Whisper, for the reason
--- UpdateAskToJoinButton gives. One click is one action under the shared
--- two-second lock (RunAction, core/main.lua).
---
--- Set on EVERY update, because rows are pooled: a row that was a solo listing
--- keeps its button otherwise.
local function UpdateInviteButton(row, info, isDelisted)
	local button = row.LFGFInvite
	button.action = nil
	ApplyLockTo(button)

	if not CanActOnRow(row, info, isDelisted) then
		button:Hide()
		return
	end

	local _, inviteFunc = LFGBrowseUtil_GetInviteActionForResult(row.resultID)
	if inviteFunc ~= nil then
		local leaderName = info.leaderName
		button.action = function()
			if InCombatLockdown() then return end
			Quintessence.Invite(leaderName)
			local message = LFGF.InviteWhisperMessage()
			if message ~= nil then
				LFGF.Whisper(leaderName, message)
			end
		end
	end
	button:SetShown(inviteFunc ~= nil)
end

--- Decide whether this row may be asked to take the player, and wire the click.
---
--- THE MIRROR OF THE INVITE RULE: this one is for GROUPS. A solo listing has no
--- group to join, so asking would be nonsense; Blizzard's own eligibility helper
--- draws the same line from the other side (numMembers == 1, Browse.lua:1462).
---
--- WHEN numMembers IS SECRET, isSolo is false and this button is the one that
--- would show -- but leaderName is secret in exactly the same states, so the
--- guard below hides it anyway. One check covers both, because
--- SecretInChatMessagingLockdown makes the WHOLE return secret at once.
---
--- THAT GUARD IS ALSO THE LOCKDOWN GUARD. C_ChatInfo.SendChatMessage is
--- SecretArguments = "AllowedWhenUntainted" (ChatInfoDocumentation.lua:568), so
--- a secret target from an addon is refused -- and the state that makes
--- leaderName secret is the same state C_ChatInfo.InChatMessagingLockdown
--- reports, so there is nothing for a second call to add.
---
--- WHAT THE CLICK DOES follows the setting, read when the button is CLICKED so
--- a change in the settings takes effect on rows already drawn:
---   * LFGF.AskToJoinMessage() returns text -> whisper it to the leader;
---   * it returns nil (checkbox off, or an empty message) -> open a whisper to
---     the leader for the player to type in, ChatFrameUtil.SendTell
---     (ChatFrameUtil.lua:383-386), the call Blizzard's own "Send Message"
---     makes (Blizzard_LFGVanilla_Browse.lua:1014). It string.formats the name
---     (:374), which the readable-name guard already covers.
--- Only the auto-whisper starts the shared cooldown: opening a whisper box
--- sends nothing, so that path returns false and RunAction leaves the buttons
--- live.
---
--- RE-CHECKED INSIDE THE CLICK, and that guard is the one thing here the test
--- harness cannot falsify -- removing it fails no example. It is kept because
--- the sources define secrecy as "whether this particular value is classified
--- RIGHT NOW, decided by the active restriction state" rather than as a
--- property fixed when the value was handed over, and the row is not redrawn
--- when the player walks into a dungeon. If that reading is wrong the branch is
--- dead and costs nothing; if it is right, the alternative is a refused call
--- the player sees as an error from this addon.
---
--- A CLICK MARKS THE GROUP as asked (askedParties, above), whichever way it
--- goes, the whisper box included, by the author's decision. After the guard,
--- so a click that does nothing marks nothing; a click the cooldown refuses
--- never reaches the action (RunAction, core/main.lua). A tooltip showing
--- under the mouse is shown again, so it says the new text at once.
local function UpdateAskToJoinButton(row, info, isDelisted, isSolo)
	local button = row.LFGFAskToJoin
	button.action = nil
	ApplyLockTo(button)

	if isSolo or not CanActOnRow(row, info, isDelisted) then
		button:Hide()
		return
	end

	local partyGUID = Readable(info.partyGUID, nil)
	ShowAsked(button, partyGUID ~= nil and askedParties[partyGUID] == true)

	local leaderName = info.leaderName
	button.action = function()
		if not canaccessvalue(leaderName) then
			return
		end
		if partyGUID ~= nil then
			askedParties[partyGUID] = true
			ShowAsked(button, true)
			if GameTooltip:IsOwned(button) then
				button:GetScript("OnEnter")(button)
			end
		end
		local message = LFGF.AskToJoinMessage()
		if message == nil then
			Quintessence.Whisper(leaderName)
			-- Nothing was sent, so no cooldown (see RunAction, core/main.lua).
			return false
		end
		LFGF.Whisper(leaderName, message)
	end
	button:Show()
end

-------------------------------------------------------
---------- Rows
-------------------------------------------------------


-- Browse.lua:6-7. Both of Blizzard's row colours are file-locals too, so they
-- are restated here with their source. NOMATCH is GRAY_FONT_COLOR, which IS a
-- real global, so that one is read rather than copied.

--- Lay out the left of the row: party icon, name, level, class icon.
---
--- THE TWO RE-ANCHORS ARE NOT OPTIONAL. The template starts on the GROUP
--- layout and its XML marks both anchors "Reanchored in code"
--- (Browse.xml:159, :178); Blizzard does it at Browse.lua:388-389 and :398-399.
--- Skipping it draws every solo listing indented by the width of a party icon
--- that is not even shown, and leaves the newcomer icon hanging off a hidden
--- class icon.
---
--- It has to run on EVERY update, not once at creation, because the ScrollBox
--- recycles row frames -- one frame is a group row and then a solo row.
---
--- THE GUILD / FRIEND ICON takes the name's starting point and the name moves
--- after it (core/relations.lua). `relation` was decided when the search's tree
--- was built, not here -- see BuildDataProvider. The name is placed through
--- LayOutRelationIcon on BOTH branches and with or without a relation, so a
--- recycled row never keeps an indent for an icon it no longer shows. The width
--- the icon takes is kept on the row for ColourRow's clamp.
local function LayOutRow(row, isSolo, memberInfo, relation)
	row.PartyIcon:SetShown(not isSolo)

	if not row.LFGFRelation then
		row.LFGFRelation = LFGF.CreateRelationIcon(row)
	end

	if not isSolo then
		row.lfgfRelationWidth = LFGF.LayOutRelationIcon(row.LFGFRelation, row.Name, relation,
			"TOPLEFT", row.PartyIcon, "TOPRIGHT", row.NameGroupOffsetX, row.NameGroupOffsetY)
		row.ClassIcon:Hide()
		row.Level:Hide()
		-- With no class icon to sit after, it hangs off the name instead.
		row.NewPlayerFriendlyIcon:SetPoint("LEFT", row.Name, "RIGHT", 2, 0)
		return
	end

	row.lfgfRelationWidth = LFGF.LayOutRelationIcon(row.LFGFRelation, row.Name, relation,
		"TOPLEFT", row.PartyIcon, "TOPLEFT", row.NameSoloOffsetX, row.NameSoloOffsetY)
	row.NewPlayerFriendlyIcon:SetPoint("LEFT", row.ClassIcon, "RIGHT", 2, 0)
	-- The XML hangs the level off the Discord icon (Browse.xml:168-173),
	-- which this addon never shows and which still holds its width. Blizzard
	-- hangs it off the name whenever that icon is hidden (Browse.lua:464-469).
	row.Level:SetPoint("BOTTOMLEFT", row.Name, "BOTTOMRIGHT", 4, 0)

	-- BOTH OR NEITHER, as Blizzard does (Browse.lua:380-387). A level with no
	-- class, or a class icon with no level, reads as a rendering fault; showing
	-- neither reads as a listing we know less about.
	local classAtlas = memberInfo and ClassIconAtlas(memberInfo.classFilename) or nil
	local level = memberInfo and memberInfo.level or nil
	if not classAtlas or level == nil then
		row.ClassIcon:Hide()
		row.Level:Hide()
		return
	end

	-- THE CALL THE FIRST VERSION OF THIS FILE LEFT OUT, and the bug it shipped:
	-- the template hardcodes atlas="groupfinder-icon-class-warrior"
	-- (Browse.xml:168), so showing the texture without setting one put a
	-- warrior crest on every listing in the client while the name beside it was
	-- correctly class-coloured.
	row.ClassIcon:SetAtlas(classAtlas, false)
	row.ClassIcon:Show()
	row.Level:Show()

	-- Blizzard writes LEVEL_ABBR .. " " .. memberInfo.level (Browse.lua:382).
	-- Concatenating a secret errors, so this branches instead: format the prefix
	-- in when the level can be read, and otherwise hand the raw value to the
	-- setter, which accepts a secret. The player loses the "Lvl" prefix and
	-- keeps the number -- better than losing both.
	if canaccessvalue(level) then
		row.Level:SetFormattedText("%s %s", L.LEVEL_ABBR, level)
	else
		row.Level:SetText(level)
	end
end

-- Wide enough for the longest zone names, narrow enough that the text can never
-- reach the role icons on the right of a ~690px row. The zone is sized to its
-- words up to this (so the playstyle can follow straight after it), and is this
-- wide when its width cannot be read: the width of secret text is secret.
local ZONE_MAX_WIDTH = 200

--- Show where a PLAYER listing's player is: "Deadmines | Westfall".
---
--- LfgSearchResultPlayerInfo.areaName (LFGListInfoDocumentation.lua:1019).
--- Blizzard's row template has no slot for it and their camelot UI never reads
--- it, so this is the addon's own FontString, made once per row frame and hung
--- off ActivityName's right so the two can never overlap. Same font as the
--- activity (Browse.xml:181), so it reads as part of that line.
---
--- It is Nilable, and nothing on this client proves the server fills it in --
--- so a missing zone simply hides the text.
---
--- Set on EVERY update: rows are pooled, and a frame that was a player row
--- becomes a group row, which must not keep the player's zone.
---
--- SIZED TO ITS WORDS, up to ZONE_MAX_WIDTH: the playstyle hangs off its
--- right edge, so a fixed box would leave a gap after every short zone.
--- Clamped like the name, with LFGF.SetClampedText.
local function UpdateZone(row, isSolo, memberInfo)
	if not row.LFGFZone then
		row.LFGFZone = S.Text(row, 12, S.colors.muted)
		row.LFGFZone:SetPoint("BOTTOMLEFT", row.ActivityName, "BOTTOMRIGHT", 4, 0)
		row.LFGFZone:SetHeight(15)
		row.LFGFZone:SetWordWrap(false)
	end

	-- A nil test, never a comparison with another value: `== nil` is safe on
	-- a secret, but a comparison with anything else was never tried in the
	-- client (lfgforever-code-style.md, *Secret values*).
	local areaName = isSolo and memberInfo and memberInfo.areaName or nil
	if not areaName then
		row.LFGFZone:Hide()
		return
	end

	-- Same branch as the level above: put the separator in front when the
	-- value can be read, otherwise hand the raw secret to the setter and lose
	-- only the separator. It is the addon's one separator (LFGF.SEPARATOR), the
	-- same pipe the whisper log draws between its action links.
	--
	-- A secret zone has a secret width, so it is pinned to ZONE_MAX_WIDTH
	-- (LFGF.SetClampedText): unlike a name, nothing but the playstyle hangs off
	-- its right edge.
	local text = areaName
	if canaccessvalue(areaName) then
		if areaName == "" then
			row.LFGFZone:Hide()
			return
		end
		text = LFGF.SEPARATOR .. " " .. areaName
	end
	LFGF.SetClampedText(row.LFGFZone, text, ZONE_MAX_WIDTH, ZONE_MAX_WIDTH)
	row.LFGFZone:Show()
end

--- End the activity line with the listing's playstyle: "Deadmines | Westfall |
--- Relaxed" on a player row, "Deadmines | Relaxed" on a group row.
---
--- LfgSearchResultData.generalPlaystyle (LFGListInfoDocumentation.lua:1006),
--- an Enum.LFGEntryGeneralPlaystyle. Build 70170 made one required to post on
--- Blizzard's Listing tab (Blizzard_LFGVanilla_Listing.lua:487-488), and
--- Blizzard's Browse row shows it on a line of its own (Browse.lua:476-477).
--- The author chose the end of the activity line instead, so rows keep their
--- height; .claude/rules/playstyle-display.md has the decisions.
---
--- THE WORD IS BLIZZARD'S: GetGeneralPlaystyleString (Blizzard_LFGUtil/
--- Mainline/LFGUtil.lua:315, loaded at startup), so it is translated and
--- answers "" for None or a value it has no word for. In the activity and
--- zone colour, which ColourRow sets (grey, or the delisted grey): the
--- author's choice over Blizzard's green label (Browse.xml:257).
---
--- SECRET IN LOCKDOWN with the rest of the result, so it is read through
--- Readable: Blizzard's function compares its argument, and comparing a secret
--- from our code errors. Unreadable shows nothing.
---
--- Set and anchored on EVERY update: rows are pooled. Blizzard's own label is
--- set only when there is a value, so a reused row keeps the last listing's
--- word; this one hides instead.
local function UpdatePlaystyle(row, info)
	if not row.LFGFPlaystyle then
		row.LFGFPlaystyle = S.Text(row, 12, S.colors.muted)
		row.LFGFPlaystyle:SetHeight(15)
		row.LFGFPlaystyle:SetWordWrap(false)
	end
	local label = row.LFGFPlaystyle

	-- After the zone when it is shown, else after the activity. An anchor to a
	-- hidden region still resolves, so a fixed anchor would leave a gap.
	label:ClearAllPoints()
	local after = row.LFGFZone:IsShown() and row.LFGFZone or row.ActivityName
	label:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT", 4, 0)

	-- Test exactly what the guard answers (nil), never a type: a type check
	-- can hide a missing guard (patterns-taint.md).
	local playstyle = Readable(info.generalPlaystyle, nil)
	local word = playstyle ~= nil and GetGeneralPlaystyleString(playstyle) or ""
	if word == "" then
		label:Hide()
		return
	end

	label:SetFormattedText("%s %s", LFGF.SEPARATOR, word)
	label:Show()
end

-- Quests & Zones: a local of Blizzard's (Mainline/LFGVanilla_Constants.lua:12),
-- so copied.
local QUEST_CATEGORY_ID = 116

--- The INLINE NOTE: a Quests & Zones listing's details text (its comment,
--- LFGListInfoDocumentation.lua:986), which Blizzard's Create Listing makes
--- mandatory for that category, the only one with no activity to pick
--- (Blizzard_LFGVanilla_Listing.lua:886-903). Nil for any other listing, for
--- blank text, and when the comment cannot be read: it is secret in
--- chat-messaging lockdown (:397). The text comes back on one line, trimmed,
--- every run of spaces and line breaks one space.
--- .claude/rules/inline-note.md.
local function InlineNote(info)
	local comment = Readable(info.comment, nil)
	if comment == nil or not comment:find("%S") then
		return nil
	end
	local activityIDs = Readable(info.activityIDs, nil)
	local activity = activityIDs and activityIDs[1] and C_LFGList.GetActivityInfoTable(activityIDs[1])
	if not activity or activity.categoryID ~= QUEST_CATEGORY_ID then
		return nil
	end
	return (comment:match("^%s*(.-)%s*$"):gsub("%s+", " "))
end

--- Show the note under the activity line, after Blizzard's friends-list note
--- icon (Camelot/FriendsFrame.xml:863-868), or nothing. `note` is the one the
--- tree was built with (ListingNode), so the line and the row's height (the
--- extent calculator in LFGF.CreateListPanel) always agree.
---
--- Two corner anchors give the text its width, so the client cuts a long note
--- with "..." at the row's end; LEFT / RIGHT would pin the vertical centre
--- too (patterns-ui.md). Built once per pooled row, set on every update.
local function UpdateNote(row, note)
	if not row.LFGFNote then
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-Note")
		icon:SetSize(14, 12)
		icon:SetPoint("TOPLEFT", row.ActivityName, "BOTTOMLEFT", 0, -3)
		row.LFGFNoteIcon = icon

		local text = S.Text(row, 12, S.colors.muted)
		text:SetPoint("TOPLEFT", row.ActivityName, "BOTTOMLEFT", 16, -2)
		text:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 10)
		text:SetWordWrap(false)
		row.LFGFNote = text
	end
	row.LFGFNote:SetText(note or "")
	row.LFGFNote:SetShown(note ~= nil)
	row.LFGFNoteIcon:SetShown(note ~= nil)
end

--- Colour the row, and grey it when the listing has been withdrawn.
---
--- A listing can be delisted while it is on screen. Blizzard greys the row in
--- place rather than removing it (Browse.lua:440-449, :471-474) so the list does
--- not jump under the cursor.
---
--- NOT IMPLEMENTED, and deliberately: Blizzard's other two activity colours,
--- MATCH (BRIGHTBLUE) and SELF (LIGHTGREEN), plus the `matchesFilters` dimming
--- at Browse.lua:428-437. All three depend on the activity-filter comparison
--- this addon has not built yet; inventing a colour rule ahead of the feature
--- would be a lie about what the row is telling the player.
local function ColourRow(row, info, leaderInfo, isDelisted)
	local nameColor = S.colors.text
	if leaderInfo and not S.IsLight() then
		local class = LFGF.ClassColor(leaderInfo.classFilename)
		if class then nameColor = { class.r, class.g, class.b } end
	end
	local detailColor = S.colors.muted
	if isDelisted then nameColor = detailColor end

	-- Clamped, or a long leader name runs across the role icons on the right.
	-- Shorter by the relation icon's width when there is one, because the icon
	-- moved the name right by that much and the role icons did not move.
	--
	-- The setter accepts a secret, so the name renders even in lockdown. Its
	-- width is then secret too and is left alone (LFGF.SetClampedText): a long
	-- name may reach the role icons in lockdown, which beats a Lua error per
	-- row, and pinning it would push the level and the newcomer icon, which
	-- hang off the name's right edge, across the row for every short name.
	--
	-- Shorter by the newcomer icon and 1 too while it shows, as Blizzard's own
	-- clamp is (Browse.lua:481-491). Its width is read, as theirs is, and
	-- guarded: it hangs off the name, so in lockdown it can be secret.
	local maxWidth = row.NameMaxWidth - (row.lfgfRelationWidth or 0)
	if row.NewPlayerFriendlyIcon:IsShown() then
		local iconWidth = LFGF.ReadableNumbers(row.NewPlayerFriendlyIcon:GetWidth())
		if iconWidth then
			maxWidth = maxWidth - iconWidth - 1
		end
	end
	LFGF.SetClampedText(row.Name, info.leaderName, maxWidth)

	row.Name:SetTextColor(unpack(nameColor))
	row.Level:SetTextColor(unpack(detailColor))
	row.ActivityName:SetTextColor(unpack(detailColor))
	row.LFGFZone:SetTextColor(unpack(detailColor))
	row.LFGFPlaystyle:SetTextColor(unpack(detailColor))
	row.LFGFNote:SetTextColor(unpack(detailColor))
	row.LFGFNoteIcon:SetVertexColor(unpack(detailColor))

	-- Set on EVERY update, not only when delisted: rows are recycled, so a
	-- one-way rule would leave a row grey for good once any withdrawn listing
	-- had passed through it.
	row.ClassIcon:SetDesaturated(isDelisted)
	row.NewPlayerFriendlyIcon:SetDesaturated(isDelisted)
end

--- The rating a listing is marked and ordered by: the WORST (fewest stars) of
--- its leader and every member, the author's decision (2026-11-14,
--- .claude/rules/player-ratings.md): any 1-star member makes it 1, else any
--- 2-star 2, else any 3-star 3; members nobody rated do not count. Nil while
--- Player ratings is off or nobody in it is rated. A solo listing's one member
--- is its player.
---
--- The members come from GetSearchResultPlayerInfo(resultID, 1..numMembers),
--- as Blizzard's group tooltip reads them (Browse.lua:640-645), the leader
--- among them. The leader's name is read as well, for a listing whose member
--- data has not arrived (the fields are Nilable). Their names are
--- "Firstname Surname", the rating key's form
--- (probed in the client, 2026-11-14). Every member counts, a big raid
--- listing's too. All of it is secret in chat-messaging lockdown
--- (LFGListInfoDocumentation.lua:431): numMembers through Readable (unreadable,
--- the leader alone counts), and each name through LFGF.PlayerRatingFor, whose
--- key reads it through LFGF.Readable, so a hidden or missing name counts as
--- not rated.
local function ListingRating(resultID, info)
	if not LFGF.ShowPlayerRatings() then
		return nil
	end
	local worst = LFGF.PlayerRatingFor(info.leaderName)
	local count = Readable(info.numMembers, nil) or 0
	for index = 1, count do
		local member = C_LFGList.GetSearchResultPlayerInfo(resultID, index)
		local rating = member and LFGF.PlayerRatingFor(member.name)
		if rating ~= nil and (worst == nil or rating < worst) then
			worst = rating
		end
	end
	return worst
end

--- PLAYER RATINGS, PHASE 3: a 2 px strip in the rating's colour over the left
--- edge of the row's band, by ListingRating: a solo player by that player, a
--- group by its worst-rated member. Your own listing is never marked, by the
--- author's decision. Kept on a delisted row too: the rating is still true.
--- Built once per pooled frame, written on every update.
local function UpdateRatingStrip(row, resultID, info)
	if not LFGF.RatingsAvailable then return end
	if not row.LFGFRatingStrip then
		row.LFGFRatingStrip = LFGF.CreateRatingStrip(row)
	end
	local rating = nil
	if not row.hasSelf then
		rating = ListingRating(resultID, info)
	end
	LFGF.PaintRatingStrip(row.LFGFRatingStrip, rating)
end

local function UpdateRow(row, resultID, relation, note)
	local info = C_LFGList.GetSearchResultInfo(resultID)
	if not info then
		row:Hide()
		return
	end
	row:Show()
	row.resultID = resultID

	local isDelisted = Readable(info.isDelisted, false) == true

	-- ON THE ROW, not just in this scope, because the click handler needs them
	-- and it runs long after this returns. Blizzard keeps them the same way
	-- (Browse.lua:402-403).
	row.isDelisted = isDelisted
	row.hasSelf = Readable(info.hasSelf, false)

	-- numMembers is secret in lockdown, so "is this a solo listing" is a guess
	-- there. Defaulting to the GROUP presentation is the safer wrong answer:
	-- it shows a party icon instead of a class icon, rather than inventing a
	-- class and level for someone.
	local numMembers = Readable(info.numMembers, nil)
	local isSolo = numMembers ~= nil and numMembers <= 1

	local memberInfo = isSolo and C_LFGList.GetSearchResultPlayerInfo(resultID, 1) or nil

	LayOutRow(row, isSolo, memberInfo, relation)
	-- Before ColourRow, which colours the zone and playstyle text these create.
	-- The zone first: the playstyle hangs off it when it is shown.
	UpdateZone(row, isSolo, memberInfo)
	UpdatePlaystyle(row, info)
	UpdateNote(row, note)
	-- Before ColourRow too, whose name clamp makes room for it.
	row.NewPlayerFriendlyIcon:SetShown(Readable(info.newPlayerFriendly, false) == true)
	ColourRow(row, info, C_LFGList.GetSearchResultLeaderInfo(resultID), isDelisted)
	UpdateRatingStrip(row, resultID, info)

	-- activityIDs carries no NeverSecret either, but it is a TABLE of numbers
	-- rather than a secret scalar; guard it the same way and fall back to an
	-- empty list, which renders as a count of zero rather than erroring.
	local activityIDs = Readable(info.activityIDs, nil) or {}
	if #activityIDs == 1 then
		local activityInfo = C_LFGList.GetActivityInfoTable(activityIDs[1])
		row.ActivityName:SetText(activityInfo and LFGUtil_GetActivityInfoName(activityInfo) or "")
	else
		row.ActivityName:SetFormattedText(L.ACTIVITY_COUNT_FORMAT, #activityIDs)
	end

	EnsureRowButtons(row)
	UpdateInviteButton(row, info, isDelisted)
	UpdateAskToJoinButton(row, info, isDelisted, isSolo)

	-- Blizzard's own display updater. It is argument-driven and touches only
	-- the frame it is handed (Browse.lua:874), so reusing it couples nothing.
	-- The comment goes in as-is: it ends at a SetText (:916).
	local displayType, maxNumPlayers = LFGBrowseUtil_GetBestDisplayTypeForActivityIDs(activityIDs)
	LFGBrowseGroupDataDisplay_Update(row.DataDisplay, displayType, maxNumPlayers,
		C_LFGList.GetSearchResultMemberCounts(resultID),
		isDelisted, isSolo,
		memberInfo and Readable(memberInfo.lfgRoles, nil) or nil,
		info.comment, Readable(info.hasSelf, false))
end

-------------------------------------------------------
---------- Row tooltips
-------------------------------------------------------
-- Blizzard's own tooltip is REUSED rather than rebuilt. It is the whole listing
-- at a glance -- roles, every member, the comment, completed encounters -- and
-- reproducing it would be a few hundred lines that then drift from theirs.
--
-- What is added is the guard their own OnEnter lacks. Two of them:
--
--   1. THE LISTING MAY BE GONE. LFGBrowseSearchEntryTooltip_UpdateAndShow
--      indexes the search result with no nil check (Browse.lua:573-574), so
--      hovering a row whose listing was delisted between render and hover
--      throws inside Blizzard's file. This is the crash that was reported.
--
--   2. THE DATA MAY BE SECRET. That builder compares and formats fields that
--      are secret in chat-messaging lockdown -- `searchResultInfo.comment ~= ""`
--      and string.format on it (:679-680), LEVEL_ABBR .. leaderInfo.level
--      (:620), RAID_CLASS_COLORS[classFilename] (:616). All legal for
--      Blizzard's untainted code, none of it legal from ours.
--
-- One accessibility check answers for the whole structure, because
-- SecretInChatMessagingLockdown is a per-FUNCTION flag: it makes the entire
-- return secret, and the only per-field opt-out is NeverSecret, which
-- LfgSearchResultData grants to partyGUID alone. So testing one field settles
-- the rest.

-- Browse.xml:348-353 -- the inset the tooltip's own Comment uses
-- (LEFT x=11 / RIGHT x=-11), so this is Blizzard's number rather than a chosen
-- one, and it is what "inside the border" means for this frame.
local TOOLTIP_CONTENT_INSET = 11

--- Widen Blizzard's tooltip until nothing in a member row hangs over its edge.
---
--- A GUARD ON BLIZZARD'S BUILDER, which we inherit by displaying their
--- tooltip. LFGBrowseSearchEntryTooltip_UpdateAndShow sizes it as
---     self:SetWidth(math.max(maxContentWidth+22, LFGBROWSE_TOOLTIP_MIN_WIDTH))
--- (Browse.lua:834), and maxContentWidth counts the member rows -- the widest
--- name, then level, role icons and the crown (:562-570, :662-675) -- as well
--- as the activity and encounter strings (:742, :763, :788). So in the client
--- this normally finds nothing to widen. The member row still has no right
--- anchor to save it if that sum ever comes up short: Name is maxLines="1" on
--- a single TOPLEFT (Browse.xml:277), then Level at +4 and a 16px role icon at
--- +4, none of them clipped, so they would draw over the right border. Why it
--- was written, and the open question of keeping it:
--- .claude/rules/blizzard-source-citations.md.
---
--- MEASURED, NOT RE-DERIVED. Reproducing Blizzard's arithmetic from the XML --
--- inset, crown width, name, +4, level, +4, 16 per role -- would have to track
--- their constants. Asking the laid-out frames where they actually ended up is
--- shorter and cannot be wrong about font metrics, about those gap constants,
--- or about a later change to that XML.
---
--- ONE PASS IS ENOUGH, and that is a property of the anchoring rather than
--- luck: every row hangs off the tooltip's LEFT edge, so widening moves the
--- right border away from content that does not move with it.
---
--- Nothing leaks into Blizzard's own Group Finder: their builder recomputes
--- SetWidth from scratch on every hover (:834), so a tooltip we widened is
--- resized by them before they next show it.
local function WidenTooltipToFitRows(tooltip)
	local limit = tooltip:GetRight()
	-- nil for a frame whose rect cannot be resolved, and GetRight carries
	-- SecretWhenAnchoringSecret. Either way: leave it as Blizzard sized it.
	if limit == nil or not canaccessvalue(limit) then
		return
	end
	limit = limit - TOOLTIP_CONTENT_INSET

	local overflow = 0

	local function Consider(region)
		if not region or not region:IsShown() then
			return
		end
		local right = region:GetRight()
		if right == nil or not canaccessvalue(right) then
			return
		end
		if right - limit > overflow then
			overflow = right - limit
		end
	end

	--- Name, level and every role icon -- not just the icons. A row whose roles
	--- are all hidden still has a name that can overrun.
	local function ConsiderRow(row)
		if not row or not row:IsShown() then
			return
		end
		Consider(row.Name)
		Consider(row.Level)
		for _, icon in ipairs(row.Roles or {}) do
			Consider(icon)
		end
	end

	ConsiderRow(tooltip.Leader)
	if tooltip.memberPool then
		for row in tooltip.memberPool:EnumerateActive() do
			ConsiderRow(row)
		end
	end

	-- WIDEN ONLY. maxContentWidth is Blizzard's answer and is the right one
	-- whenever it is the larger; shrinking to the names would cut the activity
	-- list off instead.
	if overflow > 0 then
		tooltip:SetWidth(tooltip:GetWidth() + overflow)
	end
end

local function HideRowTooltip()
	if LFGBrowseSearchEntryTooltip then
		LFGBrowseSearchEntryTooltip:Hide()
	end
	GameTooltip:Hide()
end

local function ShowRowTooltip(row)
	local info = C_LFGList.GetSearchResultInfo(row.resultID)
	if not info then
		return
	end

	if LFGBrowseSearchEntryTooltip and canaccessvalue(info.comment) then
		LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, row.resultID)
		-- Anchored as Blizzard anchors it (Browse.lua:530).
		LFGBrowseSearchEntryTooltip:SetPoint("TOPLEFT", row, "TOPRIGHT", 8, 38)
		-- After BOTH, because it measures a laid-out frame.
		WidenTooltipToFitRows(LFGBrowseSearchEntryTooltip)
		return
	end

	-- Fallback: the listing exists but its data cannot be read here. Show what
	-- a SETTER accepts -- leaderName goes in unexamined -- rather than showing
	-- nothing at all.
	--
	-- Unless there is no name: leaderName is Nilable
	-- (LFGListInfoDocumentation.lua:982) and the tooltip's SetText refuses nil
	-- (FrameAPITooltipDocumentation.lua, SetText). This is the path where the
	-- name can be secret, so the nil test goes behind canaccessvalue, the
	-- guard every read takes; `== nil` alone would not error on a secret
	-- either (lfgforever-code-style.md, *Secret values*). A secret name is not
	-- nil, so it is shown as before.
	local leaderName = info.leaderName
	if canaccessvalue(leaderName) and leaderName == nil then
		return
	end
	LFGF.ShowTextTooltip(row, leaderName)
end

-------------------------------------------------------
---------- The right-click menu
-------------------------------------------------------

--- Open Blizzard's own search-entry menu on one of our rows.
---
--- THEIR MENU, NOT ONE OF OURS. LFGBrowseMixin:CreateSearchEntryMenu reads only
--- searchEntry.resultID (Browse.lua:1002-1034), so a row of ours satisfies it --
--- and it brings the four actions with it: Send Message, Group Invite with its
--- eligibility rules (:1456-1472), Report Group and Report Advertisement
--- (:1495-1509), each with Blizzard's own localised label. Rebuilding that
--- would be a menu that has to be kept in step with theirs forever.
---
--- TWO THINGS THAT LOOK LIKE PROBLEMS AND ARE NOT, both checked:
---
---   * The menu opens at the CURSOR, not at the owner region --
---     InputUtil.AnchorRegionToCursor (Menu.lua:2602), and their comment at
---     :2581-2583 says so outright. The owner only decides when the menu
---     auto-closes.
---   * The owner they pass, LFGBrowseFrame.SearchEntryDropDown, is NIL -- the
---     name appears once in their whole addon, at that call site, and is never
---     assigned. MenuUtil substitutes GetAppropriateTopLevelParent()
---     (MenuUtil.lua:152-154). That matters: a real frame there would have been
---     on a window this one replaces and closes, and the menu polls
---     ownerRegion:IsVisible() and closes itself when that goes false
---     (Menu.lua:2504-2511).
---
--- THE COST, stated rather than hidden: the menu is built in OUR tainted stack,
--- and their SetEnabled checks only that leaderName is non-nil (:961), not that
--- it is READABLE. So in chat-messaging lockdown -- a dungeon, a raid, a
--- restricted map -- clicking Send Message (which string.formats the name,
--- ChatFrameUtil.lua:374) or Group Invite (SecretArguments =
--- "AllowedWhenUntainted") will error. Building our own menu was the only way
--- to disable those two, and it was not worth a parallel menu to do it. If it
--- proves annoying, a canaccessvalue guard here that refuses to open is the
--- smaller fix.
local function ShowRowMenu(row)
	-- CreateSearchEntryMenu is a method on LFGBrowseFrame, which lives in the
	-- LoadOnDemand Group Finder.
	--
	-- UNREACHABLE BY CONSTRUCTION, and kept anyway: a row can only exist if
	-- LFGBrowseSearchEntryTemplate did, and that template is in the same addon
	-- -- so by the time anything can be right-clicked, LFGBrowseFrame is there.
	-- Removing it fails no example, and that is said here rather than left for
	-- someone to discover. It stays because "every LFG frame access is behind
	-- an IsAddOnLoaded guard" is a rule worth being boring about, and because
	-- the day the list stops using their row template is the day this stops
	-- being dead.
	if not C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder_VanillaStyle") then
		return
	end

	-- No nil-result guard here on purpose: theirs does it (Browse.lua:1004-1006),
	-- unlike their tooltip builder, which is why that one needed wrapping.
	LFGBrowseFrame:CreateSearchEntryMenu(row)
end

--- Take Blizzard's wiring off a row we borrowed the template from.
---
--- The template declares FIVE scripts (Mainline/Blizzard_LFGVanilla_Browse.xml)
--- and every runtime one reaches into LFGBrowseFrame or its globals:
---
---   OnLoad   registers LFG_LIST_SEARCH_RESULT_UPDATED   (Browse.lua:500-503)
---   OnEvent  -> LFGBrowseFrame:ValidateSelection()       (:505-513)
---   OnClick  -> LFGBrowseFrame.selectionBehavior         (:515-526)
---   OnEnter  -> LFGBrowseSearchEntryTooltip_UpdateAndShow(:528-535)
---   OnLeave  -> LFGBrowseSearchEntryTooltip:Hide()       (:537-540)
---
--- Missing one is not cosmetic. Leaving OnEnter attached shipped this, reported
--- from the client:
---
---   Browse.lua:544: attempt to index local 'searchResultInfo' (a nil value)
---     in function 'LFGBrowseSearchEntryTooltip_UpdateAndShow'
---     in function <Browse.lua:508>          <- LFGBrowseSearchEntry_OnEnter
---
--- That builder reads the search result WITHOUT a nil guard (:574), so hovering
--- a row whose listing has since been delisted crashes inside Blizzard's file,
--- blaming their code for our wiring.
---
--- OnLoad cannot be replaced -- it has already run by the time the frame
--- exists -- so its effect is undone instead: UnregisterAllEvents. Clearing
--- OnEvent alone would leave the row subscribed to an event it can do nothing
--- with. The redraw that pair did IS still wanted, so the panel does it
--- instead: see panel:UpdateResult.
local function DetachBlizzardScripts(row)
	if row.lfgfDetached then
		return
	end
	row.lfgfDetached = true
	LFGF.ThemeFont(row.Name, 15, "text")
	LFGF.ThemeFont(row.Level, 12, "muted")
	LFGF.ThemeFont(row.ActivityName, 12, "muted")
	if row.Background and row.Background.SetColorTexture then row.Background:SetColorTexture(unpack(S.colors.raised)) end
	if row.Highlight then
		row.Highlight:SetColorTexture(unpack(S.colors.hover))
		row.Highlight:SetBlendMode("BLEND")
	end

	-- Undoes OnLoad. Clearing OnEvent alone would leave the row subscribed to
	-- LFG_LIST_SEARCH_RESULT_UPDATED with nothing to answer it.
	row:UnregisterAllEvents()
	row:SetScript("OnEvent", nil)

	-- Theirs drives LFGBrowseFrame's selection (Browse.lua:522), which is their
	-- window's state. Ours opens their MENU and nothing else -- see
	-- ShowRowMenu, and note left-click still has no behaviour of ours.
	row:SetScript("OnClick", function(self, button)
		-- Browse.lua:516-518, kept verbatim in effect. A delisted listing is
		-- already gone, and without the hasSelf half the player is offered the
		-- chance to whisper and invite themselves.
		if self.isDelisted or self.hasSelf then
			return
		end

		-- Only the right button. Blizzard play this sound for both because
		-- their left button selects; ours does nothing yet, and a sound for
		-- nothing happening is a lie.
		if button ~= "RightButton" then
			return
		end

		LFGF.PlayClick()
		ShowRowMenu(self)
	end)

	-- OnEnter/OnLeave are REPLACED rather than cleared: Blizzard's versions
	-- drove the hover highlight as well as the tooltip (Browse.lua:532-534,
	-- :539), and both halves are wanted -- just not unguarded. Assigning over
	-- them is what detaches them; there is no need to nil them first.
	--
	-- The highlight half is not optional: Highlight sits in the HIGHLIGHT
	-- layer but is hidden="true" (Browse.xml:224), so the engine's hover
	-- display does not show it on its own. Drop the Show() below and the row
	-- never highlights.
	row:SetScript("OnEnter", function(self)
		if not self.Selected:IsShown() then
			self.Highlight:Show()
		end
		ShowRowTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.Highlight:Hide()
		HideRowTooltip()
	end)
end

-------------------------------------------------------
---------- The role filters
-------------------------------------------------------
-- TWO FILTERS, ONE PER KIND OF LISTING, and they ask OPPOSITE questions:
--
--   a PLAYER is kept when they OFFER ANY ticked role AND are of a ticked CLASS
--   a GROUP  is kept when it satisfies EVERY criterion the player ticked
--
-- Different questions, different combinators, different APIs -- a player's own
-- lfgRoles against a group's member tally. OR for players because the three
-- roles are one person's choices and any of them is a match; AND for groups
-- because each criterion narrows what the last one left, which is what lets
-- "no tank yet, and short of damage, and already has a healer" be asked at all.
--
-- Their defaults differ for the same reason: every player role on means "show
-- everyone", while every group box on would be a contradiction, so that
-- section starts empty.
--
-- The GROUP half comes first below, then the player half.
--
-- THE FIELD IS memberInfo.lfgRoles, from
-- C_LFGList.GetSearchResultPlayerInfo(resultID, 1). lfgRoles is an LFGRoles
-- structure -- {tank, healer, dps}, all bool -- and it is the roles the player
-- SIGNED UP for, which is exactly what Blizzard's own solo display reads
-- (Browse.lua:392 passes memberInfo.lfgRoles through as soloRoles, :931 reads
-- soloRoles.tank / .healer / .dps).
--
-- NOT assignedRole. It sits on the same structure and reads like the simpler
-- answer, but it is a secret-capable cstring, and `assignedRole == "TANK"` is a
-- COMPARISON -- one of the three operations that error on a secret. A bool
-- cannot have that problem, which is the general lesson for filtering this data
-- rather than a detail of this filter.
--
-- THE THREE ROLES ARE INDEPENDENT BOOLS, not one choice: a tank who also signed
-- up as dps is still a tank. So a listing matches if it offers ANY checked
-- role.
--
-- NO ROLE CHECKED MEANS NO CONSTRAINT, matching the activity dropdown in the
-- filter panel, where an empty selection means "all activities"
-- (core/filterpanel.lua RequestSearch). An empty filter never hides anything.
--
-- IT FAILS OPEN: a listing whose roles cannot be read is SHOWN. lfgRoles
-- carries no NeverSecret, so it is unreadable in a dungeon or raid, and hiding
-- what you could not verify would silently shrink the list there and read as
-- the server having stopped answering.

--- The five group criteria, in the order they are shown.
---
--- `counts` is the key into the {TANK, HEALER, DAMAGER} tally that
--- GetSearchResultMemberCounts returns -- note it is DAMAGER where the player
--- filter's LFGRoles field is `dps`.
---
--- `enough` is Blizzard's own idea of a full dungeon party:
--- LFGBROWSE_DUNGEON_NUM_TANKS_EXPECTED = 1, _HEALERS_EXPECTED = 1,
--- _DPS_EXPECTED = 3 (Browse.lua:27-29). Those are file-locals, restated here
--- rather than read.
---
--- `covered` is which way the test runs, and it is the whole difference
--- between the two rows:
---   false -- "<role> role available": the group is SHORT of that role
---   true  -- "Has <role>":            it already has enough
local GROUP_CRITERIA = {
	{ field = "tankAvailable",   counts = "TANK",    enough = 1, covered = false },
	{ field = "healerAvailable", counts = "HEALER",  enough = 1, covered = false },
	{ field = "damageAvailable", counts = "DAMAGER", enough = 3, covered = false },
	{ field = "hasTank",         counts = "TANK",    enough = 1, covered = true },
	{ field = "hasHealer",       counts = "HEALER",  enough = 1, covered = true },
}

--- Does this GROUP satisfy every criterion the player checked?
---
--- THEY AND TOGETHER. Each checked rule narrows what the one before it left,
--- and the first that fails drops the listing. That makes some combinations
--- deliberately empty -- "Tank role available" with "Has tank" cannot both
--- hold -- which is left possible rather than prevented: a control that
--- silently refused a click would be harder to explain than an empty list.
---
--- Nothing checked means no constraint, which is also the default. Unlike the
--- player filter, this section starts with every box OFF, because "all on"
--- here would be that same contradiction.
---
--- THE SOURCE IS GetSearchResultMemberCounts, the tally Blizzard's own
--- RoleCount display reads (Browse.lua:941-943). It is PRESENT in the client
--- dump but UNDOCUMENTED (0 documentation entries, 8 Blizzard call sites), so
--- whether it can return a secret is genuinely unknown. Guarded on that basis
--- and failing open -- per criterion, so one unreadable count does not decide
--- the rest.
local function GroupMatchesFilters(resultID, criteria)
	if not criteria then
		return true
	end

	local anyChecked = false
	for _, rule in ipairs(GROUP_CRITERIA) do
		if criteria[rule.field] then
			anyChecked = true
			break
		end
	end
	if not anyChecked then
		return true
	end

	-- Guard the TABLE before reading a field off it: indexing a secret errors.
	local counts = Readable(C_LFGList.GetSearchResultMemberCounts(resultID), nil)
	if not counts then
		return true
	end

	for _, rule in ipairs(GROUP_CRITERIA) do
		if criteria[rule.field] then
			local have = Readable(counts[rule.counts], nil)
			if have ~= nil then
				local isCovered = have >= rule.enough
				if isCovered ~= rule.covered then
					return false
				end
			end
		end
	end

	return true
end

--- Does this GROUP have no player of a class the class filter hides by?
---
--- `hidden` is the set LFGF.GroupClassesToHide answers second (core/main.lua),
--- read once per tree: nil while nothing is hidden, since no class selected
--- and every class selected both mean no filter.
---
--- Each member's class, read the way Blizzard's camelot group tooltip reads
--- it: GetSearchResultPlayerInfo(resultID, i) for every member
--- (Blizzard_LFGVanilla_Browse.lua:640-645). GetSearchResultMemberCounts
--- carries class counts only in Blizzard's retail code (LFGList.lua:3211),
--- which camelot's never reads, so it is not relied on. Nothing is read
--- while the filter narrows nothing.
---
--- FAILS OPEN, member by member, by the author's decision: a member whose
--- data has not arrived, or whose class cannot be read, never hides a group;
--- only a member known to be of a hidden class does. Class data that arrives
--- after the search waits for the next one: a row update only redraws.
---
--- The class is read through Readable BEFORE it is used as a table key, which
--- errors on a secret in the client. The harness cannot falsify the guard (a
--- lookup by a mock secret is simply nil), as with AddPlayerKey's; in
--- lockdown numMembers is secret too, and such a listing never reaches here.
local function GroupMatchesClassFilter(resultID, numMembers, hidden)
	if not hidden then
		return true
	end
	for index = 1, numMembers do
		local memberInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, index)
		local classFilename = memberInfo and Readable(memberInfo.classFilename, nil)
		if classFilename ~= nil and hidden[classFilename] then
			return false
		end
	end
	return true
end

--- Is this solo listing's class one the player asked for?
---
--- The second dimension of the player filter, ANDed with the roles: "Tank" plus
--- "Warrior" means warriors offering tank.
---
--- classFilename carries no NeverSecret, and this uses it AS A TABLE KEY --
--- one of the operations that errors on a secret. Plain Lua does not notice: a
--- lookup by a secret key fires no metamethod and quietly returns nil, so an
--- unguarded version would read as "class not selected" and silently hide every
--- player in a dungeon or raid. Guarded, and failing open.
local function SoloMatchesClassFilter(resultID, classes)
	if not classes then
		return true
	end

	local anyChecked = false
	for _, checked in pairs(classes) do
		if checked then
			anyChecked = true
			break
		end
	end
	if not anyChecked then
		return true
	end

	local memberInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
	if not memberInfo then
		return true
	end

	local classFilename = Readable(memberInfo.classFilename, nil)
	if not classFilename then
		return true
	end

	return classes[classFilename] == true
end

--- Is this solo listing's player inside the level range the player asked for?
---
--- The third dimension of the player filter, ANDed with roles and classes. The
--- author's rules: 0 on either side is NO LIMIT on that side (an empty box in
--- the filter panel reads as 0), and both ends are inclusive.
---
--- memberInfo.level is Nilable (LFGListInfoDocumentation.lua:1019) and, like
--- every field of LfgSearchResultPlayerInfo, secret in chat-messaging lockdown
--- (:431) -- a dungeon or raid, out of combat too, so CLAUDE.md's out-of-combat
--- assumption does not cover it. Comparing a secret errors, so it is read
--- through Readable, and a level that is missing or unreadable keeps the
--- player: FAILS OPEN, as the role and class filters do.
local function SoloMatchesLevelFilter(resultID, levels)
	if not levels then
		return true
	end
	local minLevel = levels.min or 0
	local maxLevel = levels.max or 0
	if minLevel <= 0 and maxLevel <= 0 then
		return true
	end

	local memberInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
	if not memberInfo then
		return true
	end

	local level = Readable(memberInfo.level, nil)
	if level == nil then
		return true
	end

	if minLevel > 0 and level < minLevel then
		return false
	end
	if maxLevel > 0 and level > maxLevel then
		return false
	end
	return true
end

--- Does this solo listing offer any of the roles the player asked for?
---
--- roleFilter is nil until a search of ours announces one, and nil means no
--- constraint -- the list exists before any search, and results can arrive for
--- a search this addon did not start.
local function SoloMatchesRoleFilter(resultID, roleFilter)
	if not roleFilter then
		return true
	end
	if not (roleFilter.tank or roleFilter.healer or roleFilter.dps) then
		return true
	end

	local memberInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
	if not memberInfo then
		return true
	end

	-- Guard the TABLE before reading a field off it: indexing a secret errors.
	local roles = Readable(memberInfo.lfgRoles, nil)
	if not roles then
		return true
	end

	return (roleFilter.tank and Readable(roles.tank, false) == true)
		or (roleFilter.healer and Readable(roles.healer, false) == true)
		or (roleFilter.dps and Readable(roles.dps, false) == true)
end

--- Is this listing's playstyle one the player ticked? The Playstyle
--- dropdown in the filter panel's Miscellaneous section
--- (core/filterpanel_miscellaneous.lua); .claude/rules/playstyle-filter.md
--- has the author's rules, which this follows in order:
---
---   * it narrows PLAYERS AND GROUPS: both carry generalPlaystyle and both
---     show it on their row (UpdatePlaystyle). The caller keeps your own
---     listing out of it, as from every filter;
---   * NOTHING TICKED IS NO FILTER, like the class boxes, and neither is
---     everything ticked;
---   * a listing whose playstyle cannot be read is KEPT -- generalPlaystyle is
---     secret in chat-messaging lockdown with the rest of the result
---     (LFGListInfoDocumentation.lua:397, :1006), a dungeon or raid out of
---     combat too, so CLAUDE.md's out-of-combat assumption does not cover it;
---   * a listing with NO playstyle is KEPT: None, missing, or a value
---     Blizzard has no word for. "No playstyle" is exactly what
---     GetGeneralPlaystyleString answers "" for, so a row that shows none
---     (UpdatePlaystyle) is never hidden by this filter.
---
--- Blizzard's retail Group Finder filters the same way, in the client
--- (Blizzard_GroupFinder/Mainline/LFGList.lua:3239-3246): camelot's search
--- sends no server-side filter (Blizzard_LFGVanilla_Browse.lua:340-345).
---
--- READ THROUGH Readable, and tested for exactly what it answers (nil):
--- GetGeneralPlaystyleString compares its argument, which errors on a secret
--- from addon code (patterns-taint.md).
local function MatchesPlaystyleFilter(info, playstyles)
	if not playstyles then
		return true
	end

	local ticked = 0
	for _, playstyle in ipairs(LFGF.PLAYSTYLES) do
		if playstyles[playstyle.key] then
			ticked = ticked + 1
		end
	end
	if ticked == 0 or ticked == #LFGF.PLAYSTYLES then
		return true
	end

	local value = Readable(info.generalPlaystyle, nil)
	if value == nil or GetGeneralPlaystyleString(value) == "" then
		return true
	end

	for _, playstyle in ipairs(LFGF.PLAYSTYLES) do
		if playstyle.value == value then
			return playstyles[playstyle.key] == true
		end
	end
	-- A playstyle Blizzard has a word for but the dropdown does not offer
	-- (none today: GetGeneralPlaystyleString names exactly the four). With
	-- some ticked, it is not one of them.
	return false
end

--- Paint a divider's +/- from its node.
---
--- Browse.xml:279-288 ships the template with CollapseIcon shown ("-") and
--- ExpandIcon hidden ("+"), i.e. already right for an EXPANDED box. That is why
--- painting these only inside OnClick looked fine for so long: every box was
--- built expanded. The moment collapse state survives a refresh, a restored
--- box renders its rows hidden under a "-".
---
--- Called from the INITIALIZER, so it runs every time a divider is built --
--- which includes the click path, because Rerender re-initializes. One painter,
--- and no second copy to fall out of step.
local function PaintDividerIcons(divider, collapsed)
	divider.ExpandIcon:SetShown(collapsed)
	divider.CollapseIcon:SetShown(not collapsed)
end

--- What a click on a box's header does, as its tooltip: "Collapse groups",
--- "Expand players". One key per sentence, so a language pack never has to
--- build one from "Collapse" and "groups".
local function DividerTooltip(dividerType, collapsed)
	if dividerType == DIVIDER_SOLO then
		return collapsed and L.LIST_EXPAND_PLAYERS or L.LIST_COLLAPSE_PLAYERS
	end
	return collapsed and L.LIST_EXPAND_GROUPS or L.LIST_COLLAPSE_GROUPS
end

-------------------------------------------------------
---------- Building the tree
-------------------------------------------------------

--- NEWEST FIRST, by the author's decision (2026-10-12): the smaller age first.
--- age is seconds since the listing was created (camelot's own sort keeps "the
--- older one" first with the larger age, Blizzard_LFGVanilla_Browse.lua), and
--- every listing ages at the same rate, so two listings never swap between
--- searches: a new one arrives on top. Then partyGUID, the one field that is
--- never secret (LFGListInfoDocumentation.lua), then the server's order.
---
--- In chat-messaging lockdown age is secret (Readable answers nil), so
--- partyGUID orders alone. A readable age goes before an unreadable one, which
--- keeps this a consistent order whatever mix one search hands over --
--- table.sort errors on an inconsistent comparison. .claude/rules/list-order.md.
local function NewestFirst(a, b)
	if (a.age == nil) ~= (b.age == nil) then
		return a.age ~= nil
	end
	if a.age ~= b.age then
		return a.age < b.age
	end
	if a.guid ~= b.guid then
		return a.guid < b.guid
	end
	return a.index < b.index
end

--- One listing's tree node, with the keys NewestFirst reads, taken once.
local function ListingNode(resultID, info, index, relation)
	-- Readable alone, no type test: a secret age is still a number in the
	-- client, so a type test would let a missing guard through in the harness
	-- (.claude/context/patterns-taint.md). partyGUID is never secret, but is
	-- compared as a string, so anything else reads as "".
	local guid = Readable(info.partyGUID, "")
	return {
		resultID = resultID,
		relation = relation,
		-- Read once a search, so a row's line and its height never disagree.
		note = InlineNote(info),
		age = Readable(info.age, nil),
		guid = type(guid) == "string" and guid or "",
		index = index,
	}
end

-------------------------------------------------------
---------- Sort players by: the Players box's order
-------------------------------------------------------
-- The setting (core/settings.lua) orders the PLAYERS box only, inside each of
-- its parts (PARTS, below). The Groups box and the unboxed lockdown list stay
-- NewestFirst. Every order below puts a readable key before an unreadable
-- one, as NewestFirst does, so the comparison stays consistent whatever one
-- search hands over, and breaks ties NewestFirst.
-- .claude/rules/player-sort-order.md

--- The longest-listed first: the larger age first, the same tie-breaks.
local function OldestFirst(a, b)
	if (a.age == nil) ~= (b.age == nil) then
		return a.age ~= nil
	end
	if a.age ~= b.age then
		return a.age > b.age
	end
	if a.guid ~= b.guid then
		return a.guid < b.guid
	end
	return a.index < b.index
end

--- Highest or lowest level first, a known level before an unknown one.
local function ByLevel(highestFirst)
	return function(a, b)
		if (a.level == nil) ~= (b.level == nil) then
			return a.level ~= nil
		end
		if a.level ~= b.level then
			if highestFirst then
				return a.level > b.level
			end
			return a.level < b.level
		end
		return NewestFirst(a, b)
	end
end

--- The classes in the class filter's order, a known class before an unknown one.
local function ByClass(a, b)
	if (a.classRank == nil) ~= (b.classRank == nil) then
		return a.classRank ~= nil
	end
	if a.classRank ~= b.classRank then
		return a.classRank < b.classRank
	end
	return NewestFirst(a, b)
end

-- Keyed by LFGF.PLAYER_SORT_ORDERS (core/main.lua).
local PLAYER_ORDERS = {
	newest = NewestFirst,
	oldest = OldestFirst,
	levelHigh = ByLevel(true),
	levelLow = ByLevel(false),
	class = ByClass,
}

--- Each class token's place in CLASS_SORT_ORDER (Camelot/Constants.lua:1-11),
--- the list the class filter's boxes are built from (core/filterpanel.lua,
--- BuildClassRows), read for each tree so the two cannot disagree.
local function ClassRanks()
	local ranks = {}
	for rank, classFilename in ipairs(CLASS_SORT_ORDER) do
		ranks[classFilename] = rank
	end
	return ranks
end

--- Add the key a level or class order reads to a solo listing's node. Only
--- those orders read the player, so the others cost no call.
---
--- level and classFilename are secret in chat-messaging lockdown
--- (LFGListInfoDocumentation.lua:431), a dungeon or raid out of combat too,
--- so CLAUDE.md's out-of-combat assumption does not cover them: Readable
--- first, and an unreadable one is unknown. The class is guarded BEFORE it is
--- used as a table key, which errors on a secret in the client while plain
--- Lua quietly answers nil (see SoloMatchesClassFilter).
local function AddPlayerKey(node, order, classRanks)
	if order ~= "levelHigh" and order ~= "levelLow" and order ~= "class" then
		return
	end
	local memberInfo = C_LFGList.GetSearchResultPlayerInfo(node.resultID, 1)
	if not memberInfo then
		return
	end
	if order == "class" then
		local classFilename = Readable(memberInfo.classFilename, nil)
		node.classRank = classFilename ~= nil and classRanks[classFilename] or nil
	else
		node.level = Readable(memberInfo.level, nil)
	end
end

-------------------------------------------------------
---------- The parts of a box
-------------------------------------------------------
-- Each box is filled part by part, top to bottom: your own listing, friends,
-- 3-star players, guild members, everyone else (2-star players stay here),
-- then 1-star players. The same in both boxes, a group by its leader. With
-- Player ratings off nobody is rated, so it is your listing, friends, guild,
-- the rest. .claude/rules/player-ratings.md
local PARTS = { "mine", "friends", "threeStars", "guild", "rest", "oneStar" }

local function NewBucket()
	local bucket = {}
	for _, part in ipairs(PARTS) do
		bucket[part] = {}
	end
	return bucket
end

--- The part a listing that is not your own goes in, from the relation the
--- search decided and the leader's rating (nil while Player ratings is off,
--- or when the name cannot be read). A 1-star player goes last whoever they
--- are; a friend comes first otherwise; a 3-star player comes before guild
--- members, a 3-star guild member with them.
local function PartFor(relation, rating)
	if rating == 1 then
		return "oneStar"
	elseif relation == LFGF.RELATION_FRIEND then
		return "friends"
	elseif rating == 3 then
		return "threeStars"
	elseif relation == LFGF.RELATION_GUILD then
		return "guild"
	end
	return "rest"
end

--- Build the tree: one Groups box, then one Players box.
---
--- TWO DIVERGENCES FROM BLIZZARD, both deliberate.
---
--- 1. Blizzard opens a new subtree whenever the category CHANGES as it walks
---    the results (Browse.lua:216-218), so an interleaved response produces
---    Groups / Players / Groups -- several boxes of the same kind. This
---    PARTITIONS first, so there is exactly one box per kind however the
---    results arrive, and collapsing Groups takes every group with it.
---
--- 2. Groups come first, regardless of the order the server sent.
---
--- YOUR OWN LISTING HEADS ITS BOX. That one is Blizzard's, and it is the FIRST
--- comparison their sorter makes -- ahead of matching activity, ahead of the
--- solo/group split:
---
---     if (hasSelf1 ~= hasSelf2) then
---         return hasSelf1; -- Always put self at the top.
---     end
--- Browse.lua:1356-1358
---
--- This panel partitions rather than sorts, so the rule lands as "first WITHIN
--- its box": your solo listing heads Players, your group heads Groups. It also
--- stays exempt from the filters, as it was before it was pinned -- a listing
--- of your own that the filters hide is a player wondering where their own post
--- went.
---
--- The third case is ours alone: when numMembers cannot be read the listing
--- belongs to neither bucket, so it goes at the root, unboxed. See the secret
--- discussion at the top of this file -- one flat list beats a wrong split.
--- THAT BEATS hasSelf, because pinning needs to know WHICH box to pin to, and
--- in chat-messaging lockdown there is no way to ask.
---
--- THEN FRIENDS, 3-STAR PLAYERS, GUILD MEMBERS, EVERYONE ELSE AND 1-STAR
--- PLAYERS (PARTS, above), by a solo player or a group's leader: who the player
--- knows (core/relations.lua) and how they rated them (core/main.lua). It
--- orders and never exempts -- unlike your own listing, a guildmate the
--- filters exclude stays excluded.
---
--- EACH PART IS NEWEST FIRST (NewestFirst, below), and so is the unboxed list,
--- so the order holds from one search to the next instead of following the
--- server's -- except the Players box's parts, which follow "Sort players by"
--- (PLAYER_ORDERS above; newest first unless the player chose otherwise).
---
--- THE RELATION IS DECIDED HERE, ONCE PER SEARCH, and stored on the node, so the
--- icon UpdateRow draws and the place this gives it are one answer and cannot
--- disagree. One lookup per search: it scans the Battle.net friends once, and
--- it is thrown away with the tree. Nothing listens for the roster or the
--- friend list changing, by decision -- the next search sees the change. The
--- rating is read here too, once per search: a rating saved or cleared later
--- changes the strip at once (RemarkRows) and the place on the next search.
local function BuildDataProvider(results, filters, collapsedByDivider)
	-- Per bucket, one list per part (PARTS).
	local groups = NewBucket()
	local solos = NewBucket()
	local unsorted = {}
	local lookup = LFGF.NewRelationLookup()
	-- The one filter that narrows both boxes (MatchesPlaystyleFilter).
	local playstyles = filters and filters.playstyles
	-- The Groups section's class filter: the classes it hides groups by, as a
	-- set, or nil while it hides nothing.
	local _, hiddenClasses = LFGF.GroupClassesToHide(filters and filters.groupExcludedClasses)
	-- Read once per tree: "Sort players by", and the class ranks it may need.
	local playerOrder = LFGF.PlayerSortOrder()
	local classRanks = playerOrder == "class" and ClassRanks() or nil

	--- Into its part (PartFor). Each list is filled in arrival order and sorted
	--- when the tree is built (InsertBucket); the arrival position rides on
	--- the node as the last tie-break. Returns the node.
	local function File(bucket, resultID, info, hasSelf, index)
		if hasSelf then
			local node = ListingNode(resultID, info, index)
			table.insert(bucket.mine, node)
			return node
		end
		-- The leader's name: for a solo listing, the player. Secret in
		-- lockdown, and ByName answers nil for that without handing it on.
		local relation = lookup:ByName(info.leaderName)
		local node = ListingNode(resultID, info, index, relation)
		-- The strip's own rating (ListingRating), so the place and the mark
		-- agree: a group by its worst-rated member. The relation stays the
		-- leader's, the one name the lookup has.
		table.insert(bucket[PartFor(relation, ListingRating(resultID, info))], node)
		return node
	end

	for index, resultID in ipairs(results) do
		local info = C_LFGList.GetSearchResultInfo(resultID)
		if info then
			local numMembers = Readable(info.numMembers, nil)
			local hasSelf = Readable(info.hasSelf, false)

			if numMembers == nil then
				table.insert(unsorted, ListingNode(resultID, info, index))
			elseif numMembers <= 1 then
				local playerRoles = filters and filters.playerRoles
				local playerClasses = filters and filters.playerClasses
				local playerLevels = filters and filters.playerLevels
				if hasSelf or (SoloMatchesRoleFilter(resultID, playerRoles)
					and SoloMatchesClassFilter(resultID, playerClasses)
					and SoloMatchesLevelFilter(resultID, playerLevels)
					and MatchesPlaystyleFilter(info, playstyles)) then
					AddPlayerKey(File(solos, resultID, info, hasSelf, index), playerOrder, classRanks)
				end
			else
				if hasSelf or (GroupMatchesFilters(resultID, filters and filters.groupFilters)
					and GroupMatchesClassFilter(resultID, numMembers, hiddenClasses)
					and MatchesPlaystyleFilter(info, playstyles)) then
					File(groups, resultID, info, hasSelf, index)
				end
			end
		end
	end

	local dataProvider = CreateTreeDataProvider()

	local function InsertBucket(dividerType, bucket, order)
		local count = 0
		for _, part in ipairs(PARTS) do
			count = count + #bucket[part]
		end
		if count == 0 then
			return
		end
		local subtree = dataProvider:Insert({ dividerType = dividerType })
		for _, part in ipairs(PARTS) do
			table.sort(bucket[part], order)
			for _, node in ipairs(bucket[part]) do
				subtree:Insert(node)
			end
		end

		-- Re-apply what the player last did to THIS category. The flag lives on
		-- the panel rather than in the tree because this provider is brand new
		-- every search -- see the note on panel.collapsedByDivider.
		--
		-- RetainChildCollapse: collapse the box, not the rows inside it.
		-- SkipInvalidation: nothing is listening yet -- the provider has not
		-- been handed to the scroll box (TreeListDataProvider.lua:183-191, and
		-- note SkipInvalidation is the TRUE one, :9-10).
		subtree:SetCollapsed(
			collapsedByDivider ~= nil and collapsedByDivider[dividerType] == true,
			TreeDataProviderConstants.RetainChildCollapse,
			TreeDataProviderConstants.SkipInvalidation)
	end

	InsertBucket(DIVIDER_GROUP, groups, NewestFirst)
	InsertBucket(DIVIDER_SOLO, solos, PLAYER_ORDERS[playerOrder])

	table.sort(unsorted, NewestFirst)
	for _, node in ipairs(unsorted) do
		dataProvider:Insert(node)
	end

	return dataProvider
end

-------------------------------------------------------
---------- The panel
-------------------------------------------------------

--- Build the list panel. Returns it unanchored -- the caller places it.
---
--- Deliberately NO SetWidth. This is the flexible column of the split: the
--- window anchors it to the content region's left edge and to the filter
--- panel's left edge, and two opposite anchors fully determine a rect. Giving
--- it a width here would silently stop it tracking the window -- the mistake
--- .claude/context/patterns-ui.md opens with.
function LFGF.CreateListPanel(parent)
	local panel = S.Box(parent, S.colors.panel, S.colors.line)

	local scrollBox, scrollBar, noResults = LFGF.CreateScrollList(panel)
	panel.ScrollBox = scrollBox
	panel.ScrollBar = scrollBar
	noResults:Hide()
	panel.NoResultsFound = noResults

	-- A TREE view: the list is grouped, which a linear view cannot express.
	-- Padding and spacing are Blizzard's (all zero, Browse.lua:66-68).
	local view = CreateScrollBoxListTreeListView(0, 0, 0, 0, 0, 0)

	view:SetElementFactory(function(factory, elementData)
		local data = elementData.data

		if data.dividerType then
			factory(DIVIDER_TEMPLATE, function(frame, elementNode)
				LFGF.ThemeFont(frame.CategoryLabel, 13, "gold")
				frame.CategoryLabel:SetText(data.dividerType == DIVIDER_SOLO
					and L.LIST_DIVIDER_PLAYERS or L.LIST_DIVIDER_GROUPS)
				frame.CategoryLabel:Show()
				PaintDividerIcons(frame, elementNode:IsCollapsed())

				-- The whole header is the click target, so the whole header
				-- explains it. Blizzard's template has no hover scripts of its
				-- own (Browse.xml:277-315), and the box pools headers apart
				-- from the rows (one pool per template), so these never reach a
				-- row. The state is read on hover, not here.
				frame:SetScript("OnEnter", function(self)
					LFGF.ShowTextTooltip(self, DividerTooltip(data.dividerType, elementNode:IsCollapsed()))
				end)
				frame:SetScript("OnLeave", GameTooltip_Hide)

				-- Browse.lua:84-93 -- clicking a divider collapses its subtree.
				frame:SetScript("OnClick", function()
					-- The tooltip now says the wrong thing; it comes back,
					-- right, on the next hover (the author's choice over
					-- switching its text).
					if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end

					-- ToggleCollapsed RETURNS the new state
					-- (TreeListDataProvider.lua:193-197), so there is no need to
					-- read the field back.
					local nowCollapsed = elementNode:ToggleCollapsed()

					-- Remember it for the next search, which will build a tree
					-- this node is no longer part of.
					panel.collapsedByDivider[data.dividerType] = nowCollapsed

					-- Re-render the SAME provider. Calling Refresh() here would
					-- build a fresh tree, and while the flag would now survive
					-- that, re-querying the client for a click on a header is
					-- work nobody asked for. Re-initializing is also what
					-- repaints the icon.
					panel:Rerender()
				end)
			end)
		else
			factory(ROW_TEMPLATE, function(frame)
				DetachBlizzardScripts(frame)
				UpdateRow(frame, data.resultID, data.relation, data.note)
			end)
		end
	end)

	-- Each element's height, from its template, plus the note's line. The view
	-- sizes a row before its initializer runs (ScrollBoxListView.lua:383,
	-- ScrollBoxLinearView.lua:93-96, :153-162), so no row sets its own.
	view:SetElementExtentCalculator(function(_, elementData)
		local data = elementData.data
		if data.dividerType then
			return view:GetTemplateExtent(DIVIDER_TEMPLATE)
		end
		return view:GetTemplateExtent(ROW_TEMPLATE) + (data.note and NOTE_LINE_EXTENT or 0)
	end)

	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	--- Re-apply the current provider, keeping collapsed state.
	function panel:Rerender()
		local provider = self.ScrollBox:GetDataProvider()
		if provider then
			self.ScrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
		end
	end

	--- Rebuild from whatever the client currently holds. Called on both search
	--- outcomes, after a successful Group Finder report, and when a subtree is
	--- collapsed.
	function panel:Refresh()
		-- Whatever was waiting for the window to open is being done now.
		self.refreshPending = false
		-- THE FILTERED LIST, the only one Blizzard's UI reads: its camelot
		-- Browse tab draws it (Blizzard_LFGVanilla_Browse.lua,
		-- LFGBrowseMixin:UpdateResultList), and since 9.0.5 retail does too,
		-- where it replaced Blizzard's own list of reported listings. So a
		-- listing the player reported is left out of it; the raw
		-- GetSearchResults keeps it. .claude/rules/list-result-updates.md.
		local totalResults, results = C_LFGList.GetFilteredSearchResults()

		local provider = (Readable(totalResults, 0) == 0 or self.searchFailed)
			and CreateTreeDataProvider()
			or BuildDataProvider(Readable(results, nil) or {}, self.filters, self.collapsedByDivider)

		-- EMPTY IS EMPTY, whoever emptied it -- the question asked here is
		-- "did anything survive to be rendered", not "did the server send
		-- anything". Those stopped being the same question when a filter could
		-- remove a listing after it arrived, and an empty box carrying no
		-- message reads as broken.
		--
		-- IsEmpty(), not GetSize() == 0. Blizzard's GetSize REQUIRES an
		-- excludeCollapsed argument and asserts on nil, in the base mixin and
		-- in the linearized one CreateTreeDataProvider actually returns
		-- (TreeListDataProvider.lua:296, :443, :479-483) --
		--     assert(excludeCollapsed ~= nil, explicitParameterMsg);
		-- because the query APIs default to INCLUDING collapsed nodes and
		-- :428-435 wants the caller to say which they meant. Omitting it threw
		-- in the client on the first search.
		--
		-- IsEmpty is Blizzard's own name for this question and supplies
		-- IncludeCollapsed (:265-267), which is the right answer to state: a
		-- tree whose only box the player has collapsed still has results in it.
		-- The two constants cannot actually disagree here today -- Refresh
		-- rebuilds the provider and a fresh tree has nothing collapsed -- so
		-- this is intent, kept correct in advance rather than proved by a test.
		local isEmpty = provider:IsEmpty()
		-- Blizzard's two notices (Browse.lua:195): a failed search, a timed-out
		-- one included, says so, rather than that nothing was found.
		self.NoResultsFound:SetText(self.searchFailed and L.SEARCH_FAILED or L.NO_RESULTS)
		self.NoResultsFound:SetShown(isEmpty)

		self.ScrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
	end

	-- WHICH BOXES THE PLAYER HAS COLLAPSED, kept here rather than in the tree.
	--
	-- Every search builds a brand new provider, so a flag set on a tree node
	-- goes with the old nodes and the box springs back open -- which reads as
	-- the addon ignoring the player. Keyed by DIVIDER TYPE rather than by node,
	-- so it also survives a search in which that category had no listings at
	-- all and no divider was built.
	panel.collapsedByDivider = { [DIVIDER_GROUP] = false, [DIVIDER_SOLO] = false }

	--- Redraw the one row showing resultID, if any row is.
	---
	--- A result can CHANGE after it was drawn. leaderName is Nilable
	--- (LFGListInfoDocumentation.lua:982): the results can arrive before the
	--- server has named every leader, and the client fills the name in later
	--- and fires LFG_LIST_SEARCH_RESULT_UPDATED with that result's ID
	--- (:799-807). A listing withdrawn while on screen arrives the same way.
	--- Blizzard's rows redraw themselves on it (Browse.lua:500-513);
	--- DetachBlizzardScripts took that wiring off ours, so the panel listens
	--- instead. Without it a nameless row stayed blank until the next search.
	---
	--- ONE ROW, IN PLACE. The provider is not rebuilt and nothing is re-sorted:
	--- rows would move under the cursor. The relation is the one this search
	--- decided, read back from the row's node, so the icon and the row's place
	--- still agree -- a guildmate whose name arrived late stays unmarked until
	--- the next search, the same staleness as a roster that arrives late.
	---
	--- Only DRAWN rows are visited (ScrollBoxListView.lua:150-159), so an
	--- update for a result that is filtered out, collapsed or scrolled away
	--- does nothing; that row is drawn fresh when it next comes into view.
	---
	--- NOTHING WHILE THE WINDOW IS CLOSED. The rows are kept while hidden, so
	--- redrawing them then is work nobody sees -- and in a dungeon fight it is
	--- most of the redrawing this does. The OnShow below redraws them instead.
	--- IsVisible, not IsShown: closing the window hides an ANCESTOR of this
	--- panel, and the panel's own IsShown stays true.
	function panel:UpdateResult(resultID)
		if not self:IsVisible() then
			return
		end
		self.ScrollBox:ForEachFrame(function(frame, elementData)
			local data = elementData and elementData.data
			if data and data.resultID == resultID then
				UpdateRow(frame, resultID, data.relation, data.note)
				return true
			end
		end)
	end

	-- Bring the drawn rows up to date whenever the panel becomes visible, since
	-- UpdateResult skipped them while it was not. Blizzard's Browse panel does
	-- the same job with a full rebuild in its OnShow (Browse.lua:169-171); a
	-- Rerender keeps this search's order, relations and collapsed boxes, and
	-- re-reads each drawn row from the client. The ScrollBox itself has no
	-- refresh-on-show (ScrollBox.lua has only OnSizeChanged / FullUpdate).
	--
	-- OnShow reaches this panel when its window opens, although the window, not
	-- the panel, is what was shown: the scripts follow effective visibility,
	-- which Blizzard's own finder relies on (LFGParentFrameMixin:OnHide hides
	-- no panel, ParentFrame.lua:60-63, yet LFGWhoListMixin:OnHide is what turns
	-- SetWhoToUi off, WhoList.lua:253-255). HookScript, so a template's own
	-- OnShow, if it ever gains one, is kept.
	--
	-- A search that ENDED while closed has not been built at all (see OnEvent
	-- below), so that one is built now, from whatever the client holds -- the
	-- latest search, which is what the player should see.
	panel:HookScript("OnShow", function(self)
		if self.refreshPending or not self.ScrollBox:GetDataProvider() then
			self:Refresh()
		else
			self:Rerender()
		end
	end)

	panel.searchFailed = false
	panel:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
	panel:RegisterEvent("LFG_LIST_SEARCH_FAILED")
	panel:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
	panel:RegisterEvent("REPORT_PLAYER_RESULT")
	panel:SetScript("OnEvent", function(self, event, ...)
		-- Not the end of a search: leave the spinner and the list alone.
		if event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
			self:UpdateResult(...)
			return
		end
		-- A REPORTED LISTING LEAVES THE FILTERED LIST, so read it again, as
		-- Blizzard's Browse tab does on this event (Browse.lua, REPORT_PLAYER_RESULT).
		-- The players list's right-click opens Blizzard's own menu, with its
		-- Report entries (Browse.lua, CreateSearchEntryMenu). Only on SUCCESS:
		-- the payload's first value is a SendReportResult NUMBER
		-- (ReportSystemDocumentation.lua), so Blizzard's `if success` is true
		-- for every result, failures included. Not while a search runs: its
		-- results arrive filtered anyway, and the spinner must stay. While
		-- closed it waits for OnShow, as a search outcome does.
		if event == "REPORT_PLAYER_RESULT" then
			local result, reportType = ...
			if result == Enum.SendReportResult.Success
				and reportType == Enum.ReportType.GroupFinderPosting then
				if self:IsVisible() then
					self:Refresh()
				else
					self.refreshPending = true
				end
			end
			return
		end
		self:FinishSearch(event == "LFG_LIST_SEARCH_FAILED")
	end)

	-- Reporter le rafraîchissement lorsque le joueur a fermé le panneau.
	function panel:FinishSearch(failed)
		self.searchFailed = failed
		if not self:IsVisible() then
			self.refreshPending = true
			return
		end
		self:Refresh()
	end

	--- Les filtres de l’affichage ne prennent effet qu’après un clic sur
	--- Rechercher. Le bouton Toutes les annonces efface cet instantané.
	---
	--- CopyTable is DEEP unless asked otherwise (TableUtil.lua:218-228), so
	--- the per-section tables inside are copied too. A shallow copy would
	--- leave them shared with the filter panel's checkboxes, which is the one
	--- thing the snapshot exists to prevent.
	function panel:UseFilters(filters)
		self.filters = filters and CopyTable(filters) or nil
	end

	EventRegistry:RegisterCallback(LFGF.EVENT_FILTERS_APPLIED, function(_, filters, waiting)
		panel:UseFilters(filters)
		if not waiting then panel:FinishSearch(false) end
	end, panel)

	-- A RATING SAVED OR CLEARED, or the Player ratings setting switched: only
	-- the strips change, so the drawn rows are re-marked in place, with no
	-- rebuild, no re-sort and no scroll. The players list stays on screen beside
	-- the Player ratings tab, so a star clicked there marks the row here at
	-- once. A row drawn later reads the rating when it is drawn.
	local function RemarkRows()
		panel.ScrollBox:ForEachFrame(function(frame)
			if frame.LFGFRatingStrip and frame.resultID then
				local info = C_LFGList.GetSearchResultInfo(frame.resultID)
				if info then
					UpdateRatingStrip(frame, frame.resultID, info)
				end
			end
		end)
	end
	EventRegistry:RegisterCallback(LFGF.EVENT_PLAYER_RATING_CHANGED, RemarkRows, panel)
	EventRegistry:RegisterCallback(LFGF.EVENT_PLAYER_RATINGS_CHANGED, RemarkRows, panel)

	-- "SORT PLAYERS BY" CHANGED (core/settings.lua): sort the Players box again,
	-- by rebuilding from what the client holds, as the re-read after a report
	-- does -- the order is read when the tree is built. Nothing before the
	-- first search (no provider yet, and an empty one would show "No groups
	-- found"), and nothing while a search runs: its results arrive in the new
	-- order. Opening Settings closes the window (a centre panel runs
	-- CloseWindows, UIParentPanelManager.lua:288-289), so usually it waits for
	-- OnShow.
	EventRegistry:RegisterCallback(LFGF.EVENT_PLAYER_SORT_ORDER_CHANGED, function()
		if not panel.ScrollBox:GetDataProvider() then
			return
		end
		if panel:IsVisible() then
			panel:Refresh()
		else
			panel.refreshPending = true
		end
	end, panel)

	return panel
end

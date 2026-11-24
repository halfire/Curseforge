-- QuinteLFG -- core/playerrow.lua
--
-- The player rows the right column draws, in two shapes, both a name, a guild /
-- friend icon, a level, a class icon and a line of text:
--   * the ONE-LINE row, everything on one line: the Whispers tab's log
--     (core/whisperlog.lua) builds its rows on it and adds its action line;
--   * the LISTING row, a copy of a solo player's row in the players list, the
--     text on a grey second line: the Player ratings tab (core/playerratings.lua).
--
-- Published on LFGF.PlayerRow: Build / Fill for the one-line row, BuildListing /
-- FillListing for the listing row (each Build once per pooled frame, each Fill
-- on every fill), with HEIGHT, LISTING_HEIGHT and NAME_INSET_X for a caller
-- that lays something out around a row.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
local S = Quintessence.Style
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

local Row = {}
LFGF.PlayerRow = Row

-- THE ROW IS SHAPED LIKE A PLAYER ROW in the results list -- the same regions
-- in the same order, the same gaps, the same separator. A whisper from someone
-- in the list should read as the same person.
--
-- ONE DELIBERATE DIVERGENCE: the font size. The player row sets its name in
-- GameFontNormalLarge (Browse.xml:160), which is SystemFont_Shadow_Large and a
-- size up from everything beside it -- it can afford that, being a 48-tall row
-- whose name is its heading. This row is one line, so all three of its text
-- regions are set at GameFontNormal's size instead: GameFontNormalLeft,
-- GameFontDisableLeft and GameFontHighlightLeft all inherit GameFontNormal ->
-- SystemFont_Shadow_Med1 (FontStyles.xml:54, :90, :74, :62, :86, :50). They
-- differ only in COLOUR -- the name is overwritten with the class colour
-- anyway, the level is grey, the text white, because the text is the thing
-- being read.
--
-- 24 is the class icon's size there (:176) and what sets the row height; the
-- player row is 48 only because it carries a second line for the activity.
Row.HEIGHT = 26

-- THE FIRST LINE IS PINNED TO ITS OWN CENTRE, not the row's. Every region on it
-- hangs off a centre-bearing LEFT or RIGHT point, and on a row that grows a
-- second line (the whisper log's action line) the ROW's centre would drag the
-- whole line down between the two. Half the one-line height, so a one-line row
-- is laid out exactly as it would be on its centre.
local LINE_ONE_CENTER_Y = Row.HEIGHT / 2

local CLASS_ICON_SIZE = 24

-- Gaps copied from the player row: Level sits 4 after the name (:170),
-- ClassIcon 3 after the level (:178).
local NAME_TO_LEVEL_GAP = 4
local LEVEL_TO_ICON_GAP = 3
local ICON_TO_TEXT_GAP = 4

-- THE PLAYER ROW'S SEPARATOR, copied exactly (Browse.xml:149-155): white at
-- alpha 0.04, inset TOPLEFT (3, -2) and BOTTOMRIGHT (-3, 0). The -2 is what
-- separates one row from the next -- the panel does not reach the top edge, so
-- consecutive rows leave a 2px band of the darker background between them.
--
-- THAT IS THE WHOLE OF THE PLAYERS LIST'S ROW SPACING. Its view is built with
-- zero padding and zero spacing (Browse.lua:66-68), and so are the views that
-- use this row: the gap is drawn, not laid out. Adding view spacing on top
-- would double it.
local ROW_BG_INSET_X, ROW_BG_INSET_TOP = 3, -2

-- The search-entry row's own hover bar (Browse.xml:206), so this row lights up
-- the same colour a result does.

-- The name begins at the PartyIcon's slot, x = 8 (Browse.xml:158-162) -- which
-- is where a SOLO search result's name begins too, since it is anchored to that
-- icon's TOPLEFT (Browse.lua:388). A row here reads as the same person as a
-- player in the list.
Row.NAME_INSET_X = 8

-- Where the name begins: pinned to the first line's own centre (see
-- LINE_ONE_CENTER_Y). With a guild / friend icon the ICON takes this anchor and
-- the name follows it (core/relations.lua, LayOutRelationIcon).
local NAME_ANCHOR = { point = "LEFT", relativePoint = "TOPLEFT", x = Row.NAME_INSET_X, y = -LINE_ONE_CENTER_Y }

-- The name auto-sizes so the level sits right after it, exactly as the player
-- row does -- and is clamped for the same reason that row clamps with
-- NameMaxWidth: without it one long name shoves the text off the panel.
local NAME_MAX_WIDTH = 140

--- Build a row's regions, once per pooled frame.
---
--- WHY THE ROW IS BUILT HERE AND NOT INHERITED. The addon's only XML is the
--- settings rows (core/settings.xml), so there is no row template of ours to
--- name -- a view is given a FRAME TYPE instead, which SetElementInitializer
--- accepts as an alternative to a template (its argument is
--- `frameTemplateOrFrameType`, ScrollBoxListView.lua:496; FrameFactoryMixin:Create
--- falls back to treating it as a native type when there is no template info,
--- FrameFactory.lua:17-25).
---
--- The ScrollBox pools these frames, so a view's initializer runs many times on
--- one frame. Building is therefore guarded by the caller and the FILLING is
--- not.
---
--- NO SetHeight HERE, deliberately. The VIEW sizes each row, from its extent,
--- BEFORE it runs the initializer (ScrollBoxListView.lua:383, :397-421) -- so a
--- height set here would override the view's on a new frame.
function Row.Build(row)
	-- BACKGROUND layer, as the player row has it, so nothing else in the row
	-- has to know it is there.
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(unpack(S.colors.raised))
	bg:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_BG_INSET_X, ROW_BG_INSET_TOP)
	bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_BG_INSET_X, 0)
	row.ResultBG = bg

	-- HOVER HIGHLIGHT, and THE ENGINE DRAWS IT. A texture in the HIGHLIGHT draw
	-- layer is shown while the mouse is over its frame with no script of
	-- anyone's, which is exactly how the search-entry row highlights
	-- (Mainline/Blizzard_LFGVanilla_Browse.xml:205-212) -- same atlas, same ADD
	-- blend. So there is no OnEnter of ours to write, and none to get wrong.
	--
	-- THE INSETS ARE OURS, NOT THEIRS. Blizzard's highlight is cut (3, -3) /
	-- (-3, -1) for a 48-tall two-line row; on a 26-tall one those numbers would
	-- leave it short of the band the separator draws. Sharing ResultBG's insets
	-- makes the highlight sit exactly on that band.
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetColorTexture(unpack(S.colors.hover))
	highlight:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_BG_INSET_X, ROW_BG_INSET_TOP)
	highlight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_BG_INSET_X, 0)
	row.Highlight = highlight

	-- PLACED IN Fill, not here: whether a guild / friend icon stands before it
	-- changes from row to row (see NAME_ANCHOR).
	local name = S.Text(row, 13, S.colors.text)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	row.Name = name

	-- The guild / friend icon, hidden until Fill says who this is
	-- (core/relations.lua). Clicks go through it, so a click on it still
	-- reaches the row.
	row.Relation = LFGF.CreateRelationIcon(row)

	local level = S.Text(row, 12, S.colors.muted)
	level:SetPoint("LEFT", name, "RIGHT", NAME_TO_LEVEL_GAP, 0)
	level:SetJustifyH("LEFT")
	row.Level = level

	local classIcon = row:CreateTexture(nil, "ARTWORK")
	classIcon:SetSize(CLASS_ICON_SIZE, CLASS_ICON_SIZE)
	classIcon:SetPoint("LEFT", level, "RIGHT", LEVEL_TO_ICON_GAP, 0)
	row.ClassIcon = classIcon

	-- THE TEXT SLOT: the whisper on the Whispers tab, the newest activity on the
	-- Player ratings tab. Message by name, for the whisper it first held.
	--
	-- No width: two opposite anchors determine the rect, so the text takes
	-- whatever the panel's width leaves. See .claude/context/patterns-ui.md.
	-- BOTH ARE SET IN Fill, which re-anchors on every fill -- the left one
	-- depends on whether the class icon shows.
	--
	-- GameFontHighlightLeft is the same size as the name and the level -- see
	-- the note at the top of this file -- and differs only in being white.
	local message = S.Text(row, 12, S.colors.text)
	message:SetJustifyH("LEFT")
	message:SetWordWrap(false)
	row.Message = message
end

--- Fill the regions both shapes share: the guild / friend icon, the clamped
--- name in its class colour, and the level and class icon. Answers whether the
--- level and the class icon are shown.
---
--- EVERY BRANCH-DEPENDENT PROPERTY IS WRITTEN ON EVERY PASS, because rows are
--- pooled: a row that showed a mage is reused for a player whose class nobody
--- knows, and a one-way rule would leave the mage's icon and colour on it. That
--- is the trap .claude/context/patterns-ui.md opens the borrowed-template
--- section with, and it applies to a row we built ourselves just as much.
---
--- BOTH OR NEITHER for level and class icon, as the player row does
--- (Browse.lua:380-387): a class icon with no level reads as a rendering fault.
---
--- THE NAME GOES IN THROUGH A SETTER AND NOTHING ELSE: it can be a secret, and
--- a setter is the one operation that takes one.
local function FillPlayer(row, data, anchor, nameMaxWidth)
	-- A GUILDMATE OR FRIEND gets an icon where the name begins, and the name
	-- moves after it. ASKED ON EVERY FILL, from the GUID, and only then --
	-- nothing listens for the roster or the friend list changing, by decision --
	-- so a row that stays on screen keeps its answer, and a row drawn again
	-- (scrolled back into view) asks afresh.
	local relation = LFGF.RelationByGUID(data.guid)
	local relationWidth = LFGF.LayOutRelationIcon(row.Relation, row.Name, relation,
		anchor.point, row, anchor.relativePoint, anchor.x, anchor.y)

	-- Clamped, shorter by the icon's width when there is one, so the level and
	-- the text keep the room they had. A secret name's width is left at its
	-- natural size (LFGF.SetClampedText; ColourRow in core/listpanel.lua says
	-- why that beats pinning it).
	LFGF.SetClampedText(row.Name, data.name, nameMaxWidth - relationWidth)

	local class = not S.IsLight() and LFGF.ClassColor(data.classFilename)
	if class then row.Name:SetTextColor(class.r, class.g, class.b)
	else row.Name:SetTextColor(unpack(S.colors.text)) end

	local classAtlas = LFGF.ClassIconAtlas(data.classFilename)
	local level = LFGF.Readable(data.level, nil)
	local decorated = classAtlas ~= nil and level ~= nil

	if decorated then
		row.ClassIcon:SetAtlas(classAtlas, false)
		row.Level:SetFormattedText("%s %s", L.LEVEL_ABBR, level)
	end
	row.ClassIcon:SetShown(decorated)
	row.Level:SetShown(decorated)
	return decorated
end

--- Fill a one-line row from one player: data = { name, guid, classFilename,
--- level, text }, any of which may be nil, and name, guid and text secret. The
--- text goes in through a setter too.
function Row.Fill(row, data)
	local decorated = FillPlayer(row, data, NAME_ANCHOR, NAME_MAX_WIDTH)

	-- Re-anchored, not merely re-shown: an anchor to a hidden region still
	-- resolves, so leaving the text on the class icon would open a gap the
	-- width of a level and an icon nobody can see the cause of.
	row.Message:ClearAllPoints()
	row.Message:SetPoint("LEFT", decorated and row.ClassIcon or row.Name, "RIGHT",
		ICON_TO_TEXT_GAP, 0)
	-- The first line's centre, like every other region on it: RIGHT is
	-- centre-bearing, and the row's own centre moves when it grows a second
	-- line. NAME_INSET_X in from the right, mirroring the name, so a long text
	-- is cut off inside the row's box.
	row.Message:SetPoint("RIGHT", row, "TOPRIGHT", -Row.NAME_INSET_X, -LINE_ONE_CENTER_Y)

	row.Message:SetText(data.text)
end

-------------------------------------------------------
---------- The listing row
-------------------------------------------------------
-- A COPY OF A SOLO PLAYER'S ROW in the players list, by the author's decision:
-- Blizzard's LFGBrowseSearchEntryTemplate (Mainline/Blizzard_LFGVanilla_Browse.xml
-- :139-237) as core/listpanel.lua lays it out for a solo player. Copied, not
-- inherited, because that template is defined in the LoadOnDemand Group Finder
-- (Blizzard_GroupFinder_VanillaStyle), which may not be loaded when this row is
-- built, and its scripts reach into Blizzard's own Browse frame.

-- The template's height (:140).
Row.LISTING_HEIGHT = 52

-- A solo player's name: the PartyIcon's slot at TOPLEFT (8, -14) (:150-154),
-- plus NameSoloOffsetX, 5 (:142), as core/listpanel.lua anchors it. With a
-- guild / friend icon the icon takes this anchor and the name follows it.
local LISTING_NAME_ANCHOR = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 13, y = -14 }

-- NameMaxWidth (:146), the players list's own clamp.
local LISTING_NAME_MAX_WIDTH = 200

-- The name and level are 14 tall, the activity line 15 (:156, :169, :188).
local LISTING_NAME_HEIGHT = 14
local LISTING_TEXT_HEIGHT = 15

-- The activity line runs from under the name to this far in from the row's
-- right edge, so a long line is cut off inside the band rather than past it.
local LISTING_TEXT_INSET_RIGHT = 8

--- Build a listing row's regions, once per pooled frame. The view sizes the
--- row (LISTING_HEIGHT); nothing here sets a height on the row.
---
--- `rightReserved`, if given, is the width the caller keeps free at the row's
--- right end for a control of its own (the Player ratings stars): the second
--- line ends that much further in.
function Row.BuildListing(row, rightReserved)
	-- The template's band and blue hover bar (:213-236). The bar sits in the
	-- HIGHLIGHT layer, so the engine shows it while the mouse is over the row,
	-- with no script of ours (Blizzard's row shows a hidden one from OnEnter).
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(unpack(S.colors.raised))
	bg:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -2)
	bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 0)
	row.ResultBG = bg

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetColorTexture(unpack(S.colors.hover))
	highlight:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
	highlight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, -1)
	row.Highlight = highlight

	-- PLACED IN FillListing (the guild / friend icon may stand before it).
	local name = S.Text(row, 15, S.colors.text)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	name:SetHeight(LISTING_NAME_HEIGHT)
	row.Name = name

	row.Relation = LFGF.CreateRelationIcon(row)

	-- The level hangs off the name, as Blizzard hangs it whenever the Discord
	-- icon is hidden (Browse.lua:464-469); the class icon off the level (:174-179).
	local level = S.Text(row, 12, S.colors.muted)
	level:SetHeight(LISTING_NAME_HEIGHT)
	level:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 4, 0)
	row.Level = level

	local classIcon = row:CreateTexture(nil, "ARTWORK")
	classIcon:SetSize(CLASS_ICON_SIZE, CLASS_ICON_SIZE)
	classIcon:SetPoint("BOTTOMLEFT", level, "BOTTOMRIGHT", 3, -5)
	row.ClassIcon = classIcon

	-- THE SECOND LINE, grey, under the name: the template's ActivityName
	-- (:187-192), which holds "Deadmines | Westfall" on a solo player's row.
	-- Two TOP corner anchors give it a width without a centre-bearing point:
	-- the name's bottom is 14 + 14 = 28 down, and the line starts 2 below it.
	local activity = S.Text(row, 12, S.colors.muted)
	activity:SetJustifyH("LEFT")
	activity:SetWordWrap(false)
	activity:SetHeight(LISTING_TEXT_HEIGHT)
	activity:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
	activity:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(LISTING_TEXT_INSET_RIGHT + (rightReserved or 0)),
		LISTING_NAME_ANCHOR.y - LISTING_NAME_HEIGHT - 2)
	row.Activity = activity
end

--- Fill a listing row from one player: data = { name, guid, classFilename,
--- level, text }, as Fill takes it. The text is the second line.
function Row.FillListing(row, data)
	FillPlayer(row, data, LISTING_NAME_ANCHOR, LISTING_NAME_MAX_WIDTH)
	row.Activity:SetText(data.text)
end


-------------------------------------------------------
---------- The right-click menu
-------------------------------------------------------
-- BOTH LISTS OPEN THE SAME MENU, Blizzard's own: the Whispers tab's log on a
-- whisper's sender, and the Player ratings tab on a recent ally (the author's
-- decision, 2026-11-13). .claude/rules/player-ratings.md

-- The menu Blizzard opens for a player you are not grouped with, and the tag it
-- carries: UnitPopupManager:OpenMenu tags every root description
-- "MENU_UNIT_"..which (UnitPopupShared.lua:110), which is what Menu.ModifyMenu
-- keys on.
local MENU_WHICH = "FRIEND"
local MENU_TAG = "MENU_UNIT_" .. MENU_WHICH

-- A private key on the contextData, so the modifier below can tell a menu this
-- addon opened from one Blizzard opened. Namespaced because contextData is
-- Blizzard's table, not ours.
local MENU_MARKER = "lfgfPlayerMenu"
-- Another private key: entries a list adds to its own menu (Row.OpenMenu's
-- addEntries), run by the modifier below.
local MENU_ENTRIES = "lfgfPlayerMenuEntries"
-- And the name exactly as the list gave it, "Firstname Surname": Blizzard's
-- OpenMenu splits contextData.name in two while regional unique names are off
-- (UnitPopupShared.lua:44-46), and Add WoW Friend wants the whole name.
local MENU_FULL_NAME = "lfgfPlayerMenuFullName"

local menuModifierRegistered = false

--- Open Blizzard's player menu on a row: Invite, Whisper, Ignore, Report Player
--- and Copy Character Name, each with its own CanShow, in Blizzard's own words
--- and Blizzard's own order (UnitPopupSharedMenus.lua:193-211).
---
--- THE FRIEND MENU, as FriendsFrame_ShowDropdown opens it
--- (Camelot/FriendsFrame.lua:200-222) and as a player's name in chat does
--- (ItemRefHandlers.lua:41-42). Blizzard's own Group Finder Who List
--- right-clicks a row into this call with nothing but a name (WhoList.lua:26,
--- :223).
---
--- IT ALL LOADS HERE, and the TOC is not obvious about it.
--- UnitPopupSharedButtonMixins leaves Invite:CanShow and Whisper:CanShow as
--- error("Unimplemented") (:549, :491); the implementations arrive from
--- [Family]\UnitPopupButtons.lua [AllowLoadGameType standard, camelot]
--- (Blizzard_UnitPopup.toc:11), which is Mainline's. Camelot loads its own
--- UnitPopupMenus.lua too, but the nine menus whose entries it replaces do not
--- include FRIEND (Camelot/UnitPopupMenus.lua:2-152).
---
--- UnitPopup_OpenMenu DIRECT rather than through FriendsFrame_ShowDropdown:
--- that wrapper builds its own contextData (:202-217) with nowhere to put the
--- marker, and without one the modifier below would change the friends list's
--- menu too. Everything the wrapper sets is set here: the name, chatTarget the
--- same name, a chat frame (Whisper hands it to ChatFrameUtil.SendTell,
--- UnitPopupSharedButtonMixins.lua:512), and the caller's fields (a GUID, a
--- chat line). The owner is the ROW, not the chat frame, so the menu closes
--- when the row does.
---
--- REFUSED OUTRIGHT WHEN THE NAME CANNOT BE READ. Blizzard's code works on it
--- as a string: UnitPopupManager:OpenMenu splits it while regional unique names
--- are off (UnitPopupShared.lua:44-46), and entries compare it with the
--- player's own (UnitPopupIgnoreButtonMixin:CanShow,
--- UnitPopupSharedButtonMixins.lua:390-393). On a hidden name, from our tainted
--- stack, either would error inside Blizzard's file. Answers whether it opened.
---
--- ENTRIES OF A LIST'S OWN: addEntries, when given, is called with the menu's
--- root description after Blizzard has built it, and may append to it (the
--- Player ratings tab's Set Note). Appended, because Menu.ModifyMenu runs after
--- Blizzard's generator (Menu.lua:2751-2764), so they come last.
---
--- TAINT, stated rather than hidden: the menu is built in our tainted stack,
--- as core/listpanel.lua's reuse of Blizzard's search-entry menu is. The one
--- entry that breaks is Copy Character Name, greyed out below.
function Row.OpenMenu(row, name, fields, addEntries)
	name = LFGF.Readable(name, nil)
	if name == nil then
		return false
	end

	local contextData = fields or {}
	contextData.name = name
	contextData.chatTarget = name
	contextData.chatFrame = DEFAULT_CHAT_FRAME
	contextData.ownerFrame = row
	contextData[MENU_MARKER] = true
	contextData[MENU_FULL_NAME] = name
	contextData[MENU_ENTRIES] = addEntries
	UnitPopup_OpenMenu(MENU_WHICH, contextData)
	return true
end

--- Grey out the one entry that cannot work from an addon.
---
--- CopyToClipboard is HasRestrictions (OsDocumentation.lua:12) and the menu is
--- built in OUR tainted stack, so clicking Copy Character Name raises
--- ADDON_ACTION_FORBIDDEN naming this addon and copies nothing. It is the ONLY
--- entry taint actually breaks: C_FriendList.AddOrDelIgnore and
--- C_PartyInfo.InviteUnit carry no restriction at all, and Whisper only opens
--- an edit box.
---
--- DISABLED, NOT REMOVED, because removing is not on offer. Blizzard's own
--- guide describes Menu.ModifyMenu as appending -- "a function that appends
--- elements to the menu" (11_0_0_MenuImplementationGuide.lua:402) -- and the
--- description mixin has an Insert (Menu.lua:427) with no matching Remove.
--- SetEnabled (:830) is the supported lever, so the entry stays visible and
--- greyed rather than firing an error.
---
--- Matched on the LABEL because the description does not carry the mixin that
--- made it -- CreateMenuDescription captures it in closures
--- (UnitPopupSharedButtonMixins.lua:187-193) -- and MenuUtil.GetElementText
--- (MenuUtil.lua:176-178) is the supported way to read one back. The label is
--- the same global the entry is built from, so it stays localised.
local function DisableCopyCharacterName(rootDescription)
	for _, elementDescription in rootDescription:EnumerateElementDescriptions() do
		if MenuUtil.GetElementText(elementDescription) == COPY_CHARACTER_NAME then
			elementDescription:SetEnabled(false)
			return
		end
	end
end

--- ADD WOW FRIEND, the FIRST item of both lists' menus (the author's
--- decisions, 2026-11-13): Blizzard's own entry from its Recent Allies menu
--- (UnitPopupAddRecentAllyTitleFriendButtonMixin,
--- UnitPopupSharedButtonMixins.lua:3877-3901), copied because the FRIEND menu
--- has no such entry.
---
--- BLIZZARD'S RULES: shown while Battle.net is connected and WoW friends through
--- it are on (its CanShow, :3883-3885), even for someone already a friend; a
--- click raises Blizzard's own event with the full name, and Blizzard's
--- BattleNetInviteFrame opens its Send / Cancel window for it
--- (Blizzard_AddFriend/AddFriendTemplates.lua:11, :45-64), whose Send calls
--- C_BattleNet.SendTitleFriendInviteByName. That call is HasRestrictions
--- (BattleNetDocumentation.lua:336-345), but a probe from /run, which is
--- tainted like addon code, opened the window and sent the request with no
--- error (2026-11-13). The menu closes, as Blizzard's answer says (:3900).
---
--- ONE DIFFERENCE: a player with no BattleTag gets no entry. Blizzard's would
--- open CreateBattleTagFrame then (:3893-3894), and that frame is defined
--- nowhere in this client's sources. Kiosk mode, which greys Blizzard's out
--- (:3887-3889, UnitPopupSharedUtils.lua:208), is not followed: an event
--- client, never a player's.
---
--- FIRST: inserted at index 2, after the name, which is the first thing
--- Blizzard's OpenMenu adds to the menu (UnitPopupShared.lua:110-112), through
--- Insert (Menu.lua:427-437) on a button made by MenuUtil.CreateButton
--- (MenuUtil.lua:209-214), since the modifier runs after Blizzard's entries.
local function AddWoWFriend(rootDescription, name)
	if name == nil or not (BNFeaturesEnabledAndConnected() and C_BattleNet.AreTitleFriendsEnabled()) then
		return
	end
	if LFGF.Readable(select(2, BNGetInfo()), nil) == nil then
		return
	end
	rootDescription:Insert(MenuUtil.CreateButton(ADD_WOW_FRIEND, function()
		EventRegistry:TriggerEvent("BattleNetInviteFrame.TitleFriendInviteByNameRequested", name)
		return MenuResponse.Close
	end), 2)
end

--- The one modifier: grey out Copy Character Name, put Add WoW Friend first,
--- then add the entries the list asked for.
---
--- SCOPED BY THE MARKER, and that is the important part. A modifier registered
--- for this tag fires for EVERY FRIEND menu in the game -- the friends list, a
--- player's name in chat -- where Copy Character Name works perfectly, because
--- Blizzard's code is untainted. Changing those menus would be a far worse bug
--- than the one being fixed.
local function ModifyOurMenu(_, rootDescription, contextData)
	if not (contextData and contextData[MENU_MARKER]) then
		return
	end
	DisableCopyCharacterName(rootDescription)
	AddWoWFriend(rootDescription, contextData[MENU_FULL_NAME])
	local addEntries = contextData[MENU_ENTRIES]
	if addEntries then
		addEntries(rootDescription)
	end
end

--- Register the modifier above, ONCE PER SESSION, whichever list is built
--- first. Menu.ModifyMenu appends to a callback registry (Menu.lua:2767-2787), so a
--- registration per list would stack duplicates -- each harmless on its own,
--- all doing the same work. Called by each list's factory, so the modifier
--- exists from when the window is built, never before.
function Row.RegisterMenuModifier()
	if menuModifierRegistered then
		return
	end
	menuModifierRegistered = true
	Menu.ModifyMenu(MENU_TAG, ModifyOurMenu)
end

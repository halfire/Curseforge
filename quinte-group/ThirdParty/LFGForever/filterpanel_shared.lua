-- QuinteLFG -- core/filterpanel_shared.lua
--
-- What the filter panel's files share: the section builders and the grid
-- they lay their checkboxes out on. core/filterpanel.lua builds the search row,
-- the tabs and the first three sections; core/filterpanel_miscellaneous.lua
-- builds the fourth. Both read this file's one table, LFGF.FilterShared, at
-- FILE scope, which is why it loads before either of them (the TOC, and
-- window_spec's "every file reads at load only what an earlier file defined").
--
-- Moved here unchanged from core/filterpanel.lua in 0.22.0-dev.1, when the
-- Miscellaneous section became the first section built in a file of its own.
-- What only one file uses stays in that file: the search row, My filters,
-- MeasureLayout and the tabs are filterpanel.lua's.
--
-- NOTHING HERE IS BUILT AT LOAD: these are functions the panel files call while
-- the panel is being built, on the first /lfg.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
local S = Quintessence.Style
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

local Shared = {}
LFGF.FilterShared = Shared

-- Where the search row and every section start is ours, not Blizzard's --
-- theirs hangs at x=70 inside a full-width panel, this one is left-aligned in
-- the filter column (core/filterpanel.lua's FILTER_PANEL_WIDTH). The padding has
-- to clear the dropdown's own background art, which overhangs the frame by 8
-- horizontally and 7 vertically (common-dropdown-textholder,
-- Mainline/MenuTemplates.xml:7-11), or it would clip the inset's border.
local ROW_PADDING = 12

-- SECTIONS
-- --------
-- A section is a title, a rule under it, and whatever the caller puts below.
-- BuildSection is a factory so the NEXT filter is a call rather than a
-- copy-paste -- which is the point of having a section at all.
--
-- Not SettingsListSectionHeaderTemplate. It loads on camelot, but it drags
-- SettingsListSectionHeaderMixin and NewFeatureLabelTemplate, is a fixed 45
-- tall built for the Settings LIST layout, and its OnLoad is a mixin method
-- written for that context. A FontString and a texture get the same look
-- without inheriting someone else's lifecycle.
local SECTION_TITLE_TO_RULE_GAP = 4
local SECTION_RULE_HEIGHT = 4          -- UI-LFG-DividerLine is 368x4
local SECTION_RULE_TO_CONTENT_GAP = 8

-- ONE gap, used both above the first section and between sections, so "the
-- same offset" is a property of the layout rather than two constants that
-- happen to agree. Every later section inherits it (Miscellaneous, the
-- fourth, in core/filterpanel_miscellaneous.lua).
--
-- A chosen number, not a derived one, and in the neighbourhood of Blizzard's:
-- SettingsListSectionHeaderTemplate leads its own title by 16
-- (Blizzard_SettingControls.xml:18, TOPLEFT y="-16"). A little more than that
-- here because these sections sit directly under live controls rather than in
-- a scrolling list of other headers.
local SECTION_TOP_GAP = 20

-- The role row: a 32x32 checkbox (CheckButtonTemplates.xml:51), then the icon,
-- then the label. The icon is sized by us rather than by the atlas, as
-- Blizzard does for these (SetAtlas(..., false), Browse.lua:383, :1484).
local ROLE_ICON_SIZE = 20
local ROLE_BOX_TO_ICON_GAP = 2
local ROLE_ICON_TO_LABEL_GAP = 4

-- A COLLAPSIBLE SECTION'S +/- (0.22.0-dev.2): Blizzard's own list +/-, the
-- pair our players list shows on its Groups / Players boxes
-- (Mainline/Blizzard_LFGVanilla_Browse.xml:289-298) and Blizzard's camelot
-- Reputation, Skills and Currency headers set by hand
-- (Camelot/ReputationFrame.lua:281-286). "+" means collapsed, click to expand;
-- "-" means expanded. At their atlas sizes the plus is 13x13 and the minus
-- 13x4 (AtlasInfo.lua, interface/common/commonbuttonlist), so the icon is
-- centred in a slot 13 wide and the title starts after the slot and a gap: the
-- 4 Blizzard's camelot sub-headers leave between their toggle and their name
-- (Camelot/ReputationFrame.xml:38-52). .claude/rules/collapsible-filter-sections.md
local EXPAND_ATLAS = "common-button-list-plus"
local COLLAPSE_ATLAS = "common-button-list-minus"
local COLLAPSE_ICON_WIDTH = 13
local COLLAPSE_ICON_TO_TITLE_GAP = 4

-- A COLLAPSED SECTION'S WARNING (0.22.0-dev.3): shown right of the title while
-- the section is collapsed and its filters are not at their defaults, so the
-- player knows filters they cannot see still apply. Blizzard's camelot Group
-- Finder shows exactly this beside an activity name: a 16x16 frame holding
-- UI-EJ-WarningTextIcon, LEFT to the name's RIGHT at x = 2
-- (Mainline/Blizzard_LFGVanilla_Listing.xml:199-224). A file, not an atlas, so
-- that camelot XML is the evidence it exists.
local WARNING_ICON_FILE = [[Interface\EncounterJournal\UI-EJ-WarningTextIcon]]
local WARNING_ICON_SIZE = 16
local TITLE_TO_WARNING_GAP = 2

-- A WORD THAT STARTS A GRID ROW, before a control of its own: the Level row
-- (core/filterpanel.lua) and the Playstyle row
-- (core/filterpanel_miscellaneous.lua). One inset, so every word in the grids
-- starts at the same place: 6 is the class section's bulk links' nudge, by eye
-- (at the cell edge a label read as shifted left of the checkbox above it,
-- whose art is drawn inside its 32-wide frame; reported from the client,
-- 0.10.0-dev.2). The gap is the Level row's, from its label to Blizzard's
-- LevelRangeFrameTemplate.
local ROW_LABEL_INSET_X = 6
local ROW_LABEL_TO_CONTROL_GAP = 4

-- One grid row is the checkbox's height, and the rows are this far apart.
local ROLE_ROW_HEIGHT = 32             -- the checkbox, CheckButtonTemplates.xml:51
local ROLE_ROW_TO_ROW_GAP = 4

-------------------------------------------------------
---------- Sections
-------------------------------------------------------

--- Give a section the height of what it shows: the title and the rule, and
--- below them the content unless the section is collapsed.
---
--- A plain SetHeight, NOT an anchor to the content -- anchoring the section to
--- something that hangs off it is the cycle the client refuses outright (see
--- StackAnchor in BuildSection).
local function SetSectionHeight(section)
	local height = section.Title:GetStringHeight()
		+ SECTION_TITLE_TO_RULE_GAP + SECTION_RULE_HEIGHT
	if not section.collapsed then
		height = height + SECTION_RULE_TO_CONTENT_GAP + section.Content:GetHeight()
	end
	section:SetHeight(height)
end

--- Are these boxes all showing their defaults? The default is remembered on
--- each box (`defaultChecked`, BuildRoleCheck). True for no boxes.
local function ChecksAtDefaults(checks)
	for _, check in ipairs(checks) do
		if check:GetChecked() ~= check.defaultChecked then
			return false
		end
	end
	return true
end

--- The warning's tooltip: the addon's shared title-and-line tooltip
--- (LFGF.ShowTooltip, core/main.lua).
local function ShowWarningTooltip(self)
	LFGF.ShowTooltip(self, L.COLLAPSED_FILTERS_TITLE, L.COLLAPSED_FILTERS_TOOLTIP)
end

--- Show a collapsible section's warning when, and only when, the section is
--- collapsed AND its filters are not at their defaults. A section says what
--- its defaults are with an IsAtDefaults method (BuildRoleCheckSection gives
--- one; BuildLevelRow in core/filterpanel.lua extends it); a section with none
--- (Miscellaneous, which holds no filter yet) never warns. Does nothing on a
--- section with no header.
---
--- CALLED WHERE A COLLAPSED SECTION'S STATE CAN CHANGE: SetSectionCollapsed
--- (the header's click, the restore at build, Defaults), and the end of
--- core/filterpanel.lua's ApplyFilters (the restore, Reset filters, My
--- filters, Defaults). Nothing else changes a hidden box, so nothing else
--- needs to call it.
---
--- A TOOLTIP THE ICON OWNS GOES WITH IT: the icon can be hidden under the
--- mouse (a click falls through it and expands the section), and the sources
--- do not say a tooltip hides with its owner. Blizzard checks ownership before
--- hiding the same way (TabSystemTemplates.lua:73).
local function UpdateSectionWarning(section)
	local header = section.Header
	if not header then
		return
	end
	local show = false
	if section.collapsed and section.IsAtDefaults then
		show = not section:IsAtDefaults()
	end
	if not show and GameTooltip:IsOwned(header.Warning) then
		GameTooltip:Hide()
	end
	header.Warning:SetShown(show)
end

--- Show a collapsible section collapsed or expanded: its +/-, its content, its
--- height, and what the next section stacks under. Saves nothing and moves no
--- other section: the header's click does both, and the panel restores and
--- forgets through here too.
---
--- COLLAPSED, THE NEXT SECTION HANGS OFF THE RULE. Hiding the content alone
--- would leave its whole height empty: an anchor to a hidden region still
--- resolves to its full rect (Blizzard re-anchors around a button it hides for
--- exactly that reason, Blizzard_AccountStoreCardTemplates.lua:149-150). The
--- rule is always shown, so the panel's LayOutSections re-anchors the next
--- section to it.
---
--- THE BOXES KEEP THEIR STATE while hidden, and the search snapshot reads them
--- whether shown or not, so a collapsed section still filters.
local function SetSectionCollapsed(section, collapsed)
	section.collapsed = collapsed
	section.Header.Icon:SetAtlas(collapsed and EXPAND_ATLAS or COLLAPSE_ATLAS,
		TextureKitConstants.UseAtlasSize)
	section.Content:SetShown(not collapsed)
	section.StackAnchor = collapsed and section.Divider or section.Content
	SetSectionHeight(section)
	-- Last, after the content is shown or hidden: hiding the role section runs
	-- Blizzard's LevelRangeFrameMixin:OnHide, which may fix the level range.
	UpdateSectionWarning(section)
end

--- The header's click: flip the section, save its key (core/main.lua), and
--- have the panel stack its sections again. No sound, like Blizzard's camelot
--- headers and our players list's +/-.
local function ToggleSection(panel, section)
	local collapsed = not section.collapsed
	SetSectionCollapsed(section, collapsed)
	LFGF.SetFilterSectionCollapsed(section.collapseKey, collapsed)
	panel:LayOutSections()
end

--- A collapsible section's header: one Button across the whole title row,
--- holding the +/- and the title, the shape of Blizzard's camelot Reputation
--- and Skills headers, where the whole row is a Button
--- (Camelot/ReputationFrame.xml:3-35).
---
--- THE TITLE IS THE BUTTON'S OWN FONT STRING, so the engine turns it white on
--- hover with no script: GameFontHighlightLarge is GameFontNormalLarge's white
--- twin (Blizzard_Fonts_Shared/Shared/FontStyles.xml:196), the pair our text
--- links use in small (LFGF.CreateRowLink, core/main.lua).
---
--- LEFT CLICK ONLY, the default registration, like Blizzard's headers. No
--- press nudge, by the author's choice.
---
--- THE ROW'S OWN CONTROLS STAY CLICKABLE: anything a caller puts on the title
--- row (Reset filters, Save new filter, My filters) is lifted above the header
--- with RaiseOverHeader below. The header is as tall as the title, so it never
--- reaches the content under the rule.
local function BuildHeader(panel, section, titleText)
	local header = CreateFrame("Button", nil, section)
	header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)

	local icon = header:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER", header, "LEFT", COLLAPSE_ICON_WIDTH / 2, 0)
	header.Icon = icon

	local title = S.Text(header, 16, S.colors.gold)
	title:SetPoint("LEFT", header, "LEFT", COLLAPSE_ICON_WIDTH + COLLAPSE_ICON_TO_TITLE_GAP, 0)
	header:SetFontString(title)
	header:SetNormalFontObject(GameFontNormalLarge)
	header:SetHighlightFontObject(GameFontHighlightLarge)
	header:SetText(titleText)

	-- A width AND a height, so the header is rectangle-valid; the height is
	-- the title's, measured after SetText (our own string, never secret).
	header:SetSize(section:GetWidth(), title:GetStringHeight())

	-- The warning, hidden until UpdateSectionWarning shows it. The addon's
	-- tooltip icon (LFGF.CreateTooltipIcon, core/main.lua) takes hover only,
	-- so a click on it reaches this header and expands the section.
	local warning = LFGF.CreateTooltipIcon(header, WARNING_ICON_SIZE, ShowWarningTooltip)
	warning.Icon:SetTexture(WARNING_ICON_FILE)
	warning:SetPoint("LEFT", title, "RIGHT", TITLE_TO_WARNING_GAP, 0)
	header.Warning = warning

	header:SetScript("OnClick", function()
		ToggleSection(panel, section)
	end)

	section.Header = header
	return title
end

--- Lift a control on a collapsible section's title row one frame level above
--- its header, so the control keeps its own clicks. Children of one frame
--- share a level, and the header covers the whole row. Does nothing on a
--- section with no header.
local function RaiseOverHeader(section, frame)
	if section.Header then
		frame:SetFrameLevel(section.Header:GetFrameLevel() + 1)
	end
end

--- A titled section: header, rule, and a Content anchor to hang controls off.
---
--- Returned UNANCHORED, like the panel itself, so the caller decides where
--- sections sit relative to each other. The second one anchors to the first's
--- bottom and needs to know nothing about the filter row above it.
---
--- WITH A collapseKey the section is COLLAPSIBLE: a +/- header (BuildHeader)
--- holds the title, and the key is what QuinteLFGDB.collapsedFilterSections
--- saves. Its panel must then have a LayOutSections method, which the header
--- calls on every click. Without a key (the Whispers tab's section) the title
--- is a plain FontString, as before.
local function BuildSection(panel, titleText, collapseKey)
	-- WIDTH, NOT A RIGHT ANCHOR -- for the section and for everything in it.
	--
	-- RIGHT is a CENTRE-BEARING point: it pins the right edge AND the vertical
	-- centre. On a frame given no height that centre sits on its top edge, so
	-- `content:SetPoint("RIGHT", section, "RIGHT")` fought both the content's
	-- own TOPLEFT and its SetHeight, and the client resolved it by putting the
	-- rows somewhere they overlapped the next section's title.
	--
	-- A plain SetWidth carries no vertical constraint, so the top anchor and
	-- the height are the only things deciding the rect -- which is what this
	-- layout wants.
	--
	-- AND IT MUST HAVE BOTH. A frame with a width but no height is not
	-- RECTANGLE-VALID, and in the client nothing anchored to it resolves
	-- either: the first version of this fix dropped the section's RIGHT anchor
	-- without replacing the height it had been deriving, and every filter
	-- disappeared -- title, rule, checkboxes, the lot. The height is set by
	-- SizeSection, once the rows are known.
	local section = CreateFrame("Frame", nil, panel)
	section:SetWidth(panel.Layout.panelWidth - 2 * ROW_PADDING)

	local title
	if collapseKey then
		section.collapseKey = collapseKey
		title = BuildHeader(panel, section, titleText)
	else
		title = S.Text(section, 16, S.colors.gold)
		title:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
		title:SetText(titleText)
	end
	section.Title = title

	-- UI-LFG-DividerLine (AtlasInfo.lua:17077) -- Blizzard's own section rule,
	-- used exactly this way in Blizzard_LFGUtil/Mainline/PVPHelper.xml:273.
	-- That addon is NOT LoadOnDemand, so it is live on camelot.
	local divider = S.Fill(section, "ARTWORK", S.colors.line)
	divider:SetHeight(SECTION_RULE_HEIGHT)
	-- Off the SECTION's top, a title's height and the gap down -- not off the
	-- title, which on a collapsible section starts after its +/-. The rule
	-- stays at the section's left edge either way.
	divider:SetPoint("TOPLEFT", section, "TOPLEFT", 0,
		-(title:GetStringHeight() + SECTION_TITLE_TO_RULE_GAP))
	divider:SetWidth(section:GetWidth())
	section.Divider = divider

	-- An empty anchor frame rather than a sized one: whatever goes in decides
	-- the height, the same way the list column's width comes from its anchors.
	local content = CreateFrame("Frame", nil, section)
	content:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -SECTION_RULE_TO_CONTENT_GAP)
	content:SetWidth(section:GetWidth())
	section.Content = content

	-- WHAT THE NEXT SECTION HANGS OFF, and it is the content rather than the
	-- section frame itself. The section is never given a height.
	--
	-- Pinning the section's own BOTTOM to its content to get an automatic
	-- height is the obvious move and the client REFUSES it:
	--
	--   Action[SetPoint] failed because[Cannot anchor to a region dependent
	--   on it] ... Dependent ancestors: [...Divider] [...Content]
	--
	-- because Content hangs off the section's TOP through the title and the
	-- rule, so the section would depend on something depending on it.
	-- Dependency is tracked per REGION, not per axis -- "the y-chain has no
	-- cycle" is not a thing the client evaluates.
	--
	-- Anchoring the next section to THIS one's content inverts the
	-- dependency instead of creating one, and needs no height arithmetic.
	section.StackAnchor = content

	if collapseKey then
		SetSectionCollapsed(section, false)
	end

	return section
end

--- One role: checkbox, icon, label.
---
--- UICheckButtonTemplate (CheckButtonTemplates.xml:50) rather than Blizzard's
--- own LFGListingRoleButtonTemplate, which looks like the obvious reuse and is
--- a trap: its CheckButton OnClick ends with
---     if (not LFGListingFrame:SaveSoloRoles()) then
--- (Mainline/Blizzard_LFGVanilla_Listing.xml:57), so every click here would try
--- to save the PLAYER'S OWN listing roles. Its base LFGListingRoleTemplate is
--- cleaner but is 64x64 and greys itself out via UnitGetAvailableRoles in
--- OnLoad -- right for choosing your own roles, wrong for a browse filter. Both
--- also live in the LoadOnDemand addon, while this panel is built on first
--- /lfg and may precede it.
local function BuildRoleCheck(parent, role, checked)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check.roleField = role.field
	check:SetChecked(checked)
	if not S.IsClassic() then
		local base, pressed = check:GetNormalTexture(), check:GetPushedTexture()
		if base then base:SetAlpha(0) end
		if pressed then pressed:SetAlpha(0) end
		local border = S.Fill(check, "BACKGROUND", S.colors.line)
		border:SetSize(19, 19)
		border:SetPoint("CENTER")
		local body = S.Fill(check, "BORDER", S.colors.raised)
		body:SetSize(17, 17)
		body:SetPoint("CENTER")
		local mark = check:GetCheckedTexture()
		if mark then mark:SetVertexColor(unpack(S.colors.gold)) end
	end
	-- REMEMBERED ON THE BOX, so resetting does not have to know which section a
	-- box came from. The three sections do not agree on a default -- roles and
	-- classes start ON, group filters OFF -- so a reset that ticked everything,
	-- or untied everything, would be right about one section and wrong about
	-- another.
	check.defaultChecked = checked

	local icon = check:CreateTexture(nil, "ARTWORK")
	icon:SetAtlas(role.atlas, false)
	icon:SetSize(ROLE_ICON_SIZE, ROLE_ICON_SIZE)
	icon:SetPoint("LEFT", check, "RIGHT", ROLE_BOX_TO_ICON_GAP, 0)
	check.Icon = icon

	-- The template anchors Text LEFT to the checkbox's RIGHT
	-- (CheckButtonTemplates.xml:54-57), which is where the icon now sits. Same
	-- anchor point, so this REPLACES that anchor rather than adding to it.
	LFGF.ThemeFont(check.Text, 12, "text")
	check.Text:SetText(role.label)
	check.Text:SetPoint("LEFT", icon, "RIGHT", ROLE_ICON_TO_LABEL_GAP, 0)

	return check
end

--- Where one cell of a section's grid sits, relative to section.Content.
---
--- SHARED BY THE CHECKBOXES AND THE CLASS SECTION'S BULK BUTTONS, which is the
--- whole point of pulling it out: "the cell right of Hunter" has to mean the
--- same thing to both, and two copies of this arithmetic would drift the first
--- time a gap changed.
local function GridCell(column, rowIndex, columnWidth)
	return (column - 1) * columnWidth,
		-(rowIndex - 1) * (ROLE_ROW_HEIGHT + ROLE_ROW_TO_ROW_GAP)
end

--- Give a section's content and the section itself the height of `rowCount`
--- grid rows, and remember the count so a row added later knows where it goes.
---
--- The content frame is what the next section stacks under, so it is the one
--- that needs a height -- see StackAnchor. Every row, or a section with more
--- than one would have whatever follows it sitting on its last row.
---
--- The section's own height follows. A plain SetHeight, NOT an anchor to the
--- content -- anchoring the section to something that hangs off it is the
--- cycle the client refuses outright.
---
--- GetStringHeight is the title's rendered height
--- (SimpleFontStringAPIDocumentation.lua; SecretWhenAnchoringSecret only, so
--- it is readable here). Measuring beats guessing a line height for
--- GameFontNormalLarge, which is not a number any source states.
local function SizeSection(section, rowCount)
	local contentHeight = rowCount * ROLE_ROW_HEIGHT
		+ (rowCount - 1) * ROLE_ROW_TO_ROW_GAP
	section.Content:SetHeight(contentHeight)
	section.RowCount = rowCount

	-- A collapsed section stays as tall as its title and rule: the content
	-- keeps its height for when it is expanded.
	SetSectionHeight(section)
end

--- A section whose content is one row of role checkboxes, all checked.
---
--- Returns the section and the checks, so the caller names them -- the two
--- sections differ only in their title and their labels, and nothing about
--- building them should know which is which.
local function BuildRoleCheckSection(panel, title, rows, checkedByDefault, columnWidth, collapseKey)
	local section = BuildSection(panel, title, collapseKey)

	local bySet = {}
	local all = {}

	for rowIndex, row in ipairs(rows) do
		for column, role in ipairs(row) do
			local check = BuildRoleCheck(section.Content, role, checkedByDefault)

			-- A GRID: every box at its own cell, so nothing depends on how long
			-- its neighbour's label happens to be. That is what keeps "Has
			-- healer" under "Healer role available", and every class under the
			-- role above it.
			check:SetPoint("TOPLEFT", section.Content, "TOPLEFT",
				GridCell(column, rowIndex, columnWidth))

			bySet[role.set] = bySet[role.set] or {}
			table.insert(bySet[role.set], check)
			table.insert(all, check)
		end
	end

	SizeSection(section, #rows)

	-- What the collapsed section's warning asks (UpdateSectionWarning): every
	-- box at its default. A section that holds more than boxes extends this
	-- (BuildLevelRow, core/filterpanel.lua).
	section.FilterChecks = all
	function section:IsAtDefaults()
		return ChecksAtDefaults(self.FilterChecks)
	end

	return section, bySet
end

-- Published as one table, read by core/filterpanel.lua and
-- core/filterpanel_miscellaneous.lua: only what another file reads. The rest
-- (BuildRoleCheck, ChecksAtDefaults, the +/- atlases, the warning file, the
-- row gap) stays local until a second file needs it.
Shared.ROW_PADDING = ROW_PADDING
Shared.SECTION_TOP_GAP = SECTION_TOP_GAP
Shared.SECTION_TITLE_TO_RULE_GAP = SECTION_TITLE_TO_RULE_GAP
Shared.SECTION_RULE_HEIGHT = SECTION_RULE_HEIGHT
Shared.SECTION_RULE_TO_CONTENT_GAP = SECTION_RULE_TO_CONTENT_GAP
Shared.ROLE_ROW_HEIGHT = ROLE_ROW_HEIGHT
Shared.ROLE_ICON_SIZE = ROLE_ICON_SIZE
Shared.ROLE_BOX_TO_ICON_GAP = ROLE_BOX_TO_ICON_GAP
Shared.ROLE_ICON_TO_LABEL_GAP = ROLE_ICON_TO_LABEL_GAP
Shared.COLLAPSE_ICON_WIDTH = COLLAPSE_ICON_WIDTH
Shared.COLLAPSE_ICON_TO_TITLE_GAP = COLLAPSE_ICON_TO_TITLE_GAP
Shared.WARNING_ICON_SIZE = WARNING_ICON_SIZE
Shared.TITLE_TO_WARNING_GAP = TITLE_TO_WARNING_GAP
Shared.ROW_LABEL_INSET_X = ROW_LABEL_INSET_X
Shared.ROW_LABEL_TO_CONTROL_GAP = ROW_LABEL_TO_CONTROL_GAP

Shared.BuildSection = BuildSection
Shared.SizeSection = SizeSection
Shared.GridCell = GridCell
Shared.BuildRoleCheckSection = BuildRoleCheckSection
Shared.SetSectionCollapsed = SetSectionCollapsed
Shared.RaiseOverHeader = RaiseOverHeader
Shared.UpdateSectionWarning = UpdateSectionWarning

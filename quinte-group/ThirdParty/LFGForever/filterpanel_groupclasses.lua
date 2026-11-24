-- QuinteLFG -- core/filterpanel_groupclasses.lua
--
-- The Groups section's class filter: a dropdown in the free cell after "Has
-- healer" that hides, on Search, every group with a player of a class selected
-- in it. Solo players and your own listing are left alone; the list applies it
-- (core/listpanel.lua, GroupMatchesClassFilter).
--
-- A BUILDER, called once the Groups section exists: core/filterpanel.lua hands
-- LFGF.BuildGroupClassFilter the cell to fill, and still owns where every
-- control sits, what Search sends and what ApplyFilters restores. This file
-- owns the dropdown, its menu, text and tooltip, and the selection.
-- .claude/rules/group-class-filter.md
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

-- The class icon written into each menu row's text, the size Blizzard gives an
-- icon on a menu row (WorldMapBountyBoard.lua:668, RaidFinder.lua:261).
local MENU_ICON_SIZE = 16

-- How far into its cell the dropdown's frame starts. BY EYE, from the client:
-- the template draws its background 8 past the frame
-- (Mainline/MenuTemplates.xml:9-10), but that art has a transparent margin of
-- its own, and 8 in put the visible edge to the right of the "Damage role
-- available" box above. 4 lines it up. No source states the margin.
LFGF.GROUP_CLASS_DROPDOWN_INSET = 4

-- The template's text runs from 8 in to the left of its 27-wide arrow, which
-- sits 1 past the right edge (:14-24): 34 of the frame's width is never text.
-- Both published for MeasureLayout (core/filterpanel.lua).
LFGF.GROUP_CLASS_DROPDOWN_TEXT_INSETS = 34

--- A class in the plural, as it follows "No" in the dropdown and the tooltip.
local function PluralName(classFilename)
	return L["CLASS_PLURAL_" .. classFilename]
end

--- What the dropdown says, by the author's rule: NONE while it hides nothing
--- (no class selected, or every class), the one class in the plural ("No
--- Paladins"), and the count from two on ("No 2 classes"), in every language.
local function TextFor(hide)
	if #hide == 0 then
		return L.GROUP_CLASSES_NONE
	elseif #hide == 1 then
		return L.GROUP_CLASSES_ONE_FORMAT:format(PluralName(hide[1]))
	end
	return L.GROUP_CLASSES_COUNT_FORMAT:format(#hide)
end

--- Every text the dropdown can show, for MeasureLayout to find the widest.
function LFGF.GroupClassFilterTexts()
	local texts = { L.GROUP_CLASSES_NONE }
	for _, classFilename in ipairs(CLASS_SORT_ORDER) do
		table.insert(texts, L.GROUP_CLASSES_ONE_FORMAT:format(PluralName(classFilename)))
	end
	for count = 2, #CLASS_SORT_ORDER - 1 do
		table.insert(texts, L.GROUP_CLASSES_COUNT_FORMAT:format(count))
	end
	return texts
end

--- The classes hidden by, each in the plural and its class colour, joined
--- "A, B or C" with the language's own separators.
local function JoinColoured(hide)
	local names = {}
	for index, classFilename in ipairs(hide) do
		local name = PluralName(classFilename)
		local color = LFGF.ClassColor(classFilename)
		names[index] = color and color:WrapTextInColorCode(name) or name
	end
	if #names == 1 then
		return names[1]
	end
	return table.concat(names, L.GROUP_CLASSES_LIST_SEPARATOR, 1, #names - 1)
		.. L.GROUP_CLASSES_LIST_LAST_SEPARATOR .. names[#names]
end

--- The dropdown's tooltip, one gold line that wraps: what it does while it
--- hides nothing, and otherwise which groups it shows. Handed to Blizzard's
--- SetTooltip, which shows it on every hover (DropdownSelectionTextMixin,
--- MenuTemplates.lua:875-897); it reads the selection then, so it is never
--- out of date.
local function Tooltip(section)
	return function(tooltip)
		local hide = LFGF.GroupClassesToHide(section.excludedClasses)
		local text = L.GROUP_CLASSES_TOOLTIP
		if #hide > 0 then
			text = L.GROUP_CLASSES_EXCLUDED_TOOLTIP_FORMAT:format(JoinColoured(hide))
		end
		GameTooltip_AddNormalLine(tooltip, text, true)
	end
end

--- Bring the dropdown's text in line with the selection. SET WITH OverrideText
--- from our own state, as the Playstyle and Languages dropdowns are
--- (core/filterpanel_miscellaneous.lua): the selection also changes from
--- outside the menu (Reset filters, My filters, the restore, Defaults).
local function UpdateText(section)
	section.GroupClassDropdown:OverrideText(TextFor(LFGF.GroupClassesToHide(section.excludedClasses)))
end

--- A menu row: the class's icon, then its name, written into the row's own
--- text as Blizzard's menus write an icon (Blizzard_GuildControlUI.lua:74-75,
--- WorldMapBountyBoard.lua:668-671). The name is the one the class filter's
--- boxes show.
local function MenuText(classFilename)
	local name = L["CLASS_" .. classFilename]
	local atlas = LFGF.ClassIconAtlas(classFilename)
	if atlas then
		return CreateAtlasMarkup(atlas, MENU_ICON_SIZE, MENU_ICON_SIZE) .. " " .. name
	end
	return name
end

--- The menu: Select all and Unselect all first, the words of the class
--- filter's links, each answering Refresh so the menu stays open, as the
--- Languages menu's do; then the classes, in the class filter's order. A tick
--- keeps the menu open too: a checkbox's default response is Refresh
--- (MenuTemplates.lua:369-382). Every class selected is no filter, so Select
--- all leaves the dropdown saying NONE.
local function SetupMenu(section)
	section.GroupClassDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_LFGF_GROUP_CLASSES")

		local function SetAll(selected)
			for _, classFilename in ipairs(CLASS_SORT_ORDER) do
				section.excludedClasses[classFilename] = selected
			end
			UpdateText(section)
			return MenuResponse.Refresh
		end
		local function IsSelected(classFilename)
			return section.excludedClasses[classFilename] == true
		end
		local function SetSelected(classFilename)
			section.excludedClasses[classFilename] = not IsSelected(classFilename)
			UpdateText(section)
		end

		rootDescription:CreateButton(L.SELECT_ALL, SetAll, true)
		rootDescription:CreateButton(L.UNSELECT_ALL, SetAll, false)
		for _, classFilename in ipairs(CLASS_SORT_ORDER) do
			rootDescription:CreateCheckbox(MenuText(classFilename), IsSelected, SetSelected, classFilename)
		end
	end)
end

--- Build the class filter into `section` (the Groups section), its cell
--- starting `x` into the content, the dropdown centred on `rowCentre`, and
--- reaching the content's right edge. A child of the section's content, so the
--- tab system and collapsing hide it with the section.
function LFGF.BuildGroupClassFilter(panel, section, x, rowCentre)
	local left = x + LFGF.GROUP_CLASS_DROPDOWN_INSET
	local dropdown = LFGF.CreateDropdown(section.Content)
	dropdown:SetPoint("LEFT", section.Content, "TOPLEFT", left, rowCentre)
	dropdown:SetWidth(section.Content:GetWidth() - left)
	dropdown:SetTooltip(Tooltip(section))

	section.GroupClassDropdown = dropdown
	panel.GroupClassDropdown = dropdown

	-- Nothing selected: no group hidden, the start for a filter nobody has
	-- touched.
	section.excludedClasses = {}

	--- What the dropdown says right now, as a fresh table naming every class
	--- the client has: FilterSnapshot's `groupExcludedClasses`.
	function section:GetGroupExcludedClasses()
		local classes = {}
		for _, classFilename in ipairs(CLASS_SORT_ORDER) do
			classes[classFilename] = self.excludedClasses[classFilename] == true
		end
		return classes
	end

	--- Put the dropdown into the state `classes` describes, or nothing
	--- selected for nil: ApplyFilters (the restore at build, Reset filters, My
	--- filters, Defaults). Only a class the client has, named with true, is
	--- selected, so a record from before the filter existed selects nothing.
	function section:SetGroupExcludedClasses(classes)
		self.excludedClasses = {}
		if type(classes) == "table" then
			for _, classFilename in ipairs(CLASS_SORT_ORDER) do
				if classes[classFilename] == true then
					self.excludedClasses[classFilename] = true
				end
			end
		end
		UpdateText(self)
	end

	-- The collapsed section's warning (core/filterpanel_shared.lua,
	-- UpdateSectionWarning) asks whether the section is at its defaults: the
	-- boxes, and this filter hiding nothing.
	local boxesAtDefaults = section.IsAtDefaults
	function section:IsAtDefaults()
		return boxesAtDefaults(self) and #LFGF.GroupClassesToHide(self.excludedClasses) == 0
	end

	SetupMenu(section)
	UpdateText(section)
	return dropdown
end

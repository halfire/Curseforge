-- QuinteLFG -- core/minimap.lua
--
-- The two ways into the window from outside it, besides /lfg and the tab on
-- Blizzard's Group Finder:
--
--   * a BUTTON ON THE RIM OF THE MINIMAP, which the player can drag around it;
--   * an ENTRY IN BLIZZARD'S ADDON COMPARTMENT, the AddOns dropdown by the
--     minimap, declared by three lines in the TOC.
--
-- Both do the same thing through LFGF.OnLauncherClick: a left click opens or
-- closes the window, a right click opens the settings page.
--
-- NO LIBRARIES. Every addon in examples/ that puts a button on the minimap
-- uses LibDataBroker + LibDBIcon, except CharacterNotes (a Forever addon) and
-- EllesmereUI, which build it by hand exactly as this file does. The art, the
-- sizes and the rim maths are LibDBIcon's (examples/BugSack/Libs/LibDBIcon-1.0,
-- MINOR 56), cited line by line below; nothing of the library is embedded.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
-- Every word this file shows, from core/locale.lua (loaded first).
local L = LFGF.L

local BUTTON_NAME = "QuinteLFGMinimapButton"

-- 31x31, strata MEDIUM, frame level 8, both locked, as LibDBIcon creates every
-- button (LibDBIcon-1.0.lua:258-261, :483).
local BUTTON_SIZE = 31
local BUTTON_STRATA = "MEDIUM"
local BUTTON_LEVEL = 8

-- LibDBIcon's MAINLINE sizes (:533-535, :572-574, :607-610). It picks them on
-- WOW_PROJECT_ID == WOW_PROJECT_MAINLINE, which Forever reports, so these are
-- what every LibDBIcon button on this client already looks like.
local BORDER_SIZE = 50
local BACKGROUND_SIZE = 24
local ICON_SIZE = 18

-- Blizzard's own files, each also drawn by Blizzard's camelot-loaded XML:
-- the ring by Mainline/GroupLootFrame.xml:94, the backing by the world map's
-- templates (Blizzard_WorldMap/Blizzard_WorldMapTemplates.xml:18, loaded with
-- no condition by Blizzard_WorldMap_Mainline.toc:16), the round highlight
-- by the minimap's own buttons (Mainline/Minimap.xml:272). LibDBIcon passes
-- the same three as file IDs 136430, 136467, 136477 (:532, :571, :497).
local BORDER_FILE = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BACKGROUND_FILE = "Interface\\Minimap\\UI-Minimap-Background"
local HIGHLIGHT_FILE = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

-- WHERE ON THE RIM, in degrees counter-clockwise from the right (east), saved
-- as minimapAngle. Its default, 225 (bottom left, LibDBIcon's), is with the
-- key in core/db.lua.
local DEFAULT_ANGLE = LFGF.MINIMAP_DEFAULT_ANGLE

-- The rim is half the minimap's width (and height) plus this, LibDBIcon's
-- radius (:19, :163-164). Read from the minimap on every placement rather than
-- fixed: CharacterNotes hard-codes 110, which is wrong for any other size.
local RADIUS_PADDING = 5

-- THE SHAPE. Blizzard's Forever minimap is round (Camelot/Minimap.lua:42 masks
-- it with ui-hud-minimap-frame-generic-mask), but a minimap-skin addon can make
-- it square, and says so by defining the GLOBAL GetMinimapShape:
-- EnhanceQoL's makeSquareMinimap sets a square mask and
-- `function GetMinimapShape() return "SQUARE" end`
-- (EnhanceQoL/EnhanceQoL.lua:4411-4425), Leatrix Plus does the same
-- (Leatrix_Plus.lua:5158). Blizzard never defines it: no occurrence in
-- wow-ui-source or the client dump. LibDBIcon reads it on every placement
-- (:161), so it is the contract every minimap button on the player's map
-- already follows.
--
-- On "SQUARE" the button takes LibDBIcon's square branch (:166-172): the
-- direction scaled to sqrt(2) * half-size - CORNER_INSET, then clamped to the
-- half-size. Along an edge its centre sits RADIUS_PADDING outside the map,
-- beside every LibDBIcon button; near a corner it is pulled in about 7.
-- Only ROUND and SQUARE are handled, by the author's decision; LibDBIcon's
-- corner, side and tricorner shapes, and any other answer, read as round.
local SQUARE_SHAPE = "SQUARE"
local CORNER_INSET = 10

-- The press: the icon moves one pixel down and right while held, the nudge
-- MiniMapButtonTemplate gives its icon (Shared/MinimapButtonTemplate.lua:7)
-- and UIMenuButtonStretchMixin gives its own (SharedUIPanelTemplates.lua:933).
-- By AdjustPointsOffset rather than LibDBIcon's texcoord crop: the icon is an
-- ATLAS, and SetTexCoord would overwrite the coordinates SetAtlas set.
local PRESS_X, PRESS_Y = 1, -1

local LEFT_CLICK_HINT = L.MINIMAP_LEFT_CLICK
local RIGHT_CLICK_HINT = L.MINIMAP_RIGHT_CLICK
local DRAG_HINT = L.MINIMAP_DRAG

--- What either launcher does with a click. Left (or anything else): open or
--- close the window, exactly as /lfg does, in combat too (the window is a
--- plain frame, not a UI panel; core/window.lua). Right: the settings page.
function LFGF.OnLauncherClick(mouseButton)
	if mouseButton == "RightButton" then
		LFGF.OpenSettings()
	else
		LFGF.ToggleWindow()
	end
end

--- The tooltip both launchers show, owned by whatever the mouse is over.
--- The drag hint only where there is something to drag.
local function ShowLauncherTooltip(owner, canDrag)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText(LFGF.TITLE, 1, 1, 1)
	GameTooltip:AddLine(LEFT_CLICK_HINT)
	GameTooltip:AddLine(RIGHT_CLICK_HINT)
	if canDrag then
		GameTooltip:AddLine(DRAG_HINT)
	end
	GameTooltip:Show()
end

-------------------------------------------------------
---------- The addon compartment entry
-------------------------------------------------------
-- Declared in the TOC as ## AddonCompartmentFunc / FuncOnEnter / FuncOnLeave.
-- Blizzard's AddonCompartmentMixin:RegisterAddons reads those at
-- PLAYER_ENTERING_WORLD, takes the icon from ## IconAtlas, and calls
-- _G[<name>] (:99) -- so these three must be GLOBALS, namespaced because every
-- addon's globals share one table (Blizzard_Minimap/Mainline/
-- AddonCompartment.lua:102-149; the icon, :111). It calls forceinsecure() first
-- (:121), which
-- is fine: opening our own window is not protected work.
--
-- Whether the compartment shows on Forever is for the client to say: its file
-- loads under [AllowLoadGameType mainline] (Blizzard_Minimap.toc), which
-- includes camelot, and it hides itself under the UserAddonsDisabled game rule
-- (:166-173). If it is absent, the TOC lines are simply never read.

--- Click: called as (addonName, buttonName) (AddonCompartment.lua:124, :128).
function QuinteLFG_OnAddonCompartmentClick(_, mouseButton)
	LFGF.OnLauncherClick(mouseButton)
end

--- Enter: called as (addonName, menuButton) (:109).
function QuinteLFG_OnAddonCompartmentEnter(_, menuButton)
	ShowLauncherTooltip(menuButton, false)
end

--- Leave: called as (addonName, menuButton) (:116).
function QuinteLFG_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

-------------------------------------------------------
---------- The minimap button
-------------------------------------------------------

--- The saved angle, or the default. DEFENSIVE, like every reader of
--- QuinteLFGDB: it is a file on disk, and a string, a NaN or an infinity
--- (whose cos is NaN) must not reach SetPoint.
local function SavedAngle()
	local angle = LFGF.SavedValue("minimapAngle")
	if not LFGF.IsFiniteNumber(angle) then
		return DEFAULT_ANGLE
	end
	return angle
end

--- Whether a minimap-skin addon says the minimap is square. Asked on every
--- placement, never cached, so a skin addon that loads after us is seen at
--- login and during every drag.
local function MinimapIsSquare()
	return type(GetMinimapShape) == "function" and GetMinimapShape() == SQUARE_SHAPE
end

--- Put the button on the rim at `angle` degrees: on the circle, or along the
--- edge of a square minimap. One anchor, to the minimap's centre, replaced
--- each time.
local function Place(button, angle)
	local radians = math.rad(angle)
	local x, y = math.cos(radians), math.sin(radians)
	local halfWidth = Minimap:GetWidth() / 2 + RADIUS_PADDING
	local halfHeight = Minimap:GetHeight() / 2 + RADIUS_PADDING
	if MinimapIsSquare() then
		local reachX = math.sqrt(2 * halfWidth * halfWidth) - CORNER_INSET
		local reachY = math.sqrt(2 * halfHeight * halfHeight) - CORNER_INSET
		x = math.max(-halfWidth, math.min(x * reachX, halfWidth))
		y = math.max(-halfHeight, math.min(y * reachY, halfHeight))
	else
		x, y = x * halfWidth, y * halfHeight
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

--- While dragging: the angle from the minimap's centre to the cursor.
---
--- GetCursorPosition is in UNSCALED screen pixels (InputDocumentation.lua
--- :19-28) while GetCenter is in the minimap's own scale, so the cursor is
--- divided by the MINIMAP's effective scale, as LibDBIcon does. Dividing by
--- UIParent's instead drifts as soon as the minimap cluster is scaled. The
--- same division Blizzard's map canvas does
--- (MapCanvas_ScrollContainerMixin.lua:818-819).
---
--- GetCenter may return nothing (MayReturnNothing) and is
--- SecretWhenAnchoringSecret; GetEffectiveScale is secret for a frame given a
--- secret scale aspect (SimpleRegionAPIDocumentation.lua:40). Neither applies
--- to the minimap, but either would error in the arithmetic below, so an
--- unreadable answer (LFGF.ReadableNumbers) skips this frame's move rather
--- than breaking the drag.
local function FollowCursor(button)
	local centerX, centerY = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	centerX, centerY, scale, cursorX, cursorY =
		LFGF.ReadableNumbers(centerX, centerY, scale, cursorX, cursorY)
	if centerX == nil then
		return
	end

	cursorX, cursorY = cursorX / scale, cursorY / scale
	button.dragAngle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX)) % 360
	Place(button, button.dragAngle)
end

--- Press and release move the icon one pixel and back -- once, however many
--- downs arrive, and back again if the button is hidden mid-press (what
--- MiniMapButtonTemplate's OnHide does, MinimapButtonTemplate.xml:5-9).
local function Press(button)
	if not button.isDown then
		button.isDown = true
		button.Icon:AdjustPointsOffset(PRESS_X, PRESS_Y)
	end
end

local function Release(button)
	if button.isDown then
		button.isDown = false
		button.Icon:AdjustPointsOffset(-PRESS_X, -PRESS_Y)
	end
end

local function BuildButton()
	local button = CreateFrame("Button", BUTTON_NAME, Minimap)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameStrata(BUTTON_STRATA)
	button:SetFixedFrameStrata(true)
	button:SetFrameLevel(BUTTON_LEVEL)
	button:SetFixedFrameLevel(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture(HIGHLIGHT_FILE)

	-- Three layers, back to front, laid out as LibDBIcon's mainline branch
	-- lays them out: backing and icon centred, the ring from the top left,
	-- where its art is drawn.
	button.Background = button:CreateTexture(nil, "BACKGROUND")
	button.Background:SetTexture(BACKGROUND_FILE)
	button.Background:SetSize(BACKGROUND_SIZE, BACKGROUND_SIZE)
	button.Background:SetPoint("CENTER", button, "CENTER", 0, 0)

	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAtlas(LFGF.ICON_ATLAS)
	button.Icon:SetSize(ICON_SIZE, ICON_SIZE)
	button.Icon:SetPoint("CENTER", button, "CENTER", 0, 0)

	button.Border = button:CreateTexture(nil, "OVERLAY")
	button.Border:SetTexture(BORDER_FILE)
	button.Border:SetSize(BORDER_SIZE, BORDER_SIZE)
	button.Border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

	button:SetScript("OnClick", function(_, mouseButton)
		LFGF.OnLauncherClick(mouseButton)
	end)

	button:SetScript("OnMouseDown", Press)
	button:SetScript("OnMouseUp", Release)
	button:SetScript("OnHide", Release)

	button:SetScript("OnEnter", function(self)
		if not self.dragging then
			ShowLauncherTooltip(self, true)
		end
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	-- THE ONUPDATE EXISTS ONLY WHILE DRAGGING, and the angle is written to the
	-- saved table once, when the drag ends -- EllesmereUI's shape. LibDBIcon
	-- and CharacterNotes write on every frame of the drag.
	button:SetScript("OnDragStart", function(self)
		self.dragging = true
		self.dragAngle = SavedAngle()
		self:LockHighlight()
		GameTooltip_Hide()
		self:SetScript("OnUpdate", FollowCursor)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
		self.dragging = false
		LFGF.SaveValue("minimapAngle", self.dragAngle)
		Place(self, self.dragAngle)
	end)

	Place(button, SavedAngle())
	button:SetShown(LFGF.ShowMinimapButton())

	-- AGAIN AT LOGIN, for a skin addon that defines GetMinimapShape after our
	-- ADDON_LOADED: LibDBIcon waits for PLAYER_LOGIN "to let any
	-- GetMinimapShape addons load up" (:318-335). Runs at once if the player
	-- is already logged in (EventUtil.lua:77-84).
	EventUtil.ContinueOnPlayerLogin(function()
		Place(button, SavedAngle())
	end)

	-- "Show minimap button" moved (core/settings.lua). The button is built
	-- either way, so the change is a show or a hide, never a rebuild.
	EventRegistry:RegisterCallback(LFGF.EVENT_MINIMAP_BUTTON_CHANGED, function(_, shown)
		button:SetShown(shown)
	end, button)

	return button
end

-- After ADDON_LOADED, when QuinteLFGDB -- the saved angle, and whether the
-- button is wanted -- has been read from disk. Nothing here needs
-- core/settings.lua's own ADDON_LOADED callback to have run first: load
-- callbacks run in no promised order (EventUtil.lua:67-102), and both reads
-- fall back (SavedAngle above, LFGF.ShowMinimapButton) to the defaults
-- settings.lua would write on a first install.
local button
EventUtil.ContinueOnAddOnLoaded(addonName, function()
	button = button or BuildButton()
end)

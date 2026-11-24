-- QuinteLFG -- core/slash.lua
--
-- The /lfg slash command.
--
-- `/lfg` is unclaimed on this client. Blizzard ships /lfd, /df and
-- /dungeonfinder (SLASH_DUNGEONS1-6) and /lfr (SLASH_RAIDFINDER5-6), but no
-- SLASH_* global anywhere in the 993 in GlobalStrings/enUS.lua has the value
-- "/lfg" -- and on Forever those Dungeon/Raid Finder commands lead nowhere
-- anyway, because Blizzard_GroupFinder is gated off camelot entirely
-- (Blizzard_GroupFinder.toc:10, ## ExcludeLoadGameType: camelot).

-- The registry key. SlashCmdList is ONE global table shared by every addon on
-- the machine, so the key is namespaced rather than named after the command:
-- keying on "LFG" would take a name any other addon may also want, and the
-- last one loaded would silently win.
--
-- This is also why Blizzard's own RegisterNewSlashCommand
-- (SlashCommandsRegistry.lua:42-51) is not used here. It does exactly what the
-- two lines below do, but derives the key from the command word
-- (`local name = string.upper(command)`), so it would register us as "LFG".
-- It also requires a second alias and would build "/"..nil without one.
local COMMAND_KEY = "QUINTELFG"

-- The addon's private table, the second of the two varargs the client passes
-- every addon file. core/window.lua puts ToggleWindow on it, and the .toc loads
-- that file first.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
local L = LFGF.L

-- Registration is the pair of globals Blizzard's dispatcher reads:
--
--   * SLASH_<KEY><n> -- the tokens, walked from 1 upwards until one is nil
--     (ChatFrameUtil.lua:795-804). One token, so there is no SLASH_..."2".
--   * SlashCmdList[<KEY>] -- the handler.
--
-- ChatFrameUtil.ImportAllListsToHash() folds the pair into hash_SlashCmdList
-- and it runs on EVERY parse (ChatFrameEditBox.lua:253), so registering at file
-- scope like this is picked up whenever the player first types the command --
-- there is no ordering requirement against Blizzard's own setup pass.
--
-- Assigned through _G rather than as bare global statements because these are
-- dynamic names built from COMMAND_KEY; writing them out literally would let
-- the key and the token drift apart silently.
-- LFGF.SLASH_COMMAND, not a literal: core/main.lua's load greeting names the
-- same constant, so the command the player is told to type and the command
-- that is registered cannot drift apart.
_G["SLASH_" .. COMMAND_KEY .. "1"] = LFGF.SLASH_COMMAND

-- The handler's signature is (msg, editBox): the trimmed argument string and
-- the chat edit box the command was typed into (ChatFrameEditBox.lua:266-267).
-- Neither is used -- `/lfg` takes no arguments -- and naming unused parameters
-- is noise, so they are simply not declared.
--
-- LFGF.ToggleWindow is resolved at CALL time, not load time, so this file does
-- not care that core/window.lua defines it; the .toc ordering is for clarity,
-- not correctness.
_G.SlashCmdList[COMMAND_KEY] = function()
	LFGF.ToggleWindow()
end

-- The key binding, Bindings.xml's QUINTELFG_TOGGLE: the other way to open the
-- window from the keyboard, so it does what /lfg does.
--
-- Blizzard's Keybindings page titles the section _G[category]
-- (Keybindings.lua:220-226) and labels the row BINDING_NAME_<action>
-- (BindingUtil.lua:142-148), reading both when it builds its rows -- at the
-- earliest on this addon's ADDON_LOADED, after this file has run. The section
-- is the addon's name, which is never translated; the label is LFGF.L's, so a
-- language pack translates it.
BINDING_HEADER_QUINTELFG = LFGF.TITLE
BINDING_NAME_QUINTELFG_TOGGLE = L.BINDING_OPEN_WINDOW

-- What the binding's body calls. A binding body runs in the global
-- environment, so this is a global, namespaced like the compartment's
-- (core/minimap.lua). It works in combat: the window is a plain frame.
function QuinteLFG_ToggleWindow()
	LFGF.ToggleWindow()
end

-- The Search key, Bindings.xml's "CLICK QuinteLFGSearchKeyButton:LeftButton":
-- a key bound to a BUTTON, so the client clicks this button when the key is
-- pressed. No script calls Search: the player reports a script that does is
-- refused, and a Forever addon's own note says the same of /click from a
-- macro while its key-bound buttons work. The click runs the Search button's
-- own search (LFGF.SearchFromKey, core/window.lua, looked up when pressed).
--
-- The NAME is saved with the player's key, like a binding's action: renaming
-- it unbinds every player.
--
-- SHOWN, WITH NO SIZE AND NO ANCHOR: nothing to see, no rect a mouse can hit,
-- and never hidden, because the sources do not say a bound key clicks a hidden
-- button. Not the window's Search button itself, which exists only once the
-- window is built and is hidden while the window is closed.
--
-- THE PRESS ALONE: a bound key sends a press click and then a release click,
-- and Blizzard's action bars act on the press by default (ActionButtonUseKeyDown
-- is "1", CVars.lua:14). One search per key press, as the key goes down.
local SEARCH_KEY_BUTTON = "QuinteLFGSearchKeyButton"
local searchKey = CreateFrame("Button", SEARCH_KEY_BUTTON, UIParent)
searchKey:RegisterForClicks("LeftButtonDown")
searchKey:SetScript("OnClick", function()
	LFGF.SearchFromKey()
end)

-- The row's label: Blizzard's Search, the Search button's own word, so the
-- client and every language pack already translate it.
_G["BINDING_NAME_CLICK " .. SEARCH_KEY_BUTTON .. ":LeftButton"] = LFGF.SEARCH_ACTION_LABEL

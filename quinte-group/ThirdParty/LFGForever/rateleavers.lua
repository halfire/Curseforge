-- QuinteLFG -- core/rateleavers.lua
--
-- After players leave your party, one chat line asks whether you want to rate
-- them, with a link that opens the Player ratings tab. The line names nobody,
-- posts at most once every five minutes, and only while the Player ratings
-- setting is on. Parties only: nothing in a raid. It runs from login, whether
-- or not the window was ever opened. .claude/rules/rate-leavers.md

local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end
local L = LFGF.L

-------------------------------------------------------
---------- The line
-------------------------------------------------------
local COOLDOWN_SECONDS = 5 * 60
local LINK_ACTION = "ratings"

--- When the line was last posted (GetTime), or nil. Kept in memory only, so a
--- /reload or a login starts the wait again.
local lastPosted

--- Blizzard's addon link type: a click raises EventRegistry "SetItemRef" and
--- nothing else, with no tooltip (ItemRefHandlersShared.lua, the AddOn
--- handler; LinkUtil.FormatLink, LinkUtil.lua). In the light blue Blizzard
--- wraps its own chat-settings link in (Mainline/ChatFrameOverrides.lua); a
--- colour generated at load, so a missing one leaves the link plain.
local function RateLink()
	local link = LinkUtil.FormatLink(LinkTypes.AddOn, "[" .. L.RATE_LEAVERS_LINK .. "]",
		addonName, LINK_ACTION)
	if LIGHTBLUE_FONT_COLOR then
		return LIGHTBLUE_FONT_COLOR:WrapTextInColorCode(link)
	end
	return link
end

--- Post the line, unless the Player ratings setting is off or the last one
--- was under five minutes ago. A departure inside the wait is dropped, not
--- kept for later, and only a posted line restarts the wait.
local function OfferRating()
	if not LFGF.ShowPlayerRatings() then
		return
	end
	local now = GetTime()
	if lastPosted ~= nil and now - lastPosted < COOLDOWN_SECONDS then
		return
	end
	lastPosted = now
	LFGF.Print(L.RATE_LEAVERS_FORMAT:format(RateLink()))
end

-------------------------------------------------------
---------- Noticing a departure
-------------------------------------------------------
-- No event names who left: GROUP_ROSTER_UPDATE carries nothing
-- (PartyInfoDocumentation.lua), and Blizzard's own "X leaves the party." line
-- is secret in dungeons and raids (CHAT_MSG_SYSTEM is
-- SecretInChatMessagingLockdown, ChatInfoDocumentation.lua). The line names
-- nobody, so the count is enough: fewer other players than at the last look
-- means someone left, or you did. One player leaving while another joins in
-- the same update keeps the count, and posts nothing.

--- The other players in your party: 0 in no group, nil in a raid (parties
--- only) or when an answer cannot be read. Both calls are undocumented engine
--- API, asked in the order Blizzard's own party loop asks them
--- (Blizzard_CooldownBroadcaster.lua, GetOnlineGroupMemberGUIDs).
local function OtherPartyMembers()
	if LFGF.Readable(IsInRaid(), nil) ~= false then
		return nil
	end
	return LFGF.Readable(GetNumSubgroupMembers(), nil)
end

--- The count at the last look, nil when there was none to compare with.
--- Taken first at load, so a party already formed before a /reload posts
--- nothing; one that arrives after a login only counts up.
local lastCount = OtherPartyMembers()

local function OnPartyChanged()
	if Quintessence.GuildStatus() ~= "ok" then lastCount = nil; return end
	local count = OtherPartyMembers()
	if count ~= nil and lastCount ~= nil and count < lastCount then
		OfferRating()
	end
	lastCount = count
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:SetScript("OnEvent", OnPartyChanged)

-------------------------------------------------------
---------- The click
-------------------------------------------------------
local OUR_LINK = LinkTypes.AddOn .. ":" .. addonName .. ":" .. LINK_ACTION

--- Blizzard hands every addon's link to this one event, so only our own exact
--- link counts. Any mouse button opens: Blizzard does nothing else with an
--- addon link and never puts one into the chat box. The link is read through
--- LFGF.Readable first, because one clicked in someone else's line could be
--- secret in lockdown, and a secret compared with a string may error. Opening
--- works in combat: the window is a plain frame.
EventRegistry:RegisterCallback("SetItemRef", function(_, link)
	if LFGF.Readable(link, nil) ~= OUR_LINK then
		return
	end
	if not LFGF.ShowPlayerRatings() then
		LFGF.Print(L.RATE_LEAVERS_TURNED_OFF_FORMAT:format(L.PLAYER_RATINGS))
		return
	end
	LFGF.OpenPlayerRatings()
end, frame)

local addonName, Core = ...
-- Espace privé du moteur, distinct du conteneur et de l'ancien addon autonome.
local E = {}
Core.TravelEngine = E
E.Share = function() end
E.FamilyHints = { AddQuestMenu = function() end }
local defaults = { enabled = true, automatic = false, worldMap = true, minimap = true,
    arrow = false, compass = false, steps = false, destination = false,
    transportPins = false, transportTimes = false, alerts = false, sound = false }
Core.TravelDefaults = defaults
function E.Preferences()
    QuintessenceDB = type(QuintessenceDB) == 'table' and QuintessenceDB or {}
    if type(QuintessenceDB.travel) ~= 'table' then QuintessenceDB.travel = {} end
    local prefs = QuintessenceDB.travel
    for k, v in pairs(defaults) do if type(prefs[k]) ~= 'boolean' then prefs[k] = v end end
    return prefs
end
local controlled = { worldMap = { 'quinteWorldMap' }, minimap = { 'quinteMinimap' },
    arrow = { 'arrow' }, compass = { 'compass' }, steps = { 'journeyTracker' },
    destination = { 'destinationPin' }, transportPins = { 'pins', 'transit', 'portals', 'mapFlightMasters', 'minimapPins' },
    transportTimes = { 'tracker' }, alerts = { 'alerts', 'flightPathReminder' }, sound = { 'alertSound', 'arrivalSound' } }
local hidden = { 'share', 'stats', 'statsShare', 'whatsNew', 'tomtom', 'tomtomFollow', 'restedxp',
    'resumeJourney', 'corpse', 'minimapButton', 'mapRoutes' }
local function assign(target)
    local prefs = E.Preferences()
    target.journey = prefs.enabled
    for key, fields in pairs(controlled) do
        for _, field in ipairs(fields) do target[field] = prefs.enabled and prefs[key] or false end
    end
    for _, key in ipairs(hidden) do target[key] = false end
end
function E.ConfigureDefaults(target)
    assign(target)
    if E.db then assign(E.db) end
end
-- Le moteur possède ce tableau ; aucune modification des cadres ou réglages de Blizzard.
function E.ApplyPreferences()
    if not E.db then return end
    assign(E.db)
    for _, name in ipairs({ 'RefreshMap', 'RefreshMinimapPins', 'RefreshTracker', 'RefreshCompass',
        'RefreshQuinteRoute', 'RefreshGuideStops' }) do
        if type(E[name]) == 'function' then Core.Run('voyages : ' .. name, E[name]) end
    end
    if E.JourneyGuide and E.JourneyGuide.Retarget then Core.Run('voyages : direction', E.JourneyGuide.Retarget) end
    if E.WakeTravel then Core.Run('voyages : actualisation', E.WakeTravel) end
end
-- Compatibilité des menus internes du moteur, sans une deuxième page de réglages.
function E.OpenSettings() Core.UI.Open('settings') end
function E.RefreshOptionsButton() end
function E.SetOption(key, value)
    for pref, fields in pairs(controlled) do
        for _, field in ipairs(fields) do
            if field == key and Core.Navigation then return Core.Navigation.SetOption(pref, value) end
        end
    end
    if E.db then E.db[key] = value; E.ApplyPreferences() end
end
local charDB = {}
function E.CharacterDB() return charDB end
local binding = CreateFrame('Frame')
local bound = false
binding:RegisterEvent('PLAYER_LOGIN')
binding:SetScript('OnEvent', function(self)
    if bound then return end
    bound = true
    if self.UnregisterEvent then self:UnregisterEvent('PLAYER_LOGIN') end
    local db = QuintessenceDB
    if type(db) ~= 'table' then return end
    if type(db.travelCharacters) ~= 'table' then db.travelCharacters = {} end
    local key = Core.Key()
    local saved = db.travelCharacters[key]
    if type(saved) == 'table' then for k, v in pairs(saved) do charDB[k] = v end end
    db.travelCharacters[key] = charDB
end)

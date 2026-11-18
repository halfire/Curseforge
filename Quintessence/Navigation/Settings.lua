local _, Core = ...
local N, S = Core.Navigation, Core.Style
local panel, buttons
local rows = {
    { 'enabled', 'Activer le guidage', 'Couper arrête aussi le trajet en cours.' },
    { 'automatic', 'Démarrage automatique', 'Sur un marqueur natif ; sinon, bouton Chemin.' },
    { 'worldMap', 'Chemin sur la grande carte', 'Tracé et destination du voyage.' },
    { 'minimap', 'Chemin sur la minicarte', 'Tracé du passage en cours.' },
    { 'arrow', 'Flèche et distance', 'Direction du prochain passage.' },
    { 'compass', 'Boussole de voyage', 'Orientation affichée en haut de l’écran.' },
    { 'steps', 'Liste des étapes', 'Résumé du trajet dans le suivi des objectifs.' },
    { 'destination', 'Repère à l’écran', 'Marqueur visible dans le monde.' },
    { 'transportPins', 'Icônes de transport', 'Bateaux, portails et maîtres de vol.' },
    { 'transportTimes', 'Horaires des transports', 'Départs à proximité dans le suivi.' },
    { 'alerts', 'Alertes de voyage', 'Arrivées des bateaux et nouveaux maîtres de vol.' },
    { 'sound', 'Sons de voyage', 'Alertes et arrivée à destination.' },
}
function N.RefreshSettings()
    if not panel then return end
    local prefs = N.Options()
    for key, button in pairs(buttons) do
        button:SetLabel(prefs[key] and 'Activé' or 'Désactivé')
        button:SetActive(prefs[key])
    end
    panel.state:SetText(prefs.enabled and 'Guidage actif · affichage personnalisable' or 'Guidage désactivé · les marqueurs restent disponibles')
    local entrancePins = Core.DungeonEntrancePins
    panel.entrancePins:SetShown(entrancePins ~= nil)
    if entrancePins then
        local active = entrancePins.Enabled()
        panel.entrancePins:SetLabel(active and 'Entrées de donjon : affichées' or 'Entrées de donjon : masquées')
        panel.entrancePins:SetActive(active)
    end
    if Core.Characters then Core.Characters.RefreshSettings() end
end
local function createTravel(parent)
    panel = CreateFrame('Frame', nil, parent)
    panel:SetSize(1078, 658) -- toute la zone de contenu (1.39.0), textes de la même taille
    buttons = {}
    local title = S.Text(panel, 20, S.colors.text); title:SetPoint('TOPLEFT', 0, -2); title:SetText('Réglages — Voyages')
    local hint = S.Text(panel, 12, S.colors.muted); hint:SetPoint('TOPLEFT', 0, -32); hint:SetWidth(1068); hint:SetWordWrap(true)
    hint:SetText('Choisis les informations visibles. Les changements s’appliquent immédiatement et restent enregistrés.')
    panel.state = S.Text(panel, 12, S.colors.gold); panel.state:SetPoint('TOPLEFT', 0, -72)
    local stop = S.Button(panel, 'Arrêter le trajet', 140, 26, 'ghost'); stop:SetPoint('TOPRIGHT', 0, -65)
    stop:SetScript('OnClick', function() N.Clear(); Core.Print('Guidage Quintessence arrêté.') end)
    for i, row in ipairs(rows) do
        local key = row[1]
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        local box = S.Box(panel, S.colors.panel, S.colors.line)
        box:SetSize(532, 46); box:SetPoint('TOPLEFT', col * 546, -110 - line * 52)
        local label = S.Text(box, 12, S.colors.text); label:SetPoint('TOPLEFT', 10, -8); label:SetWidth(410); label:SetText(row[2])
        local help = S.Text(box, 10, S.colors.muted); help:SetPoint('TOPLEFT', 10, -26); help:SetWidth(512); help:SetText(row[3])
        local toggle = S.Button(box, '', 90, 22, 'ghost'); toggle:SetPoint('TOPRIGHT', -8, -4)
        toggle:SetScript('OnClick', function() N.SetOption(key, not N.Options()[key]) end)
        buttons[key] = toggle
    end
    local note = S.Text(panel, 11, S.colors.muted); note:SetPoint('TOPLEFT', 0, -438); note:SetWidth(1068); note:SetWordWrap(true)
    note:SetText('Chemin utilise les passages du terrain. Bateaux, vols et portails peuvent faire partie du trajet même si leurs icônes sont masquées. Moteur Shortest Path Forever, de cjber, intégré à Quintessence (GPL).')
    panel.entrancePins = S.Button(panel, '', 242, 24, 'ghost')
    panel.entrancePins:SetPoint('TOPLEFT', 525, -65)
    panel.entrancePins:SetScript('OnClick', function()
        if Core.DungeonEntrancePins then Core.DungeonEntrancePins.Toggle(); N.RefreshSettings() end
    end)
    if Core.Characters then Core.Characters.AddSettings(panel) end
    N.RefreshSettings()
    return panel
end
-- Les préférences du profil et le parcours de bienvenue appartiennent au conteneur de base.
local Settings={}
Core.Settings=Settings
local holder, profilePanel, travelPanel, displayPanel, tabs
-- Onglets de Réglages : Affichage (1.49.0 : interface, taille et synchro, venues de l'ancien accueil), Profil, Voyages
local function tabOf() return (Core.settingsTab == 'travel' or Core.settingsTab == 'display') and Core.settingsTab or 'profile' end
function Settings.Refresh()
 if not holder then return end
 local tab=tabOf()
 profilePanel:SetShown(tab=='profile');travelPanel:SetShown(tab=='travel');displayPanel:SetShown(tab=='display')
 tabs.profile:SetActive(tab=='profile');tabs.travel:SetActive(tab=='travel');tabs.display:SetActive(tab=='display')
 if tab=='profile' then Core.Profile.Refresh() elseif tab=='travel' then N.RefreshSettings() else Core.UI.RefreshDisplay() end
end
function Settings.Open(tab)
 Core.settingsTab=tab or 'profile';Core.UI.Open('settings')
end
local function create(parent)
 holder=CreateFrame('Frame',nil,parent);holder:SetSize(1078,658)
 travelPanel=createTravel(holder);travelPanel:SetPoint('TOPLEFT',0,0)
 displayPanel=Core.UI.CreateDisplayPanel(holder);displayPanel:SetPoint('TOPLEFT',0,0)
 profilePanel=Core.Profile.CreatePanel(holder);profilePanel:SetPoint('TOPLEFT',0,0)
 tabs={}
 tabs.display=S.Button(holder,'Affichage',130,28,'ghost');tabs.display:SetPoint('TOPLEFT',528,-4)
 tabs.profile=S.Button(holder,'Profil',130,28,'ghost');tabs.profile:SetPoint('TOPLEFT',668,-4)
 tabs.travel=S.Button(holder,'Voyages',130,28,'ghost');tabs.travel:SetPoint('TOPLEFT',808,-4)
 tabs.welcome=S.Button(holder,'Revoir l’accueil',130,28,'ghost');tabs.welcome:SetPoint('TOPLEFT',948,-4)
 for _,b in pairs(tabs) do b:SetFrameLevel(holder:GetFrameLevel()+10) end
 tabs.profile:SetScript('OnClick',function() Core.settingsTab='profile';Settings.Refresh() end)
 tabs.travel:SetScript('OnClick',function() Core.settingsTab='travel';Settings.Refresh() end)
 tabs.display:SetScript('OnClick',function() Core.settingsTab='display';Settings.Refresh() end)
 tabs.welcome:SetScript('OnClick',function() Core.Profile.ReplayWelcome() end)
 holder.tabs,holder.profile,holder.travel,holder.display=tabs,profilePanel,travelPanel,displayPanel
 holder.characters,holder.entrancePins=travelPanel.characters,travelPanel.entrancePins
 Settings.panel=holder;Settings.Refresh();return holder
end
Core:RegisterModule({ id='settings', title='Réglages', order=98,
 icon='Interface\\Icons\\Trade_Engineering',width=1078,height=658,
 create=create,refresh=Settings.Refresh,summary=function() return 'Affichage, profil, accueil et voyages : tes préférences.' end })
